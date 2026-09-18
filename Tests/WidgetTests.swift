import Foundation
import Testing
@testable import InkflowCore

private func widgetClip(_ text: String, pinned: Bool = false, favorite: Bool = false, time: Double = 0) -> WidgetClip {
    WidgetClip(id: UUID(), text: text, isPinned: pinned, isFavorite: favorite, createdAt: Date(timeIntervalSince1970: time))
}

@Test func widgetOnlyPublishesPinnedAndFavoriteText() {
    let snapshot = WidgetSnapshot(clips: [
        widgetClip("普通历史，不上桌面", time: 100),
        widgetClip("收藏", favorite: true, time: 90),
        widgetClip("置顶", pinned: true, time: 10),
        widgetClip("较新的置顶", pinned: true, favorite: true, time: 20)
    ])
    #expect(snapshot.clips.map(\.text) == ["较新的置顶", "置顶", "收藏"])
}

@Test func widgetBoundsSnapshotAndHidesAllTextWhenDisabled() {
    let clips = (0..<15).map { widgetClip(String(repeating: "🧑🏽‍💻好", count: 200), favorite: true, time: Double($0)) }
    let snapshot = WidgetSnapshot(clips: clips)
    #expect(snapshot.clips.count == 6)
    #expect(snapshot.clips.allSatisfy { $0.text.count == 180 })
    let hidden = WidgetSnapshot(clips: clips, isContentVisible: false)
    #expect(hidden.clips.isEmpty)
    #expect(!hidden.isContentVisible)
}

@Test func widgetSnapshotTracksEditsDeletesAndPrivacy() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = WidgetSnapshotRepository(root: root)
    #expect(try repository.load().clips.isEmpty)
    let original = WidgetSnapshot(clips: [widgetClip("常用文字", pinned: true)])
    #expect(try repository.save(original))
    #expect(try !repository.save(original))
    #expect(try repository.load() == original)
    var edited = original.clips[0]
    edited.text = "已修改"
    #expect(try repository.save(WidgetSnapshot(clips: [edited])))
    #expect(try repository.load().clips.first?.text == "已修改")
    #expect(try repository.save(WidgetSnapshot()))
    #expect(try repository.load().clips.isEmpty)
    try repository.save(original)
    try repository.save(WidgetSnapshot(clips: original.clips, isContentVisible: false))
    #expect(try !repository.load().isContentVisible)
    #expect(try !String(contentsOf: repository.fileURL, encoding: .utf8).contains("常用文字"))
}

@Test func widgetRejectsCorruptAndOversizedSnapshots() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = WidgetSnapshotRepository(root: root)
    try repository.save(WidgetSnapshot())
    try Data("broken".utf8).write(to: repository.fileURL)
    #expect(throws: (any Error).self) { try repository.load() }
    try Data(repeating: 0, count: 256 * 1_024 + 1).write(to: repository.fileURL)
    #expect(throws: (any Error).self) { try repository.load() }
}

@Test func widgetRoutesRoundTripAndRejectUntrustedActions() {
    for route: WidgetRoute in [.library, .favorites, .capture, .clip(UUID())] {
        #expect(WidgetRoute(url: route.url) == route)
    }
    for raw in ["https://library", "quandaotiehe://delete", "quandaotiehe://clip/not-a-uuid",
                "quandaotiehe://library?copy=secret", "quandaotiehe://favorites/extra",
                "quandaotiehe://capture#text", "quandaotiehe://user@capture"] {
        #expect(WidgetRoute(url: URL(string: raw.replacingOccurrences(of: "quandaotiehe:", with: "\(WidgetRoute.scheme):"))!) == nil)
    }
}

@Test func widgetVersionsUseSeparateSharedContainers() {
    #if LOCAL_ONLY
    #expect(WidgetStorage.groupID == "group.com.wssxzzzz.quandaotiehe.local")
    #else
    #expect(WidgetStorage.groupID == "group.com.qdth.inkflow")
    #endif
}
