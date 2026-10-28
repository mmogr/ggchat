import GGChatCore
import SwiftUI

/// Whether the conversation list is kept beside the chat: on a regular-width
/// window taller than it is wide, as an open iPhone Duo and an iPad held
/// upright are, and wide enough for the list and a chat no narrower than the
/// narrowest the fold allows. iOS would put the list behind a button there. A
/// folded Duo is a phone, its list a screen back, and a window wider than it
/// is tall, a folded Duo or a large iPhone turned on its side among them, has
/// the list shown or hidden as the system does.
enum SidebarPinning {
    /// The list's ideal width and the narrowest chat beside it.
    nonisolated static let narrowest: CGFloat = 280 + Fold.narrowest

    nonisolated static func fits(_ size: CGSize) -> Bool {
        size.height > size.width && size.width >= narrowest
    }

    nonisolated static func pins(regularWidth: Bool, size: CGSize) -> Bool {
        regularWidth && fits(size)
    }

    /// The list's share of the width where a phone lays it beside the chat,
    /// three eighths as Claude's own app keeps it.
    nonisolated static let listShare: CGFloat = 3 / 8
    /// The narrowest the list is laid beside the chat.
    nonisolated static let narrowestList: CGFloat = 240

    /// The list's width beside a chat in a window `width` wide.
    nonisolated static func listWidth(beside width: CGFloat) -> CGFloat {
        max(narrowestList, (width * listShare).rounded())
    }

    /// The window's size as the rule reads it: the tallest height seen at its
    /// width. The keyboard only ever takes height away, and coming up it made
    /// a tall window read as wide and the layout change under the field being
    /// typed in; folding, unfolding and turning all change the width.
    nonisolated static func measured(_ size: CGSize, after last: CGSize) -> CGSize {
        guard size.width == last.width else { return size }
        return CGSize(width: size.width, height: max(size.height, last.height))
    }
}

/// Where an open iPhone Duo held on its side is laid out as a book: the chat
/// on the trailing page, as on the outside screen, which each page is about
/// the size of, and the list or the chat's own panel on the leading page.
/// Only while the phone is half open, which is when the fold is reported;
/// laid flat, the chat has the whole screen and the list is a tap away.
enum BookPages {
    /// The shortest window read as an open Duo on its side. A folded Duo on
    /// its side is 466 points high and a Pro Max turned 440; open, the Duo
    /// is 669.
    nonisolated static let shortest: CGFloat = 600

    /// Whether `size`, read as `SidebarPinning.measured` reads it, is an
    /// open Duo on its side: wider than tall, tall enough, and room for two
    /// pages. `anyHeight` waives the height, for the walk on an iPhone.
    nonisolated static func opensSideways(_ size: CGSize, anyHeight: Bool = false) -> Bool {
        size.width > size.height && (anyHeight || size.height >= shortest)
            && size.width >= 2 * Fold.narrowest
    }

    /// The two pages across a window, in its leading-edge space.
    nonisolated struct Pages: Equatable {
        /// The leading page's width.
        var leading: CGFloat
        /// The width between the pages: the fold's, or none.
        var gap: CGFloat
    }

    /// The pages either side of a vertical fold in `folds`, or nil when
    /// there is none, as when the phone is flat or upright, or when a page
    /// beyond it would be narrower than `Fold.narrowest`.
    nonisolated static func pages(in size: CGSize, folds: [CGRect]) -> Pages? {
        guard let fold = folds.first(where: { $0.height > $0.width }) else { return nil }
        guard fold.minX >= Fold.narrowest, size.width - fold.maxX >= Fold.narrowest else { return nil }
        return Pages(leading: fold.minX, gap: fold.width)
    }

    /// Two even pages, for a list shown by hand while the phone is flat.
    nonisolated static func even(in size: CGSize) -> Pages {
        Pages(leading: (size.width / 2).rounded(), gap: 0)
    }
}

struct ConversationSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var showingProviders: Bool
    @Binding var showingSettings: Bool
    @Binding var addingProvider: Bool
    /// Whether the list is a column beside the chat, where its header has
    /// room for its title and one button: Providers and Settings go to a bar
    /// at its foot. A phone's list, a screen of its own, keeps all three up top.
    var beside = false

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                ForEach(model.conversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .tag(SidebarSelection.local(conversation.id))
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.deleteConversation(model.conversations[index].id)
                    }
                }
                if model.conversations.isEmpty, !model.hubProviders.isEmpty {
                    Text("No conversations on this phone yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                // Named only when a paired Mac's section follows it.
                if !model.hubProviders.isEmpty { Text("On this phone") }
            } footer: {
                if !model.hubProviders.isEmpty {
                    Text("These chats are kept only on this phone. The Mac does not keep them.")
                }
            }
            ForEach(model.hubProviders) { config in
                HubChatsSection(config: config)
            }
        }
        .refreshable { await model.refreshHubChats() }
        .overlay {
            if model.conversations.isEmpty, model.hubProviders.isEmpty {
                // The way in on a phone, where the detail pane and its call
                // to action are a screen away.
                VStack(spacing: 12) {
                    Text(model.providers.isEmpty ? "No providers yet" : "No conversations yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if model.providers.isEmpty {
                        Button("Add a provider") { addingProvider = true }
                        if model.runsModelsHere {
                            Button("Run a model on this iPhone") { model.openModelBrowser() }
                        }
                    } else {
                        Button("New conversation") { model.newConversation() }
                    }
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
        .navigationTitle("ggchat")
        #if os(iOS)
            // In the header's own row, as Claude's app keeps its name, not a
            // large title under it.
            .toolbarTitleDisplayMode(beside ? .inlineLarge : .automatic)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New conversation", systemImage: "square.and.pencil") {
                    model.newConversation()
                }
                .disabled(model.providers.isEmpty)
            }
            #if os(iOS)
                if beside {
                    ToolbarItemGroup(placement: .bottomBar) {
                        providersButton
                        Spacer()
                        settingsButton
                    }
                } else {
                    ToolbarItem(placement: .automatic) { providersButton }
                    ToolbarItem(placement: .automatic) { settingsButton }
                }
            #else
                ToolbarItem(placement: .automatic) { providersButton }
            #endif
        }
    }

    private var providersButton: some View {
        Button("Providers", systemImage: "server.rack") {
            showingProviders = true
        }
    }

    #if os(iOS)
        private var settingsButton: some View {
            Button("Settings", systemImage: "gearshape") {
                showingSettings = true
            }
        }
    #endif
}
