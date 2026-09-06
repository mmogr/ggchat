import GGChatCore
import SwiftUI

/// Sidebar of conversations, chat on the right. Stock containers only: the
/// system draws the glass.
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingProviders = false
    @State private var showingSettings = false
    @State private var addingProvider = false

    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            ConversationSidebar(
                showingProviders: $showingProviders, showingSettings: $showingSettings,
                addingProvider: $addingProvider
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
        } detail: {
            if let conversation = model.selectedConversation {
                ChatView(conversation: conversation)
            } else {
                EmptyDetailView(addingProvider: $addingProvider)
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
            if phase == .active { model.didBecomeActive() }
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
        List(selection: $model.selectedConversationID) {
            ForEach(model.conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
            }
            .onDelete { offsets in
                for index in offsets {
                    model.deleteConversation(model.conversations[index].id)
                }
            }
        }
        .overlay {
            if model.conversations.isEmpty {
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

struct ConversationRow: View {
    @Environment(AppModel.self) private var model
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if !conversation.title.isEmpty { return conversation.title }
        let derived = conversation.derivedTitle
        return derived.isEmpty ? "New conversation" : derived
    }

    private var subtitle: String {
        let provider = model.provider(for: conversation)?.name ?? "No provider"
        if let modelName = conversation.model { return "\(provider) · \(modelName)" }
        return provider
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview)
}
