import Foundation
import WidgetKit

enum WidgetBridge {
    static func publish(_ clips: [Clip], visible: Bool) throws {
        guard !ProcessInfo.processInfo.arguments.contains("--demo") else { return }
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetStorage.groupID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let snapshot = WidgetSnapshot(clips: clips.filter { $0.isPinned || $0.isFavorite }.map {
            WidgetClip(id: $0.id, text: $0.text, isPinned: $0.isPinned, isFavorite: $0.isFavorite, createdAt: $0.createdAt)
        }, isContentVisible: visible)
        if try WidgetSnapshotRepository(root: root).save(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetStorage.kind)
        }
    }
}
