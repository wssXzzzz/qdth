import Foundation

/// Hybrid logical clock: observed remote edits always precede the next local edit,
/// even when device clocks differ. Device ID is the deterministic tie breaker.
public struct SyncStamp: Codable, Equatable, Comparable, Sendable {
    public var milliseconds: Int64
    public var counter: Int64
    public var device: String
    public static let zero = SyncStamp(milliseconds: 0, counter: 0, device: "")

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.milliseconds != rhs.milliseconds { return lhs.milliseconds < rhs.milliseconds }
        if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
        return lhs.device < rhs.device
    }
}

public enum SyncKind: String, Codable, Sendable { case clip, workflow }

/// No Apple account or transport metadata is included in this cloud payload.
public struct SyncEnvelope: Codable, Equatable, Sendable {
    public var schema = 1
    public var key: String
    public var kind: SyncKind
    public var clocks: [String: SyncStamp]
    public var deleted: Bool
    public var clip: Clip?
    public var workflow: Workflow?

    public func validate() throws {
        guard schema == 1 else { throw SyncDataError.newerSchema }
        let prefix = kind.rawValue + ":"
        guard key.hasPrefix(prefix), UUID(uuidString: String(key.dropFirst(prefix.count))) != nil,
              clocks.count <= 8, clocks.values.allSatisfy({ $0.counter >= 0 && $0.counter < 1_000_000_000_000 && $0.device.count <= 100 }) else {
            throw SyncDataError.invalidRecord
        }
        if deleted {
            guard clip == nil, workflow == nil, clocks["deleted"] != nil else { throw SyncDataError.invalidRecord }
        } else if kind == .clip {
            guard let clip, workflow == nil, key == Self.key(clip.id, kind: .clip),
                  clip.text.utf8.count <= 5 * 1_024 * 1_024,
                  (clip.previousText?.utf8.count ?? 0) <= 5 * 1_024 * 1_024,
                  ["content", "pin", "favorite", "origin"].allSatisfy({ clocks[$0] != nil }) else { throw SyncDataError.invalidRecord }
        } else {
            guard let workflow, clip == nil, key == Self.key(workflow.id, kind: .workflow),
                  clocks["content"] != nil, workflow.steps.count <= 10_000 else { throw SyncDataError.invalidRecord }
        }
    }

    public static func key(_ id: UUID, kind: SyncKind) -> String { kind.rawValue + ":" + id.uuidString }
}

public struct SyncEntry: Codable, Equatable, Sendable {
    public var kind: SyncKind
    public var clocks: [String: SyncStamp]
    public var deleted = false
    public var dirty = true
    public var systemFields: Data? = nil
}

public struct SyncLedger: Codable, Equatable, Sendable {
    public var deviceID = UUID().uuidString
    public var accountID: String? = nil
    public var enabled = false
    public var clock = SyncStamp.zero
    public var entries: [String: SyncEntry] = [:]
    public var engineState: Data? = nil
    public var zoneCreated = false
    public var zoneWasDeleted = false
    public var lastSuccess: Date? = nil

    public init() {}
    public var pendingCount: Int { entries.values.filter(\.dirty).count }

    public mutating func tick(now: Date) -> SyncStamp {
        let time = Int64(now.timeIntervalSince1970 * 1_000)
        clock = SyncStamp(milliseconds: max(time, clock.milliseconds), counter: time > clock.milliseconds ? 0 : clock.counter + 1, device: deviceID)
        return clock
    }

    public mutating func bind(to account: String) throws {
        guard accountID == nil || accountID == account else { throw SyncDataError.differentAccount }
        accountID = account
    }
}

public enum SyncDataError: LocalizedError {
    case newerSchema, invalidRecord, differentAccount
    public var errorDescription: String? {
        switch self {
        case .newerSchema: "iCloud 数据格式较新，请更新全岛铁盒后再同步。"
        case .invalidRecord: "iCloud 记录未通过校验，已暂停同步，本机内容未被覆盖。"
        case .differentAccount: "当前 iCloud 账号与本资料库绑定的账号不同。同步已暂停，本机内容保留且不会上传到新账号；请换回原账号。"
        }
    }
}

extension VaultIndex {
    /// Called once, before first opt-in. Old v1 libraries remain readable.
    public mutating func prepareSync(now: Date = Date()) {
        guard sync == nil else { return }
        // Canonicalize only untouched built-ins from the pre-sync version.
        var seen = Set<UUID>()
        workflows = workflows.compactMap { value in
            let canonical = Workflow.presets.first(where: {
                $0.name == value.name && $0.symbol == value.symbol &&
                $0.steps.map(\.kind) == value.steps.map(\.kind) &&
                value.steps.allSatisfy { $0.search.isEmpty && $0.replacement.isEmpty }
            }) ?? value
            return seen.insert(canonical.id).inserted ? canonical : nil
        }
        sync = SyncLedger()
        var empty = VaultIndex()
        empty.workflows = []
        trackChanges(from: empty, now: now)
    }

    /// Run in the same atomic transaction as the user's edit (including while offline/disabled).
    public mutating func trackChanges(from old: VaultIndex, now: Date = Date()) {
        guard var ledger = sync else { return }
        // An editor or backup may reintroduce a deleted ID. An explicit new save
        // becomes a new identity instead of reviving a tombstoned cloud record.
        for i in clips.indices where ledger.entries[SyncEnvelope.key(clips[i].id, kind: .clip)]?.deleted == true { clips[i].id = UUID() }
        for i in workflows.indices where ledger.entries[SyncEnvelope.key(workflows[i].id, kind: .workflow)]?.deleted == true { workflows[i].id = UUID() }
        let stamp = ledger.tick(now: now)
        let oldClips = Dictionary(old.clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for i in clips.indices {
            let value = clips[i]
            let key = SyncEnvelope.key(value.id, kind: .clip)
            // Deleted identities are never resurrected. Import must allocate a new identity.
            if ledger.entries[key]?.deleted == true { continue }
            let previous = oldClips[value.id]
            var entry = ledger.entries[key] ?? SyncEntry(kind: .clip, clocks: [:])
            if previous?.text != value.text || previous?.previousText != value.previousText || entry.clocks["content"] == nil {
                entry.clocks["content"] = stamp; entry.dirty = true
            }
            if previous?.isPinned != value.isPinned || entry.clocks["pin"] == nil { entry.clocks["pin"] = stamp; entry.dirty = true }
            if previous?.isFavorite != value.isFavorite || entry.clocks["favorite"] == nil { entry.clocks["favorite"] = stamp; entry.dirty = true }
            if previous?.createdAt != value.createdAt || previous?.source != value.source || entry.clocks["origin"] == nil { entry.clocks["origin"] = stamp; entry.dirty = true }
            if let previous, previous != value { clips[i].updatedAt = max(previous.updatedAt, now) }
            ledger.entries[key] = entry
        }
        let oldWorkflows = Dictionary(old.workflows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for value in workflows {
            let key = SyncEnvelope.key(value.id, kind: .workflow)
            if ledger.entries[key]?.deleted == true { continue }
            if oldWorkflows[value.id] != value || ledger.entries[key] == nil {
                var entry = ledger.entries[key] ?? SyncEntry(kind: .workflow, clocks: [:])
                entry.clocks["content"] = oldWorkflows[value.id] == nil && Workflow.presets.contains(value) ? .zero : stamp
                entry.dirty = true
                ledger.entries[key] = entry
            }
        }
        let liveKeys = Set(clips.map { SyncEnvelope.key($0.id, kind: .clip) } + workflows.map { SyncEnvelope.key($0.id, kind: .workflow) })
        for key in Array(ledger.entries.keys) where !liveKeys.contains(key) && ledger.entries[key]?.deleted == false {
            ledger.entries[key]?.deleted = true
            ledger.entries[key]?.clocks["deleted"] = stamp
            ledger.entries[key]?.dirty = true
        }
        sync = ledger
    }

    public func envelope(for key: String) -> SyncEnvelope? {
        guard let entry = sync?.entries[key] else { return nil }
        return SyncEnvelope(key: key, kind: entry.kind, clocks: entry.clocks, deleted: entry.deleted,
                            clip: entry.deleted ? nil : clips.first { SyncEnvelope.key($0.id, kind: .clip) == key },
                            workflow: entry.deleted ? nil : workflows.first { SyncEnvelope.key($0.id, kind: .workflow) == key })
    }

    /// Deterministic field-level merge. A tombstone always wins for an identity;
    /// pin and favorite have independent clocks so they cannot undo each other.
    public mutating func mergeRemote(_ remote: SyncEnvelope, systemFields: Data? = nil) throws {
        try remote.validate()
        guard var ledger = sync else { throw SyncDataError.invalidRecord }
        for stamp in remote.clocks.values { ledger.clock = max(ledger.clock, stamp) }
        let local = envelope(for: remote.key)
        var merged = remote
        if let local {
            merged = local
            for (field, stamp) in remote.clocks { merged.clocks[field] = max(merged.clocks[field] ?? .zero, stamp) }
            merged.deleted = local.deleted || remote.deleted
            if !merged.deleted {
                func newer(_ field: String) -> Bool { (remote.clocks[field] ?? .zero) > (local.clocks[field] ?? .zero) }
                if var clip = local.clip, let incoming = remote.clip {
                    if newer("content") { clip.text = incoming.text; clip.previousText = incoming.previousText }
                    if newer("pin") { clip.isPinned = incoming.isPinned }
                    if newer("favorite") { clip.isFavorite = incoming.isFavorite }
                    if newer("origin") { clip.createdAt = incoming.createdAt; clip.source = incoming.source }
                    clip.updatedAt = max(clip.updatedAt, incoming.updatedAt)
                    merged.clip = clip
                }
                if newer("content"), remote.kind == .workflow { merged.workflow = remote.workflow }
            }
        }
        if merged.deleted { merged.clip = nil; merged.workflow = nil }
        clips.removeAll { SyncEnvelope.key($0.id, kind: .clip) == remote.key }
        workflows.removeAll { SyncEnvelope.key($0.id, kind: .workflow) == remote.key }
        if let clip = merged.clip { clips.append(clip) }
        if let workflow = merged.workflow { workflows.append(workflow) }
        clips.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
        workflows.sort { $0.id.uuidString < $1.id.uuidString }
        ledger.entries[remote.key] = SyncEntry(kind: merged.kind, clocks: merged.clocks, deleted: merged.deleted,
                                             dirty: merged != remote, systemFields: systemFields ?? ledger.entries[remote.key]?.systemFields)
        sync = ledger
    }

    /// Never acknowledge a newer local edit with an older, in-flight upload.
    public mutating func acknowledge(_ sent: SyncEnvelope, systemFields: Data?) {
        guard sync?.entries[sent.key] != nil else { return }
        let stillDirty = envelope(for: sent.key) != sent
        sync?.entries[sent.key]?.systemFields = systemFields
        sync?.entries[sent.key]?.dirty = stillDirty
    }

    /// Backups are portable content, not device/account credentials or sync cursors.
    public var portableBackup: VaultIndex {
        var result = self
        result.sync = nil
        return result
    }
}
