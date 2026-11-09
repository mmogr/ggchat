import SwiftUI

extension EnvironmentValues {
    /// Whether a chat's own controls are on a page beside it, so its top bar
    /// leaves them out: on an open Duo, upright or on its side. Never on a
    /// Mac.
    @Entry var chatControlsOnPage = false
}

#if os(iOS)
    /// How a phone lays out the list and the chat: as the system does, the
    /// list beside the chat on a tall open Duo, or a Duo on its side, as a
    /// book while half open or with the list beside the chat while flat.
    /// In each but the system's, the chat's controls are in its panel.
    enum PhoneLayout {
        case system, listBeside, pages, flat
    }

    /// The leading page of an open Duo.
    enum LeadingPage {
        case list, thisChat
    }

    /// The list, or a Duo's leading page, and the chat side by side, where a
    /// phone keeps them so: iOS lays a split view's list over the chat on a
    /// phone whatever it is asked. The chat is the row's last view whatever
    /// is beside it, so turning, half opening, laying flat and hiding the
    /// list never build it again, and its draft and keyboard stay.
    struct PhoneColumns<Sidebar: View, Detail: View>: View {
        @Environment(AppModel.self) private var model
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let layout: PhoneLayout
        /// The window's fold while the phone is half open; see `Fold`.
        let folds: [CGRect]
        /// Providers or Settings, pushed over the chat while open; see
        /// `RootPane`.
        @Binding var pane: RootPane?
        @ViewBuilder let sidebar: () -> Sidebar
        @ViewBuilder let detail: () -> Detail
        /// Whether the list is showing: on a Duo on its side, whether its
        /// leading page is.
        @State private var listShown = true
        @State private var leadingPage: LeadingPage = .list

        var body: some View {
            GeometryReader { proxy in
                let pages = bookPages(in: proxy.size)
                HStack(spacing: 0) {
                    if listShown {
                        leadingColumn
                            .frame(width: pages?.leading ?? SidebarPinning.listWidth(beside: proxy.size.width))
                            .transition(.move(edge: .leading))
                        if let pages, pages.gap > 0 {
                            // The fold itself, which nothing is drawn across.
                            Color.clear.frame(width: pages.gap)
                        } else {
                            Divider()
                        }
                    }
                    chatColumn
                }
            }
            // The leading page is put back on each unfolding, each turn and
            // each half opening or laying flat, and a hide holds until then.
            // Whichever page it was, list or panel, it stays.
            .onChange(of: layout, initial: true) { _, layout in
                switch layout {
                case .listBeside, .pages, .flat: listShown = true
                case .system: break
                }
            }
        }

        /// The chat with its sidebar button, in its own navigation stack. Its
        /// top bar is the list button, the title and the panel button, and
        /// the chat's own controls are in the panel, so a bar a third of an
        /// open Duo wide is not crowded into a More button and keeps the
        /// chat's title.
        ///
        /// Providers and Settings are pushed on this stack, over the chat,
        /// which stays its root: its draft and its place are under the page
        /// when Done, or a chat chosen in the list, takes it away.
        private var chatColumn: some View {
            NavigationStack {
                detail()
                    .navigationDestination(item: $pane) { pane in
                        RootPanePage(pane: pane)
                    }
                    .onChange(of: model.selection) { pane = nil }
                    .environment(\.chatControlsOnPage, true)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(listButtonLabel, systemImage: "sidebar.leading") {
                                withAnimation(reduceMotion ? nil : .snappy) { pressListButton() }
                            }
                            .accessibilityIdentifier("conversation-list")
                        }
                        if model.selectedConversation != nil || model.openedHubChat != nil {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(
                                    ToolsMenu.thisChatTitle(showsPanel: showsPanel, badged: toolsBadged),
                                    systemImage: showsPanel ? "info.circle.fill" : "info.circle"
                                ) {
                                    withAnimation(reduceMotion ? nil : .snappy) { pressPanelButton() }
                                }
                                .badge(toolsBadged && !showsPanel ? Text("!") : nil)
                                .accessibilityIdentifier("this-chat")
                            }
                        }
                    }
            }
        }

        /// The list, or the chat's panel if asked for.
        /// A stack of its own for each, so what one pushed is not left on
        /// the other.
        private var leadingColumn: some View {
            NavigationStack {
                switch leadingPage {
                // A sidebar's rows, as Claude's app has them, not the
                // inset cards a list in a stack is given.
                case .list: sidebar().listStyle(.sidebar)
                case .thisChat: ThisChatPanel()
                }
            }
            .id(leadingPage)
        }

        /// The pages of a Duo on its side while it is half open, either side
        /// of its fold. None flat or upright, where the list takes its
        /// share beside the chat; see `SidebarPinning.listWidth`.
        private func bookPages(in size: CGSize) -> BookPages.Pages? {
            layout == .pages ? BookPages.pages(in: size, folds: folds) : nil
        }

        private var showsPanel: Bool {
            listShown && leadingPage == .thisChat
        }

        /// Whether the chat open here, kept on this device, is badged for
        /// servers its Mac offers that it has never shown; the wrench is in
        /// the panel, so the panel's button carries the badge.
        private var toolsBadged: Bool {
            model.selectedConversation.map { model.toolsMenu(for: $0).badged } ?? false
        }

        private var listButtonLabel: String {
            listShown && leadingPage == .list ? "Hide the conversation list" : "Show the conversation list"
        }

        /// Hides the list, or shows it, in place of the panel if that is up.
        private func pressListButton() {
            if !showsPanel { listShown.toggle() }
            leadingPage = .list
        }

        /// Shows the panel on the leading page, or the list again.
        private func pressPanelButton() {
            if showsPanel {
                leadingPage = .list
            } else {
                leadingPage = .thisChat
                listShown = true
            }
        }
    }
#endif
