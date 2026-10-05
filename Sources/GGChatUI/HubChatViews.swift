import GGChatCore
import SwiftUI

/// "On home": a paired Mac's chats, in the list below this phone's own.
struct HubChatsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    let config: ProviderConfig

    var body: some View {
        Section("On \(config.name)") {
            ForEach(model.hubChats[config.id] ?? []) { chat in
                HubChatRow(chat: chat, providerID: config.id)
                    .tag(SidebarSelection.hub(providerID: config.id, chatID: chat.id))
            }
            if let line = model.hubLine(for: config.id, locale: locale, calendar: calendar) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One of a Mac's chats: its title, the model it was made with, when it last
/// changed, and "Writing" while the Mac is writing a reply to it.
struct HubChatRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    let chat: HubChatSummary
    let providerID: UUID

    var body: some View {
        let mark = model.mark(for: chat, on: providerID)
        let stamp = model.stamp(for: chat, locale: locale, calendar: calendar)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(chat.title.isEmpty ? "New conversation" : chat.title)
                    .lineLimit(1)
                if let mark {
                    Spacer(minLength: 4)
                    ConversationMarkView(mark: mark)
                }
            }
            if chat.model != nil || stamp != nil {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(chat.model ?? "")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let stamp {
                        Text(stamp)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A Mac's chat, read live and carried on from here. Nothing here is kept:
/// going Back drops it, and opening it again reads it again.
struct HubChatView: View {
    @Environment(AppModel.self) private var model
    let chat: OpenHubChat

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if case .read(let rows) = chat.state {
                    ForEach(rows) { message in
                        MessageRow(
                            message: message, showsEnding: false, advice: nil, writingLine: nil, imagesFromHub: true)
                    }
                }
                if let reply = model.openHubReply {
                    HubLiveReplyRows(reply: reply, rows: chat.state)
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
            switch chat.state {
            case .reading:
                ProgressView()
                    .accessibilityLabel("Reading the chat")
            case .unavailable(let why):
                ContentUnavailableView(why, systemImage: "desktopcomputer")
            case .read(let rows) where rows.isEmpty && model.openHubReply == nil:
                ContentUnavailableView("Nothing said yet", systemImage: "text.bubble")
            case .read:
                EmptyView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            HubComposer(notice: chat.notice, unsent: chat.unsent)
        }
        .navigationTitle(chat.title.isEmpty ? "New conversation" : chat.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            // Only for a model the Mac lists as one that thinks. The Mac
            // remembers the choice; here it is held with the chat.
            if model.hubChatOffersThinking {
                ToolbarItem(placement: .automatic) {
                    ThinkingToggle(isOn: model.hubThinkingOn) { model.setHubThinking(on: $0) }
                }
            }
        }
    }
}
