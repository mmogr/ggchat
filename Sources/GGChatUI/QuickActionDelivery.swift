#if os(iOS)
    import Observation
    import UIKit

    /// Where a quick action waits between the system handing it over and the
    /// window acting on it. The system speaks to a scene delegate, which
    /// cannot reach the app's model; the root view reads this instead.
    @Observable
    public final class QuickActionInbox {
        public static let shared = QuickActionInbox()
        var pending: QuickAction?

        func deliver(_ item: UIApplicationShortcutItem) {
            pending = QuickAction(rawValue: item.type)
        }

        /// The action waiting, once.
        func take() -> QuickAction? {
            defer { pending = nil }
            return pending
        }

        /// Sets what the icon offers. Kept by the system, so it is what a
        /// press shows while the app is not running.
        static func offer(_ actions: [QuickAction]) {
            UIApplication.shared.shortcutItems = actions.map { action in
                UIApplicationShortcutItem(
                    type: action.rawValue, localizedTitle: action.title, localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(systemImageName: action.symbol))
            }
        }
    }

    /// What each says on the icon's menu.
    extension QuickAction {
        var title: String {
            switch self {
            case .newChat: "New Chat"
            case .camera: "Take a Photo"
            case .draw: "Draw a Picture"
            }
        }

        var symbol: String {
            switch self {
            case .newChat: "square.and.pencil"
            case .camera: "camera"
            case .draw: "paintbrush.pointed"
            }
        }
    }

    /// The app delegate, there to name the scene delegate a quick action is
    /// handed to; SwiftUI still makes the window. In a DEBUG build it also
    /// turns UIKit's animations off when launched with `-ggchat-still YES`.
    public final class GGChatAppDelegate: NSObject, UIApplicationDelegate {
        /// The UI walks launch with `-ggchat-still YES`. On a loaded CI
        /// simulator a sheet still presenting, a form still scrolling a field
        /// clear of the keyboard, or a context menu still opening takes the
        /// tap or the keys meant for what will be there, and the walks failed
        /// a different way most runs. With animations off nothing on screen is
        /// in between. Never read in a release build.
        public func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            #if DEBUG
                if UserDefaults.standard.bool(forKey: "ggchat-still") { UIView.setAnimationsEnabled(false) }
            #endif
            return true
        }

        public func application(
            _ application: UIApplication, configurationForConnecting session: UISceneSession,
            options: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
            configuration.delegateClass = QuickActionSceneDelegate.self
            return configuration
        }
    }

    /// Takes a quick action both ways it arrives: with the launch it caused,
    /// and to an app already running.
    final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
        func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
            if let item = options.shortcutItem { QuickActionInbox.shared.deliver(item) }
        }

        func windowScene(
            _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
            completionHandler: @escaping (Bool) -> Void
        ) {
            QuickActionInbox.shared.deliver(shortcutItem)
            completionHandler(true)
        }
    }
#endif
