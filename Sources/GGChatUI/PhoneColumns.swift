import SwiftUI

extension EnvironmentValues {
    /// Whether a chat's own controls are on a page beside it, so its top bar
    /// leaves them out: on an open Duo on its side. Never on a Mac.
    @Entry var chatControlsOnPage = false
}

#if os(iOS)
    /// How a phone lays out the list and the chat: as the system does, the
    /// list beside the chat on a tall open Duo, or a Duo on its side as a
    /// book, half open or flat.
    enum PhoneLayout {
        case system, listBeside, pages, flat

        /// Whether the chat's controls are in its panel; see `BookPages`.
        var isBook: Bool {
            self == .pages || self == .flat
        }
    }

    /// The leading page of a Duo on its side.
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
            // The list is put back on each unfolding, each turn upright and
            // each half opening on its side, and a hide holds until then.
            // Laid flat, the chat has the screen.
            .onChange(of: layout, initial: true) { _, layout in
                switch layout {
                case .listBeside, .pages: listShown = true
                case .flat: listShown = false
                case .system: break
                }
                if !layout.isBook { leadingPage = .list }
            }
        }

        /// The chat with its sidebar button, in its own navigation stack. On
        /// a Duo on its side its top bar is the list button, the title and
        /// the panel button, and the chat's own controls are in the panel.
        private var chatColumn: some View {
            NavigationStack {
                detail()
                    .environment(\.chatControlsOnPage, layout.isBook)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(listButtonLabel, systemImage: "sidebar.leading") {
                                withAnimation(reduceMotion ? nil : .snappy) { pressListButton() }
                            }
                            .accessibilityIdentifier("conversation-list")
                        }
                        if layout.isBook, model.selectedConversation != nil || model.openedHubChat != nil {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(
                                    showsPanel ? "Hide this chat's panel" : "Show this chat's panel",
                                    systemImage: showsPanel ? "info.circle.fill" : "info.circle"
                                ) {
                                    withAnimation(reduceMotion ? nil : .snappy) { pressPanelButton() }
                                }
                                .accessibilityIdentifier("this-chat")
                            }
                        }
                    }
            }
        }

        /// The list, or on a Duo on its side the chat's panel if asked for.
        /// A stack of its own for each, so what one pushed is not left on
        /// the other.
        private var leadingColumn: some View {
            NavigationStack {
                switch leadingPage {
                case .list: sidebar()
                case .thisChat: ThisChatPanel()
                }
            }
            .id(leadingPage)
        }

        /// The pages of a Duo on its side: either side of its fold while it
        /// is half open, and even while it is flat. None upright.
        private func bookPages(in size: CGSize) -> BookPages.Pages? {
            switch layout {
            case .pages: BookPages.pages(in: size, folds: folds) ?? BookPages.even(in: size)
            case .flat: BookPages.even(in: size)
            case .listBeside, .system: nil
            }
        }

        private var showsPanel: Bool {
            listShown && leadingPage == .thisChat
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
