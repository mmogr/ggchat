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
                return MockEngine(behaviour: behaviour, sleeper: ContinuousClockSleeper(), catalogue: mockCatalogue)
            }
        #endif
        return UnavailableEngine()
    }

    /// The library beside the engine. The mock one is given no directory,
    /// so it keeps nothing on disk, and a walk launched again starts from
    /// its behaviour and not from an earlier walk's downloads. Its downloads
    /// take a second a step, ten in all, so a walk reads a row while it is
    /// running.
    public static func makeLibrary() -> any ModelLibrary {
        #if DEBUG && os(iOS)
            if let behaviour = mockBehaviour {
                return MockLibrary(
                    behaviour: behaviour, sleeper: ContinuousClockSleeper(), stepDelay: .seconds(1),
                    catalogue: mockCatalogue)
            }
        #endif
        return UnavailableLibrary()
    }

    /// Where the models are kept, `ggchat-models` under Application
    /// Support, wherever this build runs a model, and nil everywhere else, so
    /// a release build and the Mac make no such directory.
    static func makeModelsDirectory() -> ModelsDirectory? {
        #if DEBUG && os(iOS)
            if mockBehaviour != nil { return ModelsDirectory.applicationSupport() }
        #endif
        return nil
    }

    #if DEBUG && os(iOS)
        /// The one catalogue the mock engine lists and the mock library
        /// installs into, so a model the mock downloads joins the engine's
        /// list.
        private static let mockCatalogue = MockLibrary.Catalogue(behaviour: mockBehaviour ?? .ready)
    #endif

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
