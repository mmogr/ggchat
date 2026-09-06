import GGChatCore
import SwiftData
import SwiftUI

/// The whole app as one Scene, so the app target is a `@main` struct and
/// nothing else. Owns the SwiftData container and the app model.
public struct GGChatScene: Scene {
    @State private var model: AppModel
    private let container: ModelContainer

    public init() {
        let store = SwiftDataStore(container: SwiftDataStore.makeContainer())
        container = store.container
        _model = State(initialValue: AppModel(store: store, secrets: KeychainSecrets()))
    }

    public var body: some Scene {
        WindowGroup {
            RootView()
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
