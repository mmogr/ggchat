/// The gglib this app carries, as its framework reports itself: gglib-ffi's
/// `BuildInfo`, in this module's words, since the binding's types stop at
/// GGChatLocal as modelpipe's stop at GGChatPipe.
public struct GGLibBuild: Sendable, Equatable {
    /// gglib's version, `0.28.0-rc.2` say: the release the framework and
    /// the vendored binding were taken from.
    public var gglibVersion: String
    /// The uniffi release that generated the binding and built the
    /// framework's scaffolding.
    public var uniffiVersion: String
    /// The llama.cpp release gglib is pinned to, a `b<n>` tag, and so the
    /// llama.cpp framework the app embeds beside gglib's.
    public var llamaPin: String

    public init(gglibVersion: String, uniffiVersion: String, llamaPin: String) {
        self.gglibVersion = gglibVersion
        self.uniffiVersion = uniffiVersion
        self.llamaPin = llamaPin
    }
}
