import Foundation
import Testing
@testable import InkflowCore

@Test func flagsSurvivePersistenceAndRemainIndependent() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = VaultRepository(root: root)
    try repo.prepare()
    var index = VaultIndex()
    var pinned = Clip(text: "常用收件地址")
    pinned.isPinned = true
    var favorite = Clip(text: "值得留住的句子 🪴")
    favorite.isFavorite = true
    index.clips = [pinned, favorite]
    try repo.saveIndex(index)
    let loaded = try repo.loadIndex()
    #expect(loaded.clips[0].isPinned && !loaded.clips[0].isFavorite)
    #expect(!loaded.clips[1].isPinned && loaded.clips[1].isFavorite)
    #expect(loaded == index)
}

@Test func corruptIndexIsNeverReplacedByAnEmptyLibrary() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = VaultRepository(root: root)
    try repo.prepare()
    let bad = Data("{broken".utf8)
    try bad.write(to: repo.indexURL)
    #expect(throws: (any Error).self) { try repo.loadIndex() }
    #expect(try Data(contentsOf: repo.indexURL) == bad)
}

@Test func workflowsExecuteInOrderAndKeepUnicode() {
    let input = "  苹果🍎\r\n\r\n香蕉\r\n苹果🍎  "
    let steps: [ActionStep] = [.init(.trim), .init(.removeBlankLines), .init(.deduplicateLines), .init(.checklist)]
    #expect(TextActions.run(steps, on: input) == "- [ ] 苹果🍎\n- [ ] 香蕉")
    #expect(TextActions.run([.init(.replace, search: ".*", replacement: "文字")], on: "a.*b") == "a文字b")
    #expect(TextActions.run([.init(.replace)], on: "原文") == "原文")
}

@Test func urlEncodingIsReversibleAndEncodesReservedCharacters() {
    let text = "你好 + /?&= 🪴"
    let encoded = TextActions.run([.init(.urlEncode)], on: text)
    #expect(!encoded.contains("&"))
    #expect(!encoded.contains("+"))
    #expect(TextActions.run([.init(.urlDecode)], on: encoded) == text)
    #expect(TextActions.run([.init(.urlDecode)], on: "%zz") == "%zz")
}

@Test func backupMergePreservesBothFlagsAndDistinctContent() {
    var local = VaultIndex()
    var original = Clip(text: "相同的内容")
    original.isPinned = true
    local.clips = [original]
    var incoming = VaultIndex()
    var duplicate = Clip(text: "相同的内容")
    duplicate.isFavorite = true
    var collision = Clip(text: "不同的内容")
    collision.id = original.id
    incoming.clips = [duplicate, collision]
    local.merge(incoming)
    #expect(local.clips.count == 2)
    #expect(local.clips[0].isPinned && local.clips[0].isFavorite)
    #expect(Set(local.clips.map(\.id)).count == 2)
    local.merge(incoming)
    #expect(local.clips.count == 2)
    #expect(local.workflows.count == 4)
}

@Test func linkDetectionDoesNotTreatSentencesOrUnsafeSchemesAsLinks() {
    #expect(Clip(text: "https://apple.com").isLink)
    #expect(!Clip(text: "javascript:alert(1)").isLink)
    #expect(!Clip(text: "前往 https://apple.com 阅读").isLink)
    #expect(!Clip(text: "https://").isLink)
}

@Test func importedTextHandlesBOMAndRejectsBinary() throws {
    #expect(try VaultRepository.decode(Data([0xEF, 0xBB, 0xBF]) + Data("你好".utf8)) == "你好")
    #expect(try VaultRepository.decode("你好".data(using: .utf16)!) == "你好")
    #expect(throws: VaultError.self) { try VaultRepository.decode(Data([0xff, 0x01, 0x81])) }
}
