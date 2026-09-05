import GGChatCore
import SwiftUI

/// The transcript: flat text on the scrolling background, pinned to the
/// bottom while a reply streams, with the composer floating over it.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @State private var showingStatus = false
    let conversation: Conversation

    private var provider: ProviderConfig? {
        model.provider(for: conversation)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(conversation.messages) { message in
                    MessageRow(
                        message: message,
                        isLast: message.id == conversation.messages.last?.id,
                        error: message.id == conversation.messages.last?.id
                            ? model.streamError(for: conversation.id) : nil
                    )
                }
                if let live = model.liveReply, live.conversationID == conversation.id {
                    LiveReplyRow(live: live)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .overlay {
            if conversation.messages.isEmpty, !model.isStreaming(conversation.id) {
                ContentUnavailableView("Say something", systemImage: "text.bubble")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Composer(conversation: conversation)
        }
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let provider, model.proxyStatusAvailable(for: provider.id) {
                ToolbarItem(placement: .automatic) {
                    Button("Server status", systemImage: "gauge.with.dots.needle.33percent") {
                        showingStatus = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingStatus) {
            if let provider {
                ProxyStatusView(provider: provider)
            }
        }
        .task(id: provider?.id) {
            if let provider {
                await model.probeProxyStatus(for: provider)
            }
        }
    }

    private var title: String {
        if !conversation.title.isEmpty { return conversation.title }
        let derived = conversation.derivedTitle
        return derived.isEmpty ? "New conversation" : derived
    }
}

/// Observes only the live reply, so each token redraws this row alone.
struct LiveReplyRow: View {
    let live: LiveReply

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoleLabel(role: .assistant)
            if !live.reasoning.isEmpty {
                ReasoningRow(text: live.reasoning, isThinking: live.content.isEmpty)
            }
            if live.content.isEmpty, live.reasoning.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Waiting for the first token")
            } else {
                MarkdownBlocksView(blocks: MarkdownBlocks.parse(live.content))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.12), value: live.content.count)
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: AppModel.preview.conversations[0])
    }
    .environment(AppModel.preview)
}
