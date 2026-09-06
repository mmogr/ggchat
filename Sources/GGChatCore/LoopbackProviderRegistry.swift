import Foundation
import Synchronization

/// Lets a mock pipe session hand out a loopback base URL that no socket
/// listens on, by registering an in-process provider for that URL. The app
/// asks here first when it builds a provider for a base URL; a real pipe's
/// URL is never registered, so it falls through to `OpenAICompatibleProvider`.
public final class LoopbackProviderRegistry: Sendable {
    public static let shared = LoopbackProviderRegistry()

    private let providers = Mutex<[URL: any Provider]>([:])
    private let nextPort = Mutex<Int>(49152)

    public init() {}

    /// Mints an unused loopback base URL and binds `provider` to it.
    public func register(_ provider: any Provider) -> URL {
        let port = nextPort.withLock { port in
            defer { port += 1 }
            return port
        }
        let url = URL(string: "http://127.0.0.1:\(port)/v1")!
        providers.withLock { $0[url] = provider }
        return url
    }

    /// Binds `provider` to a base URL chosen by the caller, for a mock that
    /// has to answer at the same address after a relaunch.
    public func register(_ provider: any Provider, at baseURL: URL) {
        providers.withLock { $0[baseURL] = provider }
    }

    public func provider(for baseURL: URL) -> (any Provider)? {
        providers.withLock { $0[baseURL] }
    }

    public func unregister(_ baseURL: URL) {
        providers.withLock { _ = $0.removeValue(forKey: baseURL) }
    }

    /// The one place a base URL becomes a `Provider`.
    public func makeProvider(baseURL: URL, apiKey: String?, log: any LogSink = NoopLogSink()) -> any Provider {
        provider(for: baseURL) ?? OpenAICompatibleProvider(baseURL: baseURL, apiKey: apiKey, log: log)
    }
}
