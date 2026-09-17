import CloudKit
import Foundation
import Observation
import Network
import UIKit

/// CloudKit is deliberately created only after the user opts in. All callbacks
/// and UI edits share the main actor and the same atomic local transaction.
@MainActor @Observable
final class CloudSyncController: CKSyncEngineDelegate {
    static let containerID = "iCloud.com.qdth.inkflow"
    private static let zoneID = CKRecordZone.ID(zoneName: "QuanDaoTieHe")
    private static let recordType = "VaultItem"

    var status = "未开启 · 仅保存在本机"
    var issue: String?
    var isBusy = false
    @ObservationIgnored private weak var store: ClipStore?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var container: CKContainer?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var manualSync = false
    @ObservationIgnored private var failedThisCycle = false
    @ObservationIgnored private var verifiedThisCycle = false
    @ObservationIgnored private var inFlight: [String: SyncEnvelope] = [:]
    @ObservationIgnored private var assetFiles: [String: URL] = [:]
    @ObservationIgnored private var networkMonitor: NWPathMonitor?
    @ObservationIgnored private let assetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("QuanDaoTieHe-Sync-" + UUID().uuidString, isDirectory: true)

    init(store: ClipStore) { self.store = store }
    private var enabled: Bool { store?.index.sync?.enabled == true }
    private var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("--demo") }

    func setEnabled(_ value: Bool) async {
        guard let store else { return }
        if value && isDemo { issue = "演示模式不会连接 iCloud，请正常启动 App 后开启。"; return }
        guard store.persistSync({ index in
            if value { index.prepareSync() }
            index.sync?.enabled = value
        }) else { return }
        if value { await syncNow() }
        else {
            await stop()
            guard !enabled else { return }
            issue = nil
            status = "已关闭 · 本机和 iCloud 中的已有内容保留"
        }
    }

    func resume() async {
        guard enabled, !isDemo else { return }
        await syncNow()
    }

    private func start() async throws {
        guard engine == nil, enabled, !isDemo, let store, store.isReady else { return }
        guard store.index.sync?.zoneWasDeleted != true else { throw CloudSyncError.zoneRemoved }
        let token = generation
        status = "正在检查 iCloud 账号…"
        let cloud = container ?? CKContainer(identifier: Self.containerID)
        container = cloud
        let accountStatus = try await cloud.accountStatus()
        guard token == generation, enabled else { throw CancellationError() }
        guard accountStatus == .available else { throw CloudSyncError.accountUnavailable(accountStatus) }
        let account = try await cloud.userRecordID().recordName
        guard token == generation, enabled else { throw CancellationError() }
        var ledger = store.index.sync ?? SyncLedger()
        try ledger.bind(to: account)
        guard store.persistSync({ $0.sync?.accountID = ledger.accountID }) else { throw CloudSyncError.localWrite }
        let serialization = try store.index.sync?.engineState.map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        var configuration = CKSyncEngine.Configuration(database: cloud.privateCloudDatabase, stateSerialization: serialization, delegate: self)
        configuration.automaticallySync = true
        configuration.subscriptionID = "quandao-tiehe-private-sync"
        let newEngine = CKSyncEngine(configuration)
        engine = newEngine
        if store.index.sync?.zoneCreated != true {
            newEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
        enqueueDirtyRecords()
        UIApplication.shared.registerForRemoteNotifications()
    }

    func syncNow() async {
        guard enabled, !isDemo, !starting, !manualSync else { return }
        starting = true
        watchNetwork()
        let token = generation
        defer { if token == generation { starting = false } }
        do {
            try await start()
            guard token == generation, let engine, enabled else { return }
            manualSync = true; isBusy = true; failedThisCycle = false; verifiedThisCycle = false; issue = nil
            defer { if token == generation { manualSync = false; isBusy = false } }
            status = "正在同步…"
            // Fetch before send: apply remote tombstones before publishing offline edits.
            try await engine.fetchChanges()
            guard self.engine === engine, token == generation else { return }
            enqueueDirtyRecords()
            try await engine.sendChanges()
            guard self.engine === engine, token == generation else { return }
            try await engine.fetchChanges()
            guard self.engine === engine, token == generation else { return }
            verifiedThisCycle = true
            finishCycle()
        } catch is CancellationError { }
        catch {
            if token == generation { report(error) }
        }
    }

    func localDidChange() {
        guard enabled else { return }
        enqueueDirtyRecords()
        if !isBusy && issue == nil { status = "等待同步 · \(store?.index.sync?.pendingCount ?? 0) 项变更" }
    }

    private func enqueueDirtyRecords() {
        guard let engine, let ledger = store?.index.sync, ledger.enabled, !ledger.zoneWasDeleted else { return }
        let changes: [CKSyncEngine.PendingRecordZoneChange] = ledger.entries.filter { $0.value.dirty }.keys.sorted().map {
            .saveRecord(CKRecord.ID(recordName: $0, zoneID: Self.zoneID))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func stop() async {
        generation = UUID()
        networkMonitor?.cancel(); networkMonitor = nil
        let old = engine
        let oldAssets = Array(assetFiles.keys)
        engine = nil
        starting = false; manualSync = false; isBusy = false
        // Cancel outside delegate callbacks; waiting there could deadlock the engine.
        await old?.cancelOperations()
        for revision in oldAssets { cleanAsset(revision) }
    }

    private func watchNetwork() {
        guard networkMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, self.enabled, self.engine == nil || self.issue != nil else { return }
                await self.syncNow()
            }
        }
        monitor.start(queue: .main)
        networkMonitor = monitor
    }

    private func suspend(_ error: Error) {
        let old = engine
        let oldAssets = Array(assetFiles.keys)
        engine = nil
        generation = UUID()
        starting = false; manualSync = false; isBusy = false
        report(error)
        Task {
            await old?.cancelOperations()
            for revision in oldAssets { cleanAsset(revision) }
        }
    }

    /// Called only after an explicit UI confirmation. Never automatically recreate
    /// a cloud zone the user removed in iCloud settings / CloudKit Console.
    func reuploadAfterZoneRemoval() async {
        await stop()
        guard let store, store.persistSync({ index in
            index.sync?.zoneWasDeleted = false
            index.sync?.zoneCreated = false
            index.sync?.engineState = nil
            for key in Array(index.sync?.entries.keys ?? Dictionary<String, SyncEntry>().keys) {
                index.sync?.entries[key]?.systemFields = nil
                index.sync?.entries[key]?.dirty = true
            }
        }) else { return }
        await syncNow()
    }

    private func report(_ error: Error) {
        failedThisCycle = true
        issue = Self.message(for: error)
        status = "同步暂停 · 本机内容已保留"
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .networkFailure, .networkUnavailable: return "暂时无法连接网络。变更已保存在本机，联网后会重试，也可点“立即同步”。"
        case .notAuthenticated: return "请在系统设置登录 iCloud，并允许全岛铁盒使用 iCloud。"
        case .quotaExceeded: return "iCloud 空间不足，请释放空间后重试。本机内容不会丢失。"
        case .permissionFailure, .badContainer, .missingEntitlement, .badDatabase:
            return "此安装尚未正确配置 iCloud 权限或 CloudKit 容器。请按项目的 iCloud 配置说明完成开发者签名后重试。"
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud 服务暂时繁忙，会自动重试；请稍后查看同步状态。"
        default: return "iCloud 同步未完成（\(error.code.rawValue)）：\(error.localizedDescription)"
        }
    }

    private func persist(_ change: (inout VaultIndex) -> Void) -> Bool {
        guard let store, store.persistSync(change) else { suspend(CloudSyncError.localWrite); return false }
        return true
    }

    private func finishCycle() {
        guard !failedThisCycle, let store else { return }
        let pending = store.index.sync?.pendingCount ?? 0
        if pending == 0 {
            guard verifiedThisCycle else {
                status = issue == nil ? "暂无待上传变更" : "同步暂停 · 本机内容已保留"
                return
            }
            guard persist({ $0.sync?.lastSuccess = Date() }) else { return }
            issue = nil
            status = "已与 iCloud 同步"
        } else { status = issue == nil ? "等待同步 · \(pending) 项变更" : "同步暂停 · 本机内容已保留" }
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, enabled else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                let data = try JSONEncoder().encode(update.stateSerialization)
                // Remote data and cursor are persisted serially. On any failed write
                // suspend before accepting a newer cursor, so fetch can be replayed.
                _ = persist { $0.sync?.engineState = data }
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let account):
                    if store?.index.sync?.accountID != account.recordName { suspend(SyncDataError.differentAccount) }
                case .signOut: suspend(CloudSyncError.accountUnavailable(.noAccount))
                case .switchAccounts: suspend(SyncDataError.differentAccount)
                @unknown default: suspend(CloudSyncError.accountUnavailable(.couldNotDetermine))
                }
            case .fetchedDatabaseChanges(let changes):
                if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                    if persist({ $0.sync?.zoneWasDeleted = true }) { suspend(CloudSyncError.zoneRemoved) }
                }
            case .fetchedRecordZoneChanges(let changes):
                verifiedThisCycle = true
                var next = store!.index
                for modification in changes.modifications where modification.record.recordID.zoneID == Self.zoneID {
                    let record = modification.record
                    try next.mergeRemote(Self.decode(record), systemFields: try Self.systemFields(record))
                }
                // External hard deletions also become local tombstones. Normal app
                // deletions upload a content-free tombstone, never a hard delete.
                for deletion in changes.deletions where deletion.recordID.zoneID == Self.zoneID {
                    if let local = next.envelope(for: deletion.recordID.recordName) {
                        var tombstone = local
                        tombstone.deleted = true; tombstone.clip = nil; tombstone.workflow = nil
                        tombstone.clocks["deleted"] = next.sync?.tick(now: Date()) ?? .zero
                        try next.mergeRemote(tombstone)
                        next.sync?.entries[tombstone.key]?.systemFields = nil
                        next.sync?.entries[tombstone.key]?.dirty = true
                    }
                }
                if persist({ $0 = next }) { enqueueDirtyRecords() }
            case .sentDatabaseChanges(let changes):
                if changes.savedZones.contains(where: { $0.zoneID == Self.zoneID }) {
                    _ = persist { $0.sync?.zoneCreated = true }
                }
                if let failure = changes.failedZoneSaves.first { report(failure.error) }
            case .sentRecordZoneChanges(let changes):
                try await handleSent(changes, engine: syncEngine)
            case .willFetchChanges, .willSendChanges:
                if !manualSync { failedThisCycle = false; verifiedThisCycle = false }
                isBusy = true; status = "正在同步…"
            case .didFetchRecordZoneChanges(let result):
                if let error = result.error {
                    if error.code == .zoneNotFound && store?.index.sync?.zoneCreated != true { break }
                    report(error)
                } else { verifiedThisCycle = true }
            case .didFetchChanges, .didSendChanges:
                if !manualSync { isBusy = false; finishCycle() }
            case .willFetchRecordZoneChanges: break
            @unknown default: break
            }
        } catch { if engine === syncEngine { suspend(error) } }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, enabled, let store else { return nil }
        do {
            // Recheck identity at the upload boundary, not just on app launch.
            let account = try await container?.userRecordID().recordName
            guard engine === syncEngine, enabled else { return nil }
            guard account == store.index.sync?.accountID else { throw SyncDataError.differentAccount }
            var records: [CKRecord] = []
            for change in syncEngine.state.pendingRecordZoneChanges.filter({ context.options.scope.contains($0) }).prefix(40) {
                guard case .saveRecord(let id) = change, id.zoneID == Self.zoneID else { continue }
                guard let value = store.index.envelope(for: id.recordName), store.index.sync?.entries[id.recordName]?.dirty == true else {
                    syncEngine.state.remove(pendingRecordZoneChanges: [change]); continue
                }
                try value.validate()
                let record: CKRecord
                if let fields = store.index.sync?.entries[id.recordName]?.systemFields {
                    let decoder = try NSKeyedUnarchiver(forReadingFrom: fields)
                    decoder.requiresSecureCoding = true
                    guard let cached = CKRecord(coder: decoder), cached.recordID == id else { throw SyncDataError.invalidRecord }
                    decoder.finishDecoding()
                    record = cached
                } else { record = CKRecord(recordType: Self.recordType, recordID: id) }
                let revision = UUID().uuidString
                let folder = assetDirectory
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(revision + ".json")
                let data = try JSONEncoder().encode(value)
                guard data.count <= 48 * 1_024 * 1_024 else { throw CloudSyncError.payloadTooLarge }
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                record["payload"] = CKAsset(fileURL: url)
                record["revision"] = revision as CKRecordValue
                record["schemaVersion"] = 1 as CKRecordValue
                inFlight[revision] = value
                assetFiles[revision] = url
                records.append(record)
            }
            return records.isEmpty ? nil : CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records)
        } catch { if engine === syncEngine { suspend(error) }; return nil }
    }

    private func handleSent(_ changes: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) async throws {
        guard let store else { return }
        var conflicts: [CKRecord.ID: CKRecord] = [:]
        for failure in changes.failedRecordSaves where failure.error.code == .serverRecordChanged {
            guard let record = failure.error.serverRecord else { throw failure.error }
            if (record["payload"] as? CKAsset)?.fileURL != nil { conflicts[record.recordID] = record }
            else {
                // Conflict errors can omit the downloaded CKAsset. Fetch its full
                // contents before opening the local transaction, so UI edits made
                // while awaiting the network cannot be overwritten by a stale copy.
                conflicts[record.recordID] = try await engine.database.record(for: record.recordID)
            }
        }
        guard self.engine === engine, enabled else { return }
        var next = store.index
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var zoneRemoved = false
        for record in changes.savedRecords {
            verifiedThisCycle = true
            guard let revision = record["revision"] as? String, let sent = inFlight[revision] else { continue }
            next.acknowledge(sent, systemFields: try Self.systemFields(record))
        }
        for failure in changes.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                guard let remote = conflicts[id] else { throw failure.error }
                try next.mergeRemote(Self.decode(remote), systemFields: try Self.systemFields(remote))
                if next.sync?.entries[id.recordName]?.dirty == true { retry.append(.saveRecord(id)) }
            case .zoneNotFound:
                if next.sync?.zoneCreated == true {
                    next.sync?.zoneWasDeleted = true; zoneRemoved = true
                } else {
                    next.sync?.entries[id.recordName]?.systemFields = nil
                    engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                    retry.append(.saveRecord(id))
                }
            case .unknownItem:
                // An unsaved record may fail because its production schema is not
                // deployed. Only infer deletion if we have seen this record before.
                guard next.sync?.entries[id.recordName]?.systemFields != nil else { report(failure.error); continue }
                // A server hard-delete must not resurrect an old offline edit.
                if var tombstone = next.envelope(for: id.recordName) {
                    tombstone.deleted = true; tombstone.clip = nil; tombstone.workflow = nil
                    tombstone.clocks["deleted"] = next.sync?.tick(now: Date()) ?? .zero
                    try next.mergeRemote(tombstone)
                    next.sync?.entries[id.recordName]?.systemFields = nil
                    next.sync?.entries[id.recordName]?.dirty = true
                    retry.append(.saveRecord(id))
                }
            default:
                // CKSyncEngine retries transient failures. Our durable dirty ledger
                // also survives engine restarts and permanent failures for manual retry.
                report(failure.error)
            }
        }
        guard persist({ $0 = next }) else { return }
        for record in changes.savedRecords + changes.failedRecordSaves.map(\.record) {
            if let revision = record["revision"] as? String { cleanAsset(revision) }
        }
        if zoneRemoved { suspend(CloudSyncError.zoneRemoved); return }
        for record in changes.savedRecords where next.sync?.entries[record.recordID.recordName]?.dirty == true {
            retry.append(.saveRecord(record.recordID))
        }
        // Do not re-add every failed record here: permanent errors would cause
        // an unbounded send loop. Transient retries belong to CKSyncEngine;
        // other failures stay in our durable ledger until explicit/foreground retry.
        engine.state.add(pendingRecordZoneChanges: retry)
    }

    private static func decode(_ record: CKRecord) throws -> SyncEnvelope {
        guard record.recordType == recordType, (record["schemaVersion"] as? NSNumber)?.intValue == 1 else { throw SyncDataError.newerSchema }
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL,
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 64 * 1_024 * 1_024 else { throw SyncDataError.invalidRecord }
        let value = try JSONDecoder().decode(SyncEnvelope.self, from: Data(contentsOf: url))
        guard value.key == record.recordID.recordName else { throw SyncDataError.invalidRecord }
        try value.validate()
        return value
    }

    private static func systemFields(_ record: CKRecord) throws -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder)
        encoder.finishEncoding()
        return encoder.encodedData
    }

    private func cleanAsset(_ revision: String) {
        if let url = assetFiles.removeValue(forKey: revision) { try? FileManager.default.removeItem(at: url) }
        inFlight.removeValue(forKey: revision)
    }

}

private enum CloudSyncError: LocalizedError {
    case accountUnavailable(CKAccountStatus), localWrite, zoneRemoved, payloadTooLarge
    var errorDescription: String? {
        switch self {
        case .accountUnavailable(let status):
            switch status {
            case .noAccount: "请先在系统设置登录 iCloud，然后点“立即同步”。"
            case .restricted: "此设备的 iCloud 访问受到限制，请检查系统设置或设备管理策略。"
            default: "暂时无法确认 iCloud 账号，请检查网络后重试。"
            }
        case .localWrite: "本机资料库写入失败，已暂停同步以保护数据。请检查设备空间后重试。"
        case .zoneRemoved: "iCloud 中的资料库已被移除。本机内容保留；为防止自动传回已删除的数据，需要你确认后才能重新上传。"
        case .payloadTooLarge: "某条记录编码后超过云同步大小限制，请缩短该片段或清理特殊控制字符后重试。本机内容已保留。"
        }
    }
}
