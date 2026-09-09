/// What a live pipe can be asked about itself: the port it bound, and what
/// its endpoint has spent on relays.
///
/// A value read on demand rather than a stream to subscribe to. These numbers
/// change interestingly only when the path does, and `PipeSession.status`
/// already says when that happens — so a screen that shows them alongside the
/// path is refreshed by the thing it is already watching, and needs no clock
/// of its own.
///
/// Named in this module's words rather than the binding's, for the reason
/// ``PipeCloseReason`` is: the binding's types stop at the seam.
public struct PipeReadings: Sendable, Equatable {
    /// The loopback port this pipe bound.
    ///
    /// `baseURL` carries it too. Reading a port out of a URL is the work this
    /// saves a person who wants the number on its own.
    public var port: UInt16

    /// Relay connections this endpoint has opened, whether or not the pipe
    /// ended up direct.
    ///
    /// A pipe reading `direct` with a non-zero count here hole-punched after
    /// starting through a relay, which is the ordinary way a connection
    /// forms — not a sign that anything went wrong.
    public var relayConnections: UInt64

    /// Relay connections that failed to open.
    public var relayConnectionsFailed: UInt64

    /// Relay connections a relay refused for rate.
    ///
    /// Worth its own number rather than being folded into the failures: the
    /// binding's own documentation calls a non-zero here the difference
    /// between "the network is broken" and "this endpoint is being throttled",
    /// and those two send a person to different places.
    public var relayConnectionsRatelimited: UInt64

    public init(
        port: UInt16,
        relayConnections: UInt64 = 0,
        relayConnectionsFailed: UInt64 = 0,
        relayConnectionsRatelimited: UInt64 = 0
    ) {
        self.port = port
        self.relayConnections = relayConnections
        self.relayConnectionsFailed = relayConnectionsFailed
        self.relayConnectionsRatelimited = relayConnectionsRatelimited
    }
}
