import GGChatCore

// Only the release arm names anything from it, and `make analyze` compiles in
// Debug, where an unconditional import is an unused one.
#if !DEBUG
    import GGChatPipe
#endif

/// The one place the app chooses its pipe implementation.
public enum PipeConnectorFactory {
    /// A shipped build dials for real; a debug build mocks.
    ///
    /// The mock stays on the DEBUG side rather than being replaced, which is
    /// not what `docs/ffi-seam.md` originally said would happen. Three things
    /// argued it round. `MockPipeSession` is what the Settings screen's
    /// "Force closed" control downcasts to, and that button is the only way
    /// to exercise the reconnect UI by hand. Twenty-odd tests drive the app
    /// model through a mock that walks a status on a gate rather than a
    /// network. And a debug build that dialled for real would need a machine
    /// serving one before it could show a conversation at all.
    ///
    /// What a release build does is the thing that changed. It refused every
    /// ticket with a sentence about the build, because there was nothing
    /// behind the seam to dial with. There is now.
    ///
    /// `UnavailablePipeConnector` stays, and is not dead: it is the sentinel
    /// `scripts/check_no_mock_in_release.sh` looks for to prove it really
    /// opened the release objects, and periphery keeps it because the package
    /// retains public symbols.
    public static func make() -> any PipeConnector {
        #if DEBUG
            MockPipeConnector(sleeper: ContinuousClockSleeper(), stepDelay: .milliseconds(900))
        #else
            ModelpipeConnector()
        #endif
    }
}
