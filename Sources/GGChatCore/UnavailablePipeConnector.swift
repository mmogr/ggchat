/// The pipe in a build that has none. `MockPipeConnector` walks a canned
/// status to `direct` and answers from `MockProvider`, which is the right
/// thing in DEBUG and a lie anywhere else: a release user who pasted a real
/// ticket and a real token would get a status pill reading "Direct", a model
/// list that never came off their machine, and replies no server wrote.
///
/// So the release build gets this instead. It refuses every dial with a
/// sentence, and `PipeConnectorFactory` is the one place that chooses
/// between the two.
///
/// The choice is not the whole of it: outside DEBUG there is nothing to
/// choose. `MockPipeConnector` and `MockPipeSession` are declared inside an
/// `#if DEBUG`, so a release binary carries neither the types nor their
/// symbols, and this is the only `PipeConnector` in it.
public struct UnavailablePipeConnector: PipeConnector {
    public init() {}

    /// Always throws `PipeConnectError.unavailable`. The ticket and the token
    /// are not examined: they are not what is wrong, and saying so about a
    /// perfectly good ticket would send the user off to fix it.
    public func connect(ticket: String, token: String) async throws -> any PipeSession {
        throw PipeConnectError.unavailable
    }
}
