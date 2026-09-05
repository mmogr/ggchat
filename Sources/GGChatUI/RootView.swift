import GGChatCore
import SwiftUI

/// Sidebar of conversations, chat on the right. Stock containers only: the
/// system draws the glass.
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingProviders = false
    @State private var showingSettings = false

    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            ConversationSidebar(showingProviders: $showingProviders, showingSettings: $showingSettings)
        } detail: {
            if let conversation = model.selectedConversation {
                ChatView(conversation: conversation)
            } else {
                ContentUnavailableView(
                    "No conversation", systemImage: "bubble.left.and.text.bubble.right",
                    description: Text("Start one from the sidebar."))
            }
        }
        .sheet(isPresented: $showingProviders) {
            ProvidersView()
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
                ContentUnavailableView(
                    "No conversations", systemImage: "text.bubble",
                    description: Text(model.providers.isEmpty ? "Add a provider first." : "Start one."))
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
