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

    /// The composer's model list, pushed on the panel: the same sections,
    /// rows and pick, as a list of its own with the system's search. No
    /// chips, since every section is in reach on a page this tall.
    private struct ModelChoice: View {
        @Environment(AppModel.self) private var model
        @Environment(\.dismiss) private var dismiss
        @Environment(\.locale) private var locale
        @Environment(\.calendar) private var calendar
        @State private var query = ""
        let conversationID: UUID

        /// The conversation as it is now, not as it was when pushed.
        private var conversation: Conversation? {
            model.conversations.first { $0.id == conversationID }
        }

        var body: some View {
            let list = conversation.map {
                model.modelList(for: $0, filter: nil, query: query, locale: locale, calendar: calendar)
            }
            List {
                if let conversation, let list {
                    let canMove = model.canChangeProvider(of: conversation)
                    if !canMove, list.sections.contains(where: \.moves) {
                        Text(ModelList.waitsForTheReply).font(.footnote).foregroundStyle(.secondary)
                    }
                    if list.foundNothing {
                        Text("No models match \u{201C}\(list.query)\u{201D}.").foregroundStyle(.secondary)
                    }
                    ForEach(list.sections) { section in
                        Section {
                            rows(section, canMove: canMove)
                        } header: {
                            Label(
                                section.state.map { "\(section.provider.name) · \($0)" } ?? section.provider.name,
                                systemImage: section.provider.symbol)
                        }
                    }
                }
            }
            .navigationTitle("Model")
            .searchable(text: $query, prompt: "Search models")
            .onAppear { model.relistModels() }
        }

        @ViewBuilder
        private func rows(_ section: ModelListSection, canMove: Bool) -> some View {
            if section.offersConnect {
                Button("Connect") { model.connect(fromTheList: section.id) }
                    .accessibilityHint("Dials \(section.provider.name) to list its models")
            } else if !section.isListed {
                Text("Not listed yet").foregroundStyle(.tertiary)
            } else if section.rows.isEmpty, query.isEmpty {
                Text(section.provider.kind == .onDevice ? "No models on this iPhone yet." : "No models listed.")
                    .foregroundStyle(.tertiary)
            }
            ForEach(section.rows) { row in
                let held = section.moves && !canMove
                Button {
                    model.pick(model: row.modelID, on: section.id, for: conversationID)
                    dismiss()
                } label: {
                    ModelListRowLabel(row: row, dimmed: section.isStale || held).contentShape(.rect)
                }
                .tint(.primary)
                .disabled(held)
                .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
                .accessibilityHint(section.moves ? "Moves this conversation to \(section.provider.name)" : "")
            }
            // As the composer's list offers it.
            if section.provider.kind == .onDevice, model.runsModelsHere {
                Button("Find a model…") { model.openModelBrowser() }
            }
        }
    }
#endif
