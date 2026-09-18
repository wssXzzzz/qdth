import Foundation

/// URLs select a screen only. They never import text, copy, or delete content.
public enum WidgetRoute: Equatable, Sendable {
    case library, favorites, capture, clip(UUID)
    #if LOCAL_ONLY
    public static let scheme = "quandaotiehe-local"
    #else
    public static let scheme = "quandaotiehe"
    #endif

    public var url: URL {
        let path: String
        switch self {
        case .library: path = "library"
        case .favorites: path = "favorites"
        case .capture: path = "capture"
        case .clip(let id): path = "clip/\(id.uuidString)"
        }
        return URL(string: "\(Self.scheme)://\(path)")!
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        switch components.host {
        case "library" where components.path.isEmpty: self = .library
        case "favorites" where components.path.isEmpty: self = .favorites
        case "capture" where components.path.isEmpty: self = .capture
        case "clip":
            let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].isEmpty, let id = UUID(uuidString: String(parts[1])) else { return nil }
            self = .clip(id)
        default: return nil
        }
    }
}
