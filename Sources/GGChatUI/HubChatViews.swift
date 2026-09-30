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

/// One of a Mac's chats: its title, the model it was made with, and
/// "Writing" while the Mac is writing a reply to it.
struct HubChatRow: View {
    @Environment(AppModel.self) private var model
    let chat: HubChatSummary
    let providerID: UUID

    var body: some View {
        let mark = model.mark(for: chat, on: providerID)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(chat.title.isEmpty ? "New conversation" : chat.title)
                    .lineLimit(1)
                if let mark {
                    Spacer(minLength: 4)
                    ConversationMarkView(mark: mark)
                }
            }
            if let modelName = chat.model {
                Text(modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A Mac's chat, read live and read only. Nothing here is kept: going Back
/// drops it, and opening it again reads it again.
struct HubChatView: View {
    let chat: OpenHubChat

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if case .read(let rows) = chat.state {
                    ForEach(rows) { message in
                        MessageRow(message: message, showsEnding: false, advice: nil, writingLine: nil)
                    }
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
            case .read(let rows) where rows.isEmpty:
                ContentUnavailableView("Nothing said yet", systemImage: "text.bubble")
            case .read:
                EmptyView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Continue from this phone comes in the next update.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .navigationTitle(chat.title.isEmpty ? "New conversation" : chat.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
