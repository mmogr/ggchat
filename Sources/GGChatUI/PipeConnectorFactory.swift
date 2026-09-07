import GGChatCore

/// The one place the app chooses its pipe implementation. When
/// modelpipe-ffi lands, `ModelpipeConnector` replaces both arms here and
/// nothing else changes.
public enum PipeConnectorFactory {
    /// The mock stands in only where a build is visibly a build. A shipped
    /// app that mocked the pipe would answer a real ticket with a canned
    /// reply, list a model that is not on any machine, and show a status
    /// pill reading "Direct", with nothing on screen saying otherwise.
    /// Refusing is the honest answer until there is something to dial with.
    ///
    /// The `#if` is not only a choice: `MockPipeConnector` is itself declared
    /// inside an `#if DEBUG`, so in a release build the first arm names a type
    /// that does not exist and there is nothing to return but the refusal.
    public static func make() -> any PipeConnector {
        #if DEBUG
            MockPipeConnector(sleeper: ContinuousClockSleeper(), stepDelay: .milliseconds(900))
        #else
            UnavailablePipeConnector()
        #endif
    }
}
