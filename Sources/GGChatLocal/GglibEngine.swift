import Foundation
import GGChatCore
import GGLib

/// gglib's own engine on this device: gglib's proxy on a loopback port, in
/// front of llama.cpp running in this process, served by the library's
/// `serve(reading:)`. Chat never crosses the binding: the session hands back
/// the proxy's base URL and key, and the ordinary OpenAI-compatible provider
/// talks to that (ADR 0001).
///
/// The engine opens no library of its own. It is served from the one
/// `GglibLibrary` opens, asked for at each serve, so the engine and the
/// model library share one library over one `gglib.db`, and an open that
/// failed is tried again by whichever asks next.
public struct GglibEngine: LocalEngine {
    /// How the library is reached: `GglibLibrary`'s handle, or a test's
    /// fake.
    typealias Handle = @Sendable () async throws -> any LibraryProtocol

    public let isAvailable: Bool
    private let library: Handle

    /// The engine served from `library`'s own handle, offered where
    /// ``runsHere``.
    public init(library: GglibLibrary) {
        self.init { try await library.library() }
    }

    /// The engine over whatever `library` answers.
    ///
    /// - Parameter isAvailable: whether to offer the engine, which is
    ///   ``runsHere`` outside a test: a test on the Mac stands the engine in
    ///   for an iPhone's.
    init(isAvailable: Bool = GglibEngine.runsHere, library: @escaping Handle) {
        self.isAvailable = isAvailable
        self.library = library
    }

    /// Whether gglib's engine runs where this build runs: on an iPhone or
    /// an iPad, and not on its simulator, whose engine is unavailable so its
    /// walks use the mock, nor on the Mac, which this app runs no model on.
    public static var runsHere: Bool {
        #if os(iOS) && !targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }

    /// Serves the engine at `reading`, opening the library first if it is
    /// not open. Whatever fails is said as an `OnDeviceError`.
    public func serve(reading: GGChatCore.DeviceReading) async throws -> any EngineSession {
        let server: any ServerProtocol
        do {
            server = try await library().serve(reading: GGLib.DeviceReading(reading))
        } catch {
            throw OnDeviceError(thrown: error)
        }
        guard let baseURL = Self.loopback(server.baseUrl()) else {
            await server.shutdown()
            throw OnDeviceError.internal(message: "gglib's engine came up somewhere this app will not send a request.")
        }
        return GglibEngineSession(server: server, baseURL: baseURL)
    }

    /// `http://127.0.0.1:<port>/v1`, which is what the binding promises, or
    /// nil for anything else: the one hop with nothing encrypting it must
    /// not leave this device, as `ModelpipeSession` holds a pipe's to.
    static func loopback(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "http", url.port != nil, url.host() == "127.0.0.1"
        else { return nil }
        return url
    }
}
