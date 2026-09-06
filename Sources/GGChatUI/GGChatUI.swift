#if canImport(SwiftUI)
    import SwiftUI
#endif

// The SwiftUI module. Views arrive in the app-shell PR; this file exists so
// the package's UI product has a target to build.

/// Bumped when the UI module gains its first view.
public enum GGChatUI {
    public static let moduleName = "GGChatUI"
}
