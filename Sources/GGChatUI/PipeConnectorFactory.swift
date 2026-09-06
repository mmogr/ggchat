import GGChatCore

/// The one place the app chooses its pipe implementation. When
/// modelpipe-ffi lands, `ModelpipeConnector` replaces the mock here and
/// nothing else changes.
public enum PipeConnectorFactory {
    public static func make() -> any PipeConnector {
        MockPipeConnector(sleeper: ContinuousClockSleeper(), stepDelay: .milliseconds(900))
    }
}
