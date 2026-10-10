import GGChatCore
import SwiftUI

/// What a switcher shows and does at a branch point, whatever ids its
/// chats have: which option is open, each option's line, and how to open
/// the option at an index.
struct BranchChoice {
    let index: Int
    let lines: [String]
    let open: (Int) -> Void

    /// The choice at `point`, opening an option's chat by `open`.
    init<ChatID, ID>(_ point: BranchPoint<ChatID, ID>, open: @escaping (ChatID) -> Void) {
        index = point.index
        lines = point.options.map(Self.line(for:))
        let chats = point.options.map(\.chatID)
        self.open = { open(chats[$0]) }
    }

    /// Which option the open chat is, of how many: "2/3".
    var position: String {
        "\(index + 1)/\(lines.count)"
    }

    /// The same, as VoiceOver says it.
    var spokenPosition: String {
        "Branch \(index + 1) of \(lines.count)"
    }

    /// How an option is listed: its line, or what stands in for one.
    static func line<ChatID, ID>(for option: BranchOption<ChatID, ID>) -> String {
        if option.messageID == nil { return "Nothing here yet" }
        return option.preview.isEmpty ? "(no text)" : option.preview
    }
}

/// The options at a branch point (ADR 0010): the previous and the next open
/// those chats, and the count lists every option by its line, the open one
/// checked. Choosing the open one does nothing.
struct BranchSwitcher: View {
    let choice: BranchChoice

    var body: some View {
        HStack(spacing: 2) {
            Button("Previous branch", systemImage: "chevron.left") {
                choice.open(choice.index - 1)
            }
            .disabled(choice.index == 0)
            Menu {
                ForEach(Array(choice.lines.enumerated()), id: \.offset) { at, line in
                    Button {
                        if at != choice.index { choice.open(at) }
                    } label: {
                        if at == choice.index {
                            Label(line, systemImage: "checkmark")
                        } else {
                            Text(line)
                        }
                    }
                }
            } label: {
                Text(choice.position)
                    .monospacedDigit()
            }
            .accessibilityLabel(choice.spokenPosition)
            Button("Next branch", systemImage: "chevron.right") {
                choice.open(choice.index + 1)
            }
            .disabled(choice.index == choice.lines.count - 1)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// After a chat's last message, where other chats of its family go on:
/// says so, with the switcher.
struct BranchEndRow: View {
    let choice: BranchChoice

    var body: some View {
        HStack(spacing: 8) {
            Text("Other branches go on from here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            BranchSwitcher(choice: choice)
        }
    }
}

/// What a row's menu offers on a turn (ADR 0010): the same three changes on
/// this device's conversation and on a Mac's chat, each made its own way.
struct MessageChanges {
    /// Opens the editor on the turn.
    let edit: (Message) -> Void
    let regenerate: (UUID) -> Void
    let branch: (UUID) -> Void
}

/// Beside a chat's title in the list: it is a branch of another.
struct BranchMark: View {
    var body: some View {
        Image(systemName: "arrow.triangle.branch")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Branch")
    }
}
