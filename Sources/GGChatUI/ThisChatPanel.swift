import SwiftUI

/// A part of the panel beside a chat on an open iPhone Duo on its side,
/// shown or left out by `parts`.
nonisolated enum ThisChatPart: Equatable {
    case model, thinking, tools, systemPrompt, context, server

    /// The parts a chat's panel shows, in order. A Mac's chat keeps its
    /// tools and its prompt on the Mac, so has neither here.
    static func parts(
        isMacsChat: Bool, thinks: Bool, offersTools: Bool, hasContext: Bool, reportsStatus: Bool
    ) -> [ThisChatPart] {
        var parts: [ThisChatPart] = [.model]
        if thinks { parts.append(.thinking) }
        if offersTools, !isMacsChat { parts.append(.tools) }
        if !isMacsChat { parts.append(.systemPrompt) }
        if hasContext { parts.append(.context) }
        if reportsStatus { parts.append(.server) }
        return parts
    }
}

#if os(iOS)
    import GGChatCore

    /// "This chat": the open chat's own controls, on the leading page of an
    /// open iPhone Duo on its side, beside the chat on the trailing page. Its
    /// model, Thinking, Tools, system prompt, context and server, which
    /// elsewhere are in the chat's top bar, its sheets and its composer. The
    /// composer keeps its model pill and context ring here too, so the chat's
    /// page is the outside screen's.
    struct ThisChatPanel: View {
        @Environment(AppModel.self) private var model
        @State private var status: ProxyStatus?
        @State private var failure: String?

        var body: some View {
            List {
                if let conversation = model.selectedConversation {
                    local(conversation)
                } else if let chat = model.openedHubChat {
                    macs(chat)
                }
            }
            .overlay {
                if model.selectedConversation == nil, model.openedHubChat == nil {
                    ContentUnavailableView("No chat open", systemImage: "info.circle")
                }
            }
            .navigationTitle("This chat")
            .toolbarTitleDisplayMode(.inlineLarge)
            .followsProxyStatus(of: statusProvider, status: $status, failure: $failure)
        }

        // MARK: - A chat kept here

        @ViewBuilder
        private func local(_ conversation: Conversation) -> some View {
            let provider = model.provider(for: conversation)
            let reading = model.contextReading(for: conversation)
            let parts = ThisChatPart.parts(
                isMacsChat: false, thinks: model.offersThinking(for: conversation),
                offersTools: model.offersTools(for: conversation), hasContext: reading != nil,
                reportsStatus: provider.map { model.proxyStatusAvailable(for: $0.id) } ?? false
            )
            Section("Model") {
                NavigationLink {
                    ModelChoice(conversationID: conversation.id)
                } label: {
                    LabeledContent("Model", value: conversation.model ?? provider?.defaultModel ?? "Choose a model")
                }
                if let provider {
                    LabeledContent("Provider", value: provider.name)
                }
            }
            if parts.contains(.thinking) {
                Section {
                    let on = model.thinkingOn(for: conversation)
                    PanelSwitchRow(
                        label: ThinkingToggle.label(isOn: on), symbol: ThinkingToggle.symbol(isOn: on), isOn: on,
                        id: "thinking"
                    ) { model.setThinking(on: $0, for: conversation.id) }
                }
            }
            if parts.contains(.tools) {
                ToolsPanelRows(
                    conversationID: conversation.id, menu: model.toolsMenu(for: conversation),
                    setOn: { model.setTools(on: $0, for: conversation.id) },
                    pick: { model.setServer($0, picked: $1, for: conversation.id) },
                    seen: { model.markToolsSeen(for: conversation.id) })
            }
            if parts.contains(.systemPrompt) {
                Section {
                    NavigationLink {
                        SystemPromptForm(conversation: conversation)
                    } label: {
                        LabeledContent("System prompt", value: conversation.hasSystemPrompt ? "Set" : "None")
                    }
                }
            }
            if parts.contains(.context), let reading {
                Section("Context") { ContextLines(reading: reading) }
            }
            if parts.contains(.server), let provider {
                ProxyStatusSections(
                    provider: provider, status: status, failure: failure, listsTools: !parts.contains(.tools))
            }
        }

        // MARK: - A Mac's chat

        @ViewBuilder
        private func macs(_ chat: OpenHubChat) -> some View {
            let mac = model.providers.first { $0.id == chat.providerID }
            let reading = model.hubContextReading
            let parts = ThisChatPart.parts(
                isMacsChat: true, thinks: model.hubChatOffersThinking, offersTools: false,
                hasContext: reading != nil, reportsStatus: model.proxyStatusAvailable(for: chat.providerID)
            )
            Section("Model") {
                LabeledContent(
                    "Model", value: model.hubChatModel(chat)?.id ?? chat.thinking.modelName ?? "Not named"
                )
                if let mac {
                    LabeledContent("Mac", value: mac.name)
                }
            }
            if parts.contains(.thinking) {
                Section {
                    let on = model.hubThinkingOn
                    PanelSwitchRow(
                        label: ThinkingToggle.label(isOn: on), symbol: ThinkingToggle.symbol(isOn: on), isOn: on,
                        id: "thinking"
                    ) { model.setHubThinking(on: $0) }
                }
            }
            if parts.contains(.context), let reading {
                Section("Context") { ContextLines(reading: reading) }
            }
            if parts.contains(.server), let mac {
                ProxyStatusSections(provider: mac, status: status, failure: failure)
            }
        }

        // MARK: - Pieces

        /// The provider whose status the panel follows: the open chat's,
        /// when it answers gglib's status endpoint.
        private var statusProvider: ProviderConfig? {
            let id =
                model.selectedConversation.flatMap { model.provider(for: $0)?.id } ?? model.openedHubChat?.providerID
            guard let id, model.proxyStatusAvailable(for: id) else { return nil }
            return model.providers.first { $0.id == id }
        }
    }

    /// The models a chat kept here can run on, and the providers it can
    /// move to, as the composer's model pill lists them, pushed on the panel.
    private struct ModelChoice: View {
        @Environment(AppModel.self) private var model
        @Environment(\.dismiss) private var dismiss
        let conversationID: UUID

        /// The conversation as it is now, not as it was when pushed.
        private var conversation: Conversation? {
            model.conversations.first { $0.id == conversationID }
        }

        var body: some View {
            List {
                if let conversation {
                    let provider = model.provider(for: conversation)
                    let current = conversation.model ?? provider?.defaultModel
                    Section("Model") {
                        if let provider {
                            let models = model.chatModels(for: provider.id)
                            if models.isEmpty {
                                Text("No models listed yet.").foregroundStyle(.secondary)
                                // As the composer's list offers it.
                                if provider.kind == .onDevice, model.runsModelsHere {
                                    Button("Find a model…") { model.openModelBrowser() }
                                }
                            }
                            ForEach(models) { info in
                                Button {
                                    model.select(model: info.id, for: conversationID)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(info.id)
                                            if let detail = info.description {
                                                Text(detail).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if info.id == current {
                                            Image(systemName: "checkmark").foregroundStyle(.tint)
                                        }
                                    }
                                    .contentShape(.rect)
                                }
                                .tint(.primary)
                            }
                        } else {
                            Text("Pick a provider for this conversation first.").foregroundStyle(.secondary)
                        }
                    }
                    // As the pill offers them: when there is more than one,
                    // and when the conversation has none.
                    if provider == nil || model.providers.count > 1 {
                        Section("Provider") {
                            ForEach(model.providers) { config in
                                Button {
                                    model.select(provider: config.id, for: conversationID)
                                } label: {
                                    HStack {
                                        Text(config.name)
                                        Spacer()
                                        if config.id == provider?.id {
                                            Image(systemName: "checkmark").foregroundStyle(.tint)
                                        }
                                    }
                                    .contentShape(.rect)
                                }
                                .tint(.primary)
                                .disabled(!model.canChangeProvider(of: conversation))
                                .accessibilityLabel("Provider, \(config.name)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Model")
        }
    }
#endif
