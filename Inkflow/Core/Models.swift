import Foundation

public struct Clip: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var text: String
    public var createdAt: Date = Date()
    public var isPinned: Bool = false
    public var isFavorite: Bool = false
    public var updatedAt: Date = Date()
    public var source: String = "剪贴板"
    public var previousText: String? = nil
    public init(text: String) { self.text = text }
    public var title: String {
        String((text.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "空白片段").prefix(100))
    }
    public var isLink: Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: { $0.isWhitespace }), let url = URL(string: value) else { return false }
        return ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }
}

public enum TransformKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case trim, removeBlankLines, deduplicateLines, sortLines, uppercase, lowercase, quote, checklist, urlEncode, urlDecode, replace
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .trim: "清理首尾空白"
        case .removeBlankLines: "移除空行"
        case .deduplicateLines: "去除重复行"
        case .sortLines: "按行排序"
        case .uppercase: "转换为大写"
        case .lowercase: "转换为小写"
        case .quote: "转换为引用"
        case .checklist: "转换为待办"
        case .urlEncode: "URL 编码"
        case .urlDecode: "URL 解码"
        case .replace: "查找与替换"
        }
    }
}

public struct ActionStep: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var kind: TransformKind
    public var search: String = ""
    public var replacement: String = ""
    public init(_ kind: TransformKind, search: String = "", replacement: String = "") {
        self.kind = kind; self.search = search; self.replacement = replacement
    }
}

public struct Workflow: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var symbol: String
    public var steps: [ActionStep]
    public init(name: String, symbol: String = "bolt", steps: [ActionStep]) {
        self.name = name; self.symbol = symbol; self.steps = steps
    }
    public static let presets: [Workflow] = [
        Workflow(name: "整理一段文字", symbol: "sparkles", steps: [.init(.trim), .init(.removeBlankLines)]),
        Workflow(name: "清单去重", symbol: "line.3.horizontal.decrease", steps: [.init(.trim), .init(.deduplicateLines)]),
        Workflow(name: "生成待办清单", symbol: "checklist", steps: [.init(.trim), .init(.removeBlankLines), .init(.checklist)]),
        Workflow(name: "整理为引用", symbol: "text.quote", steps: [.init(.trim), .init(.quote)])
    ].enumerated().map { index, value in
        var result = value
        // Stable identities keep the built-in actions from multiplying on each device.
        result.id = UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 1))!
        result.steps = value.steps.enumerated().map { stepIndex, step in
            var step = step
            step.id = UUID(uuidString: String(format: "20000000-0000-0000-%04d-%012d", index + 1, stepIndex + 1))!
            return step
        }
        return result
    }
}

public struct VaultIndex: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var clips: [Clip] = []
    public var workflows: [Workflow] = Workflow.presets
    public var sync: SyncLedger? = nil
    public init() {}
}

public enum TextActions {
    public static func run(_ steps: [ActionStep], on input: String) -> String {
        steps.reduce(input) { text, step in
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let lines = normalized.components(separatedBy: "\n")
            switch step.kind {
            case .trim: return text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .removeBlankLines: return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
            case .deduplicateLines:
                var seen = Set<String>()
                return lines.filter { seen.insert($0).inserted }.joined(separator: "\n")
            case .sortLines: return lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
            case .uppercase: return text.uppercased()
            case .lowercase: return text.lowercased()
            case .quote: return lines.map { "> " + $0 }.joined(separator: "\n")
            case .checklist: return lines.map { "- [ ] " + $0 }.joined(separator: "\n")
            case .urlEncode: return text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? text
            case .urlDecode: return text.removingPercentEncoding ?? text
            case .replace: return step.search.isEmpty ? text : text.replacingOccurrences(of: step.search, with: step.replacement)
            }
        }
    }
}
