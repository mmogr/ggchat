import Foundation

/// Everything the app remembers about a provider except its credentials.
/// The API key, ticket and token live in `Secrets` under `id`; a pipe config
/// keeps only a non-secret digest of its ticket so distinct tickets can be
/// counted (the kill-criterion reading).
public struct ProviderConfig: Identifiable, Codable, Sendable, Equatable, Hashable {
    public enum Kind: Codable, Sendable, Equatable, Hashable {
        case openAICompatible(baseURL: URL)
        case pipe(ticketDigest: String)
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var defaultModel: String?

    public init(id: UUID = UUID(), name: String, kind: Kind, defaultModel: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.defaultModel = defaultModel
    }

    public var isPipe: Bool {
        if case .pipe = kind { return true }
        return false
    }
}

extension ProviderConfig {
    /// A pasted address becomes a base URL: http or https only, a host is
    /// required, and a bare host or trailing slash gets `/v1` appended, which
    /// is what every OpenAI-compatible server serves.
    public static func normalizedBaseURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1" }
        components.path = path
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }
}
