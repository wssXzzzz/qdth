import Foundation
import Testing
@testable import InkflowCore

private let baselineTime = Date(timeIntervalSince1970: 1_700_000_000)

private func initialLibrary() -> VaultIndex {
    var index = VaultIndex()
    var clip = Clip(text: "来自全岛铁盒的测试文字 🏝️")
    clip.createdAt = baselineTime
    clip.updatedAt = baselineTime
    index.clips = [clip]
    index.prepareSync(now: baselineTime)
    index.sync?.deviceID = "A"
    return index
}

private func edit(_ index: inout VaultIndex, at time: TimeInterval = 1, _ change: (inout VaultIndex) -> Void) {
    let old = index
    change(&index)
    index.trackChanges(from: old, now: baselineTime.addingTimeInterval(time))
}

@Test func oldBackupsMigrateWithoutLosingContentOrFlags() throws {
    var old = VaultIndex()
    var clip = Clip(text: "旧版内容")
    clip.isFavorite = true; clip.isPinned = true
    old.clips = [clip]
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    object.removeValue(forKey: "sync")
    var loaded = try JSONDecoder().decode(VaultIndex.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(loaded.sync == nil)
    loaded.prepareSync(now: baselineTime)
    #expect(loaded.clips == old.clips)
    #expect(loaded.sync?.enabled == false)
    #expect(loaded.sync?.pendingCount == 5)
    #expect(loaded.sync?.entries.values.allSatisfy(\.dirty) == true)
}

@Test func simultaneousPinAndFavoriteMergeIndependently() throws {
    var a = initialLibrary()
    var b = a; b.sync?.deviceID = "B"
    let key = SyncEnvelope.key(a.clips[0].id, kind: .clip)
    edit(&a) { $0.clips[0].isPinned = true }
    edit(&b) { $0.clips[0].isFavorite = true }
    let fromA = try #require(a.envelope(for: key)), fromB = try #require(b.envelope(for: key))
    try a.mergeRemote(fromB); try b.mergeRemote(fromA)
    #expect(a.clips == b.clips)
    #expect(a.clips[0].isFavorite && a.clips[0].isPinned)
    #expect(a.envelope(for: key) == b.envelope(for: key))
}

@Test func removingFavoriteIsNotUndoneByAnUnrelatedPin() throws {
    var a = initialLibrary()
    edit(&a) { $0.clips[0].isFavorite = true }
    var b = a; b.sync?.deviceID = "B"
    edit(&a, at: 2) { $0.clips[0].isFavorite = false }
    edit(&b, at: 3) { $0.clips[0].isPinned = true }
    let key = SyncEnvelope.key(a.clips[0].id, kind: .clip)
    try a.mergeRemote(#require(b.envelope(for: key)))
    #expect(!a.clips[0].isFavorite && a.clips[0].isPinned)
}

@Test func deletionWinsAgainstAnOfflineEditAndSurvivesRestart() throws {
    var a = initialLibrary()
    var b = a; b.sync?.deviceID = "B"
    let key = SyncEnvelope.key(a.clips[0].id, kind: .clip)
    edit(&a) { $0.clips.removeAll() }
    edit(&b, at: 100) { $0.clips[0].text = "晚些时候的离线修改" }
    a = try JSONDecoder().decode(VaultIndex.self, from: JSONEncoder().encode(a))
    let fromA = try #require(a.envelope(for: key)), fromB = try #require(b.envelope(for: key))
    try a.mergeRemote(fromB); try b.mergeRemote(fromA)
    #expect(a.clips.isEmpty && b.clips.isEmpty)
    #expect(a.envelope(for: key) == b.envelope(for: key))
    #expect(a.envelope(for: key)?.clip == nil)
    #expect(a.sync?.entries[key]?.deleted == true)
}

@Test func concurrentTextEditsConvergeDeterministically() throws {
    var a = initialLibrary()
    var b = a; b.sync?.deviceID = "B"
    let key = SyncEnvelope.key(a.clips[0].id, kind: .clip)
    edit(&a) { $0.clips[0].text = "A 修改" }
    edit(&b) { $0.clips[0].text = "B 修改" }
    let fromA = try #require(a.envelope(for: key)), fromB = try #require(b.envelope(for: key))
    try a.mergeRemote(fromB); try b.mergeRemote(fromA)
    #expect(a.clips == b.clips)
    #expect(a.clips[0].text == "B 修改")
    let stable = a.envelope(for: key)
    try a.mergeRemote(fromB)
    #expect(a.envelope(for: key) == stable)
}

@Test func observedFutureClockDoesNotPreventSubsequentLocalEdits() throws {
    var a = initialLibrary()
    var b = a; b.sync?.deviceID = "B"
    let key = SyncEnvelope.key(a.clips[0].id, kind: .clip)
    edit(&b, at: 86_400) { $0.clips[0].text = "快一天的时钟" }
    try a.mergeRemote(#require(b.envelope(for: key)))
    edit(&a, at: 2) { $0.clips[0].text = "读取后再次修改" }
    try b.mergeRemote(#require(a.envelope(for: key)))
    #expect(a.clips == b.clips)
    #expect(b.clips[0].text == "读取后再次修改")
}

@Test func inFlightAcknowledgementCannotClearNewerChanges() throws {
    var index = initialLibrary()
    let key = SyncEnvelope.key(index.clips[0].id, kind: .clip)
    let sent = try #require(index.envelope(for: key))
    edit(&index) { $0.clips[0].isPinned = true }
    index.acknowledge(sent, systemFields: Data([1, 2]))
    #expect(index.sync?.entries[key]?.dirty == true)
    let latest = try #require(index.envelope(for: key))
    index.acknowledge(latest, systemFields: Data([3, 4]))
    #expect(index.sync?.entries[key]?.dirty == false)
    #expect(index.sync?.entries[key]?.systemFields == Data([3, 4]))
}

@Test func accountBindingRejectsCrossAccountUpload() throws {
    var ledger = SyncLedger()
    try ledger.bind(to: "account-A")
    try ledger.bind(to: "account-A")
    #expect(throws: SyncDataError.self) { try ledger.bind(to: "account-B") }
    #expect(ledger.accountID == "account-A")
}

@Test func backupExcludesCloudIdentityCursorsAndTombstones() throws {
    var index = initialLibrary()
    index.sync?.accountID = "not-for-export"
    index.sync?.engineState = Data("private-cursor".utf8)
    let exported = try JSONEncoder().encode(index.portableBackup)
    let text = String(decoding: exported, as: UTF8.self)
    #expect(!text.contains("not-for-export") && !text.contains("private-cursor"))
    #expect(index.portableBackup.clips == index.clips)
    #expect(index.portableBackup.sync == nil)
}

@Test func restoringDeletedBackupCreatesANewIdentity() throws {
    var index = initialLibrary()
    let backup = index.portableBackup
    let deletedID = index.clips[0].id
    edit(&index) { $0.clips.removeAll() }
    edit(&index, at: 2) { $0.merge(backup) }
    #expect(index.clips.count == 1)
    #expect(index.clips[0].id != deletedID)
    #expect(index.sync?.entries[SyncEnvelope.key(deletedID, kind: .clip)]?.deleted == true)
}

@Test func workflowEditsAndDeletesSyncWithoutDuplicatingPresets() throws {
    var a = initialLibrary()
    var b = VaultIndex(); b.prepareSync(now: baselineTime.addingTimeInterval(10))
    #expect(a.workflows == b.workflows)
    let workflowID = a.workflows[0].id
    let key = SyncEnvelope.key(workflowID, kind: .workflow)
    edit(&a) { $0.workflows[0].name = "自定义动作" }
    try b.mergeRemote(#require(a.envelope(for: key)))
    #expect(b.workflows.count == 4)
    #expect(b.workflows.first(where: { $0.id == workflowID })?.name == "自定义动作")
    edit(&a, at: 2) { $0.workflows.removeAll { $0.id == workflowID } }
    try b.mergeRemote(#require(a.envelope(for: key)))
    #expect(b.workflows.count == 3)
}

@Test func disabledSyncStillTracksOfflineChanges() {
    var index = initialLibrary()
    let key = SyncEnvelope.key(index.clips[0].id, kind: .clip)
    index.sync?.entries[key]?.dirty = false
    index.sync?.enabled = false
    edit(&index) { $0.clips[0].isFavorite = true }
    #expect(index.sync?.entries[key]?.dirty == true)
    #expect(index.sync?.enabled == false)
}

@Test func malformedRemoteRecordCannotModifyLibrary() throws {
    var index = initialLibrary()
    let key = SyncEnvelope.key(index.clips[0].id, kind: .clip)
    var remote = try #require(index.envelope(for: key))
    remote.schema = 999
    let before = index
    #expect(throws: SyncDataError.self) { try index.mergeRemote(remote) }
    #expect(index == before)
    remote.schema = 1; remote.key = "clip:malformed"
    #expect(throws: SyncDataError.self) { try index.mergeRemote(remote) }
    #expect(index == before)
}

@Test func syncStateAndOfflineQueuePersistTogether() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = VaultRepository(root: root)
    try repository.prepare()
    var index = initialLibrary()
    index.sync?.engineState = Data("cursor".utf8)
    edit(&index) { $0.clips[0].isFavorite = true }
    try repository.saveIndex(index)
    #expect(try repository.loadIndex() == index)
}

@Test func savingAStaleWorkflowEditorCreatesANewIdentity() {
    var index = initialLibrary()
    var stale = index.workflows[0]
    let deletedID = stale.id
    edit(&index) { $0.workflows.removeAll { $0.id == deletedID } }
    stale.name = "删除后仍想保留的编辑"
    edit(&index, at: 2) { $0.workflows.append(stale) }
    #expect(index.workflows.last?.id != deletedID)
    #expect(index.sync?.entries[SyncEnvelope.key(deletedID, kind: .workflow)]?.deleted == true)
    #expect(index.workflows.last?.name == stale.name)
}

@Test func multiDeviceMergesAreAssociativeAndIdempotent() throws {
    let base = initialLibrary()
    let key = SyncEnvelope.key(base.clips[0].id, kind: .clip)
    var a = base, b = base, c = base
    a.sync?.deviceID = "A"; b.sync?.deviceID = "B"; c.sync?.deviceID = "C"
    edit(&a) { $0.clips[0].text = "设备 A 的内容" }
    edit(&b) { $0.clips[0].isPinned = true }
    edit(&c) { $0.clips[0].isFavorite = true }
    let records = try [a, b, c].map { try #require($0.envelope(for: key)) }
    var first = base, second = base
    for record in records { try first.mergeRemote(record) }
    for record in records.reversed() { try second.mergeRemote(record) }
    #expect(first.envelope(for: key) == second.envelope(for: key))
    let state = first.envelope(for: key)
    for record in records { try first.mergeRemote(record) }
    #expect(first.envelope(for: key) == state)
    #expect(first.clips[0].isPinned && first.clips[0].isFavorite)
}

@Test func importingBackupCannotChangeAccountBinding() throws {
    var local = initialLibrary()
    try local.sync?.bind(to: "my-account")
    var incoming = initialLibrary()
    try incoming.sync?.bind(to: "other-account")
    local.merge(incoming)
    #expect(local.sync?.accountID == "my-account")
}
