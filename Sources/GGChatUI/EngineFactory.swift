import Foundation
import GGChatCore

#if os(iOS)
    import GGChatLocal
#endif

/// The one place the app chooses the engine on this device and its model
/// library.
///
/// gglib's own engine runs on an iPhone or an iPad, in a release build and
/// in a DEBUG one, and nowhere else: the simulator and the Mac have
/// `UnavailableEngine`, so they offer nothing on-device. The one exception
/// is a DEBUG build on iOS launched with `-ggchat-mock-engine
/// <ready|slow|fails|too-big|no-models>`, which gets `MockEngine` and
/// `MockLibrary` behaving so, as `-ggchat-mock-mcp-servers` shapes the mock
/// pipe; the walks run on that, with This iPhone added at launch unless
/// `-ggchat-mock-engine-unadded YES` says otherwise.
///
/// The library on iOS is gglib's own (`GglibLibrary`), but for that case:
/// the database in `ggchat-gglib` and the models in `ggchat-models`, both
/// under Application Support. It is opened at the first question or serve,
/// and every way to ask it is behind the engine: where the engine is
/// unavailable nothing is browsed, downloaded or listed, so it is never
/// opened and makes no folder. The Mac has no library.
///
/// gglib's engine is served from that same library, so the process holds
/// one gglib library over one `gglib.db`: serving again stops the engine
/// served before only within one library.
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
        #if os(iOS)
            if GglibEngine.runsHere, let library = gglibLibrary {
                return GglibEngine(library: library)
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
        #if os(iOS)
            if let gglibLibrary { return gglibLibrary }
        #endif
        return UnavailableLibrary()
    }

    #if os(iOS)
        /// gglib's library, the one the browser asks and the engine is
        /// served from. Handed the very folder `makeModelsDirectory()` names,
        /// so the room checked before a download and the folder gglib writes
        /// it to are one. Nil where Application Support cannot be named.
        private static let gglibLibrary: GglibLibrary? = makeModelsDirectory()
            .flatMap { LibraryFolders.applicationSupport(models: $0.directory) }
            .map { GglibLibrary(folders: $0) }
    #endif

    /// Where the models are kept, `ggchat-models` under Application
    /// Support, on iOS, and nil on the Mac. Naming it makes nothing: the app
    /// makes and marks it only where the engine is available.
    static func makeModelsDirectory() -> ModelsDirectory? {
        #if os(iOS)
            return ModelsDirectory.applicationSupport()
        #else
            return nil
        #endif
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

        /// The model a walk on a device names with `-ggchat-live-engine-model
        /// <id>`, as gglib's proxy lists it: This iPhone is added at launch
        /// with it chosen, over gglib's own engine. Nil when unset or empty.
        static var liveEngineModel: String? {
            UserDefaults.standard.string(forKey: "ggchat-live-engine-model").flatMap { $0.isEmpty ? nil : $0 }
        }

        /// Whether a walk launched with `-ggchat-mock-engine-unadded YES`
        /// asks for the mock without This iPhone added at launch: a first run
        /// on a phone where no model was chosen yet, whose way in is Add
        /// provider.
        static var leavesThisIPhoneOut: Bool {
            UserDefaults.standard.bool(forKey: "ggchat-mock-engine-unadded")
        }

        /// What `-ggchat-mock-engine` asks of the mock; nil when it is unset
        /// or names no behaviour. Read on every platform, and acted on only
        /// on iOS: elsewhere the factories above return no mock, so the
        /// engine is unavailable and nothing is added for it.
        static var mockBehaviour: MockEngine.Behaviour? {
            UserDefaults.standard.string(forKey: mockEngineKey).flatMap(MockEngine.Behaviour.init(rawValue:))
        }
    #endif
}
