import GGChatCore
// Unconditional now that the pairing reader is the real one in every build.
// It used to be under `#if !DEBUG`, because only the release arm of `make()`
// named anything from this module and `make analyze` compiles in Debug,
// where an unconditional import would have been an unused one.
import GGChatPipe

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

    /// Who reads a pairing string, in every build including DEBUG.
    ///
    /// No `#if` here, unlike ``make()``. The mock stands in for the far
    /// machine, which a debug build has no way to reach; it does not stand
    /// in for modelpipe's parser, which needs nothing but the string. A
    /// DEBUG reader of this app's own would be the second parse this change
    /// exists to delete, and the form and the scanner would then be walked
    /// against rules the shipped build does not follow.
    public static func makePairingReader() -> any PairingReader {
        ModelpipePairingReader()
    }
}
