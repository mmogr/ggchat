import GGChatCore
import SwiftUI

/// Sidebar of conversations, chat on the right. Stock containers only: the
/// system draws the glass.
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    // Read only through their bindings (`$showingProviders` and the rest),
    // which the Swift 6.4 indexer records as no read of the property, so
    // periphery reports each as unused. Periphery's repository was archived
    // in August 2026 and will not learn otherwise; the indexer may.
    // periphery:ignore - read only through its binding, see above
    @State private var showingProviders = false
    // periphery:ignore - read only through its binding, see above
    @State private var showingSettings = false
    // periphery:ignore - read only through its binding, see above
    @State private var addingProvider = false
    /// What opening the store had to say.
    private let storeNotice: ShownStoreNotice

    public init(storeNotice: ShownStoreNotice = ShownStoreNotice(nil)) {
        self.storeNotice = storeNotice
    }

    public var body: some View {
        @Bindable var model = model
        // The notice is laid out below the split view, not in a bottom inset
        // over it: under such an inset the chat's composer stayed where it
        // was on an iPhone, and the notice was drawn over it.
        VStack(spacing: 0) {
            NavigationSplitView {
                ConversationSidebar(
                    showingProviders: $showingProviders, showingSettings: $showingSettings,
                    addingProvider: $addingProvider
                )
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
            } detail: {
                if let conversation = model.selectedConversation {
                    ChatView(conversation: conversation)
                } else if let chat = model.openedHubChat {
                    HubChatView(chat: chat)
                } else {
                    EmptyDetailView(addingProvider: $addingProvider)
                }
            }
            if !storeNotice.lines.isEmpty {
                StoreNoticeView(notice: storeNotice)
            }
        }
        .sheet(isPresented: $showingProviders) {
            ProvidersView()
        }
        .sheet(isPresented: $addingProvider) {
            AddProviderView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert(
            "Something did not work",
            isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })
        ) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .task { model.load() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.scene(.foreground)
            case .background: model.scene(.background)
            // `.inactive` is a transient — the notification shade, a call
            // banner, a window losing focus — and a pipe is worth holding
            // through one. Only `.background` means the process is about to
            // stop running.
            default: break
            }
        }
    }
}

struct ConversationSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var showingProviders: Bool
    @Binding var showingSettings: Bool
    @Binding var addingProvider: Bool

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
                    } else {
                        Button("New conversation") { model.newConversation() }
                    }
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
        .navigationTitle("ggchat")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New conversation", systemImage: "square.and.pencil") {
                    model.newConversation()
                }
                .disabled(model.providers.isEmpty)
            }
            ToolbarItem(placement: .automatic) {
                Button("Providers", systemImage: "server.rack") {
                    showingProviders = true
                }
            }
            #if os(iOS)
                ToolbarItem(placement: .automatic) {
                    Button("Settings", systemImage: "gearshape") {
                        showingSettings = true
                    }
                }
            #endif
        }
    }
}

/// What the app says when nothing is selected. On first run it is the way
/// in: a first-time user is one button from adding their server.
struct EmptyDetailView: View {
    @Environment(AppModel.self) private var model
    @Binding var addingProvider: Bool

    var body: some View {
        if model.providers.isEmpty {
            ContentUnavailableView {
                Label("No providers", systemImage: "server.rack")
            } description: {
                Text("Add the server that runs your models, or a modelpipe ticket from one.")
            } actions: {
                Button("Add a provider") { addingProvider = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("No conversation", systemImage: "bubble.left.and.text.bubble.right")
            } description: {
                Text("Start one, and it appears in the sidebar.")
            } actions: {
                Button("New conversation") { model.newConversation() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview)
}
