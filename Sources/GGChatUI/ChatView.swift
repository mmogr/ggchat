import GGChatCore
import SwiftUI

/// The transcript: flat text on the scrolling background, pinned to the
/// bottom while a reply streams, with the composer floating over it.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.chatControlsOnPage) private var controlsOnPage
    @State private var showingStatus = false
    @State private var editingPrompt = false
    @State private var editing: Message?
    let conversation: Conversation

    private var provider: ProviderConfig? {
        model.provider(for: conversation)
    }

    var body: some View {
        let points = model.branchPoints(of: conversation)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(conversation.messages) { message in
                    MessageRow(
                        message: message,
                        showsEnding: message.id == conversation.messages.last?.id
                            && !model.isStreaming(conversation.id),
                        advice: message.failure.flatMap { model.advice(for: $0, in: conversation) },
                        writingLine: model.writingLine(for: message, in: conversation),
                        branch: points.first { $0.messageID == message.id }.map {
                            BranchChoice($0) { model.openBranch($0) }
                        },
                        changes: model.messageChanges(in: conversation.id) { editing = $0 }
                    )
                }
                if let live = model.liveReplies[conversation.id] {
                    LiveReplyRow(live: live)
                } else if let end = points.first(where: { $0.messageID == nil }) {
                    BranchEndRow(choice: BranchChoice(end) { model.openBranch($0) })
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)
            .footOfTheLatest()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .jumpsToLatest(replying: model.isStreaming(conversation.id), in: conversation.id)
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
            // On an open Duo on its side these are in the chat's panel.
            if !controlsOnPage {
                // Always there, so a prompt can be set before the first
                // message. Whether one is set is in the label, not an
                // accessibility value: the vertical bar an iPhone Duo lays
                // toolbar items in keeps a button's label and identifier and
                // drops its value.
                ToolbarItem(placement: .automatic) {
                    Button {
                        editingPrompt = true
                    } label: {
                        Label(
                            conversation.hasSystemPrompt ? "System prompt, set" : "System prompt",
                            systemImage: promptSymbol
                        )
                    }
                    .accessibilityIdentifier("system-prompt")
                }
                // Only for a model gglib lists as one that thinks.
                if model.offersThinking(for: conversation) {
                    ToolbarItem(placement: .automatic) {
                        ThinkingToggle(isOn: model.thinkingOn(for: conversation)) { on in
                            model.setThinking(on: on, for: conversation.id)
                        }
                    }
                }
                // Only for a paired Mac that offers its MCP servers' tools.
                let tools = model.toolsMenu(for: conversation)
                if !tools.isHidden {
                    ToolbarItem(placement: .automatic) {
                        ToolsMenuButton(menu: tools) { on in
                            model.setTools(on: on, for: conversation.id)
                        } pick: { server, picked in
                            model.setServer(server, picked: picked, for: conversation.id)
                        }
                    }
                }
                if let provider, model.proxyStatusAvailable(for: provider.id) {
                    ToolbarItem(placement: .automatic) {
                        Button("Server status", systemImage: "gauge.with.dots.needle.33percent") {
                            showingStatus = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingStatus) {
            if let provider {
                ProxyStatusView(provider: provider)
            }
        }
        .sheet(isPresented: $editingPrompt) {
            SystemPromptView(conversation: conversation)
        }
        .sheet(item: $editing) { message in
            MessageEditor(message: message) { model.edit(message.id, in: conversation.id, to: $0) }
        }
        // What clears the list's unread mark. Appear, not a `.task`, and no
        // disappear, which iOS 27 sends at once while the chat stays; see
        // `AppModel+ListMarks`. The view is kept when the selection moves, so
        // a move is told as the other chat arriving.
        .onAppear { model.chatAppeared(conversation.id) }
        .onChange(of: conversation.id) { _, shown in model.chatAppeared(shown) }
    }

    /// Filled while a prompt is set, since the transcript never shows it.
    private var promptSymbol: String {
        conversation.hasSystemPrompt ? "person.text.rectangle.fill" : "person.text.rectangle"
    }

    private var title: String {
        if !conversation.title.isEmpty { return conversation.title }
        let derived = conversation.derivedTitle
        return derived.isEmpty ? "New conversation" : derived
    }
}

/// Observes only the live reply, so each token redraws this row alone. The
/// model is read only while the reply waits for its pipe or the engine, for
/// the line that names the provider.
struct LiveReplyRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    let live: LiveReply

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoleLabel(role: .assistant)
            if !live.reasoning.isEmpty {
                ReasoningRow(text: live.reasoning, isThinking: live.content.isEmpty)
            }
            ForEach(Array(live.tools.enumerated()), id: \.offset) { _, line in
                ToolLine(line: line)
            }
            if let waiting = model.waitingLine(for: live, locale: locale, calendar: calendar) {
                // Plain text, which VoiceOver reads as it is shown. Stop is the
                // composer's button, as for any reply in flight.
                Text(waiting)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let reading = live.readingLine(in: locale) {
                // Plain text, which VoiceOver reads as it is shown.
                Text(reading)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if live.awaitsFirstToken {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Waiting for the first token")
            } else {
                MarkdownBlocksView(blocks: live.blocks)
            }
            LiveReplyWork(live: live)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: live.content.count)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Default") {
    NavigationStack {
        ChatView(conversation: AppModel.preview.conversations[0])
    }
    .environment(AppModel.preview)
}

#Preview("Accessibility 5") {
    NavigationStack {
        ChatView(conversation: AppModel.preview.conversations[0])
    }
    .environment(AppModel.preview)
    .dynamicTypeSize(.accessibility5)
}
