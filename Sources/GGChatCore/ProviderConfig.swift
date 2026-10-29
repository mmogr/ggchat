import Foundation

/// Everything the app remembers about a provider except its credentials.
/// The API key, ticket and token live in `Secrets` under `id`; a pipe config
/// keeps only a non-secret digest of its ticket so distinct tickets can be
/// counted (the kill-criterion reading). The engine on this device keeps
/// nothing there: it hands each session a key of its own.
public struct ProviderConfig: Identifiable, Codable, Sendable, Equatable, Hashable {
    public enum Kind: Codable, Sendable, Equatable, Hashable {
        case openAICompatible(baseURL: URL)
        case pipe(ticketDigest: String)
        /// The engine on this device, which serves gglib at a loopback
        /// address of its own (`LocalEngine`). No payload: a device has one
        /// engine, so it has one such provider, and the address and the key
        /// are the session's, not the provider's.
        case onDevice
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

    /// Whether the provider has a session to bring up and tear down: a pipe
    /// is dialled before anything goes through it, a send waits for it
    /// (ADR 0006), and it is hung up on the way to the background. The
    /// engine on this device is served before anything goes to it. A server
    /// by address has none.
    public var hasSession: Bool {
        switch kind {
        case .openAICompatible: false
        case .pipe, .onDevice: true
        }
    }

    /// Whether the provider is a paired Mac: a gglib hub with chats of its
    /// own, runs, drawing and MCP servers, which only a device it has paired
    /// reaches. The engine on this device is gglib without any of those.
    public var isPairedMac: Bool {
        switch kind {
        case .openAICompatible, .onDevice: false
        case .pipe: true
        }
    }

    /// Whether the provider is a modelpipe pipe, dialled with the ticket and
    /// token `Secrets` keeps under its id.
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
