import Foundation
import GGChatCore

/// The one place the app chooses the engine on this device and its model
/// library.
///
/// No build has gglib's engine yet, so outside one case both are
/// unavailable: a release build, the Mac, and a DEBUG build launched without
/// `-ggchat-mock-engine`, so the walks that never ask for it see nothing
/// on-device. The case is a DEBUG build on iOS launched with
/// `-ggchat-mock-engine <ready|slow|fails|too-big|no-models>`, which gets
/// `MockEngine` and `MockLibrary` behaving so, as `-ggchat-mock-mcp-servers`
/// shapes the mock pipe.
///
/// `UnavailableEngine` is also the sentinel
/// `scripts/check_no_mock_in_release.sh` looks for.
public enum EngineFactory {
    public static func makeEngine() -> any LocalEngine {
        #if DEBUG && os(iOS)
            if let behaviour = mockBehaviour {
                return MockEngine(behaviour: behaviour, sleeper: ContinuousClockSleeper())
            }
        #endif
        return UnavailableEngine()
    }

    public static func makeLibrary() -> any ModelLibrary {
        #if DEBUG && os(iOS)
            if let behaviour = mockBehaviour {
                return MockLibrary(behaviour: behaviour, sleeper: ContinuousClockSleeper())
            }
        #endif
        return UnavailableLibrary()
    }

    #if DEBUG
        /// The default a UI walk sets, `-ggchat-mock-engine ready`, to run a
        /// model on this iPhone with the mock.
        static let mockEngineKey = "ggchat-mock-engine"

        /// What `-ggchat-mock-engine` asks of the mock; nil when it is unset
        /// or names no behaviour. Read on every platform, and acted on only
        /// on iOS: elsewhere the factories above return no mock, so the
        /// engine is unavailable and nothing is added for it.
        static var mockBehaviour: MockEngine.Behaviour? {
            UserDefaults.standard.string(forKey: mockEngineKey).flatMap(MockEngine.Behaviour.init(rawValue:))
        }
    #endif
}
