import Foundation
import GGChatCore
import GGLib

/// A serve of gglib's engine: the server `serve(reading:)` answered, said as
/// an `EngineSession`.
final class GglibEngineSession: EngineSession {
    let baseURL: URL
    let apiKey: String
    private let server: any ServerProtocol

    init(server: any ServerProtocol, baseURL: URL) {
        self.server = server
        self.baseURL = baseURL
        apiKey = server.apiKey()
    }

    /// A watch of the engine of its own for each stream, pulled a step at a
    /// time: where the engine stands first, then each change, ending after
    /// `stopped`, once the watch has nothing more to say. A consumer that
    /// stops listening stops the pulling, though a step already asked for
    /// cannot be called off: the binding's calls cannot be cancelled, so
    /// that one ends at the engine's next change or at its shutdown.
    var status: AsyncStream<EngineStatus> {
        let watch = server.status()
        return AsyncStream { continuation in
            let pulling = Task {
                while !Task.isCancelled, let state = await watch.next() {
                    continuation.yield(EngineStatus(state))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in pulling.cancel() }
        }
    }

    /// Ends the reply in flight, frees the model, closes the proxy's port
    /// and the engine's behind it, and ends every watch; returns once all of
    /// that is done. The server's own shutdown is idempotent, so this is.
    func shutdown() async {
        await server.shutdown()
    }
}
