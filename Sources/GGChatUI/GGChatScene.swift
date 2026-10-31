import GGChatCore
import SwiftData
import SwiftUI

/// The whole app as one Scene, so the app target is a `@main` struct and
/// nothing else. Owns the SwiftData container and the app model.
public struct GGChatScene: Scene {
    @State private var model: AppModel
    private let container: ModelContainer
    /// What opening the store found to say, as the window shows it.
    @State private var storeNotice: ShownStoreNotice

    /// Runs before the window's first frame, so what it does is marked for
    /// Instruments (`LaunchSignposts`). `KeychainSecrets()` touches nothing
    /// until a credential is first read.
    public init() {
        let opened = LaunchSignposts.interval("Open the store") { SwiftDataStore.open() }
        let store = SwiftDataStore(container: opened.container)
        container = store.container
        _storeNotice = State(initialValue: ShownStoreNotice(opened.notice))
        let model = LaunchSignposts.interval("Make the model") {
            AppModel(store: store, secrets: KeychainSecrets())
        }
        _model = State(initialValue: model)
    }

    public var body: some Scene {
        WindowGroup {
            RootView(storeNotice: storeNotice)
                .environment(model)
        }
        .modelContainer(container)
        #if os(macOS)
            .defaultSize(width: 1100, height: 720)
            .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
            Settings {
                SettingsView()
                    .environment(model)
            }
        #endif
    }
}
