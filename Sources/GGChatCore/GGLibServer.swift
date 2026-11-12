/// What a gglib says of itself beside its model list, on `GET /v1/models`:
/// `"gglib": {"version": "0.35.0", "features": ["chats", "runs", "drawing",
/// "status"]}`. A server that is not gglib says nothing, and neither does a
/// gglib from before 0.35.0. A field or a feature word this build does not know
/// means nothing here.
public struct GGLibServer: Decodable, Sendable, Equatable {
    /// gglib's version, `0.35.0` say.
    public var version: String
    /// The features it serves, by their words: only what it serves is listed.
    public var features: Set<String>

    public init(version: String, features: Set<String>) {
        self.version = version
        self.features = features
    }

    /// Whether it serves `feature`.
    public func serves(_ feature: GGLibFeature) -> Bool {
        features.contains(feature.rawValue)
    }

    /// A gglib that serves every feature this build reads.
    public static func serving(_ version: String, _ features: [GGLibFeature] = GGLibFeature.allCases) -> GGLibServer {
        GGLibServer(version: version, features: Set(features.map(\.rawValue)))
    }
}

/// The features this build reads from a gglib's `features`, each a word there.
public enum GGLibFeature: String, Sendable, CaseIterable {
    /// The desk's chats, read and carried on from a paired device, with
    /// their images.
    case chats
    /// Replies written as runs, which go on while nobody reads them.
    case runs
    /// Pictures drawn with an image model.
    case drawing
    /// The status pane.
    case status
}

/// A server's model list, with what a gglib said of itself beside it.
public struct ModelList: Sendable, Equatable {
    public var models: [ModelInfo]
    /// Nil from a server that is not gglib, and from a gglib before 0.35.0.
    public var gglib: GGLibServer?

    public init(models: [ModelInfo], gglib: GGLibServer? = nil) {
        self.models = models
        self.gglib = gglib
    }
}
