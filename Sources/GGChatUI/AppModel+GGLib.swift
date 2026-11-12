import Foundation
import GGChatCore

/// What a provider's model list last said of its gglib: nothing, as a
/// server that is not gglib and a gglib from before 0.35.0 say, or its
/// version and the features it serves.
enum GGLibAnswer: Equatable {
    case silent
    case server(GGLibServer)
}

// What each server's gglib says of itself beside its model list
// (`GGLibServer`), kept from the last list in memory for as long as the app
// runs, and forgotten when its provider is moved or removed.
extension AppModel {
    /// What `providerID`'s gglib said of itself, or nil when its list said
    /// nothing or was never read.
    func gglib(of providerID: UUID) -> GGLibServer? {
        guard case .server(let server)? = gglibAnswers[providerID] else { return nil }
        return server
    }

    /// "home runs gglib 0.35.0", for each provider whose list said its
    /// gglib's version, in the providers' order.
    public var serverGGLibLines: [String] {
        providers.compactMap { config in gglib(of: config.id).map { "\(config.name) runs gglib \($0.version)" } }
    }
}
