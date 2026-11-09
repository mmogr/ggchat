import SwiftUI

/// A page the list's foot opens: Providers or Settings. Where the list is
/// beside the chat on an open Duo, upright, as a book or flat, it is pushed
/// over the chat in the chat's own column, so the list stays where it is and
/// the chat, its draft and its place, is under it when Done or a chat in the
/// list takes it away. Folded, a phone pushes it on the list's own screen.
/// An iPad and a Mac keep a sheet.
enum RootPane: Hashable, Identifiable {
    case providers, settings

    var id: Self { self }

    /// How a pane is shown in a layout.
    enum Presentation: Equatable {
        /// Pushed over the chat, in the chat's column.
        case chatColumn
        /// Pushed on the list's own screen: a phone with the list a screen
        /// back.
        case listScreen
        /// A sheet over everything.
        case sheet
    }
}

/// The page itself, without a stack of its own: whoever pushes it owns one.
struct RootPanePage: View {
    let pane: RootPane

    var body: some View {
        switch pane {
        case .providers: ProvidersView(ownStack: false)
        case .settings: SettingsView(ownStack: false)
        }
    }
}

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
