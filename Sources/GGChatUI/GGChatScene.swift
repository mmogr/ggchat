import GGChatCore
import SwiftData
import SwiftUI

/// The whole app as one Scene, so the app target is a `@main` struct and
/// nothing else. Owns the SwiftData container and the app model, once
/// they are made.
///
/// Nothing is made before the window's first frame (#59). The window first
/// draws `LaunchView`, the system background and nothing a person has to
/// read, while the store is opened off the main actor; the model is then made
/// on it and the app swapped in. Opening the store, before this, ran in
/// `init` ahead of the first frame, and a Release build on an iPhone showed
/// a white window for as long as it took.
public struct GGChatScene: Scene {
    /// The store, the model and what opening the store had to say, once
    /// made.
    @State private var launched: Launched?

    public init() {}

    public var body: some Scene {
        WindowGroup {
            if let launched {
                RootView(storeNotice: launched.notice)
                    .environment(launched.model)
                    .modelContainer(launched.container)
            } else {
                LaunchView()
                    .task { launched = await Launched.make() }
            }
        }
        #if os(macOS)
            .defaultSize(width: 1100, height: 720)
            .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
            Settings {
                if let launched {
                    SettingsView()
                        .environment(launched.model)
                } else {
                    LaunchView()
                }
            }
        #endif
    }
}

/// What a launch makes before the app can draw: the container, the model on
/// it and what opening the store found to say.
struct Launched {
    let container: ModelContainer
    let model: AppModel
    let notice: ShownStoreNotice

    /// Opens the store off the main actor, then makes the model on it. Each
    /// is marked for Instruments (`LaunchSignposts`). `KeychainSecrets()`
    /// touches nothing until a credential is first read, so `Make the model`
    /// is the model's own defaults: the pipe connector and its identities,
    /// the engine and its library's folders, the diagnostics and the network
    /// watcher.
    static func make() async -> Launched {
        let opened = await Task.detached(priority: .userInitiated) {
            LaunchSignposts.interval("Open the store") { SwiftDataStore.open() }
        }.value
        let store = SwiftDataStore(container: opened.container)
        let model = LaunchSignposts.interval("Make the model") {
            AppModel(store: store, secrets: KeychainSecrets())
        }
        return Launched(container: store.container, model: model, notice: ShownStoreNotice(opened.notice))
    }
}

/// The window while the store opens: the system background, and after a
/// moment a spinner, so a quick launch shows nothing that flickers and a
/// slow one shows that something is happening.
struct LaunchView: View {
    @State private var waited = false

    var body: some View {
        ZStack {
            Color.clear
            if waited {
                ProgressView()
                    .accessibilityLabel("Opening your conversations")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            waited = true
        }
    }
}
