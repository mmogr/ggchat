/// The pipe in a build that has none. `MockPipeConnector` walks a canned
/// status to `direct` and answers from `MockProvider`, which is the right
/// thing in DEBUG and a lie anywhere else: a release user who pasted a real
/// ticket and a real token would get a status pill reading "Direct", a model
/// list that never came off their machine, and replies no server wrote.
///
/// So a release build got this instead, and refused every dial with a
/// sentence, until #53 gave it `ModelpipeConnector` to dial with. Nothing
/// in the app returns it now. It stays because
/// `scripts/check_no_mock_in_release.sh` looks for it, to prove it really
/// opened the release objects.
///
/// Leaving the mock unchosen was never the whole of it. `MockPipeConnector`
/// and `MockPipeSession` are declared inside an `#if DEBUG`, so a release
/// binary carries neither the types nor their symbols.
public struct UnavailablePipeConnector: PipeConnector {
    public init() {}

    /// Always throws `PipeConnectError.unavailable`. The ticket and the token
    /// are not examined: they are not what is wrong, and saying so about a
    /// perfectly good ticket would send the user off to fix it.
    public func connect(ticket: String, token: String) async throws -> any PipeSession {
        throw PipeConnectError.unavailable
    }
}
