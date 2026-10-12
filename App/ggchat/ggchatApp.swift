import GGChatUI
import SwiftUI

@main
struct GGChatApp: App {
    #if os(iOS)
        // A quick action from the app's icon is handed to a delegate, and
        // only an `App` may name one. The delegate itself is the package's.
        @UIApplicationDelegateAdaptor(GGChatAppDelegate.self) private var delegate
    #endif

    var body: some Scene {
        GGChatScene()
    }
}
