import SwiftUI

/// A page the list's foot opens: Providers or Settings. Where the list is
/// beside the chat on an open Duo, upright, as a book or flat, it is pushed
/// over the chat in the chat's own column, so the list stays where it is and
/// the chat, its draft and its place, is under it when Done or a chat in the
/// list takes it away. Everywhere else, a folded phone, an iPad and a Mac,
/// it is a sheet: pushed on a folded phone's list, Save in a provider's
/// editor took Providers with it, and the list was what was left.
enum RootPane: Hashable, Identifiable {
    case providers, settings

    var id: Self { self }

    /// How a pane is shown in a layout.
    enum Presentation: Equatable {
        #if os(iOS)
            /// Pushed over the chat, in the chat's column.
            case chatColumn
        #endif
        /// A sheet over everything.
        case sheet
    }
}

#if os(iOS)
    /// The page itself, without a stack of its own: whoever pushes it owns
    /// one. Only a phone's columns push it.
    struct RootPanePage: View {
        let pane: RootPane

        var body: some View {
            switch pane {
            case .providers: ProvidersView(ownStack: false)
            case .settings: SettingsView(ownStack: false)
            }
        }
    }
#endif

/// The page as a sheet, with a stack of its own.
struct RootPaneSheet: View {
    let pane: RootPane

    var body: some View {
        switch pane {
        case .providers: ProvidersView()
        case .settings: SettingsView()
        }
    }
}
