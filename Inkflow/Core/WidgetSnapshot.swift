import Foundation

/// The widget never reads the full vault, previous revisions, or sync metadata.
public enum WidgetStorage {
    public static let kind = "QuandaoFavoriteClips"
    #if LOCAL_ONLY
    public static let groupID = "group.com.wssxzzzz.quandaotiehe.local"
    #else
    public static let groupID = "group.com.qdth.inkflow"
    #endif
    public static let filename = "widget-snapshot.json"
}

public struct WidgetClip: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public let isPinned: Bool
    public let isFavorite: Bool
    public let createdAt: Date

    public init(id: UUID, text: String, isPinned: Bool, isFavorite: Bool, createdAt: Date) {
        self.id = id; self.text = text; self.isPinned = isPinned
        self.isFavorite = isFavorite; self.createdAt = createdAt
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let isContentVisible: Bool
    public let clips: [WidgetClip]

    public init(clips: [WidgetClip] = [], isContentVisible: Bool = true) {
        version = 1
        self.isContentVisible = isContentVisible
        self.clips = isContentVisible ? clips.filter { $0.isPinned || $0.isFavorite }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }.prefix(6).map { clip in
                var bounded = clip
                bounded.text = String(clip.text.prefix(180))
                return bounded
            } : []
    }
}

public struct WidgetSnapshotRepository: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public var fileURL: URL { root.appendingPathComponent(WidgetStorage.filename) }

    public func load() throws -> WidgetSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return WidgetSnapshot() }
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 256 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
        let value = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: fileURL))
        guard value.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        // Also bound data read from a stale or externally modified snapshot.
        return WidgetSnapshot(clips: value.clips, isContentVisible: value.isContentVisible)
    }

    @discardableResult
    public func save(_ value: WidgetSnapshot) throws -> Bool {
        if (try? load()) == value, FileManager.default.fileExists(atPath: fileURL.path) { return false }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
        return true
    }
}
