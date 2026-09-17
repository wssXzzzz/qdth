import Foundation

public enum VaultError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidText
    case oversizedFile
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "资料库版本 \(version) 较新，请升级全岛铁盒后再打开。"
        case .invalidText: "无法读取文本编码，请转换为 UTF-8 后重试。"
        case .oversizedFile: "文件超过 5 MB，请拆分为较小的文本后导入。"
        }
    }
}

/// The caller serializes operations. A single atomic index contains the full
/// library, including previous text revisions, favorites and pinned state.
public struct VaultRepository: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public var indexURL: URL { root.appendingPathComponent("index.json") }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func loadIndex() throws -> VaultIndex {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return VaultIndex() }
        let value = try JSONDecoder().decode(VaultIndex.self, from: Data(contentsOf: indexURL))
        guard value.version == 1 else { throw VaultError.unsupportedVersion(value.version) }
        return value
    }

    public func saveIndex(_ index: VaultIndex) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    public static func decode(_ data: Data) throws -> String {
        guard data.count <= 5 * 1_024 * 1_024 else { throw VaultError.oversizedFile }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .utf8) { return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text }
        throw VaultError.invalidText
    }
}
