import Foundation

extension BranchRules {
    /// The longest preview, in characters, before it is cut with "…".
    public static let previewLength = 80

    /// The branch points chat `me`'s family holds along it, at the start of
    /// each of its turns and after its last row. Each option is shown by the
    /// chat that holds it and changed last, the open chat by itself.
    public static func points<ChatID, ID, Key, Stamp>(
        _ me: ChatID, family: [LineChat<ChatID, ID, Key, Stamp>]
    ) -> [BranchPoint<ChatID, ID>] {
        guard let mine = family.first(where: { $0.chatID == me }) else { return [] }
        let starts = units(mine.rows.map(\.role)).map(\.rows.lowerBound)
        return (starts + [mine.rows.count]).compactMap { point(mine, family, at: $0) }
    }

    private static func point<ChatID, ID, Key, Stamp>(
        _ mine: LineChat<ChatID, ID, Key, Stamp>, _ family: [LineChat<ChatID, ID, Key, Stamp>], at: Int
    ) -> BranchPoint<ChatID, ID>? {
        let shares = { (chat: LineChat<ChatID, ID, Key, Stamp>) in
            at == 0 || (chat.rows.count >= at && chat.rows[at - 1].key == mine.rows[at - 1].key)
        }
        var turns: [Key: LineChat<ChatID, ID, Key, Stamp>] = [:]
        for chat in family where shares(chat) && startsTurn(chat.rows, at) {
            let key = chat.rows[at].key
            guard let shown = turns[key] else {
                turns[key] = chat
                continue
            }
            let newer = (chat.updatedAt, chat.chatID) > (shown.updatedAt, shown.chatID)
            if shown.chatID != mine.chatID, chat.chatID == mine.chatID || newer { turns[key] = chat }
        }
        let empty = at == mine.rows.count
        guard turns.count + (empty ? 1 : 0) >= 2 else { return nil }
        var options = turns.sorted { $0.key < $1.key }.map { option($0.value, at: at) }
        if empty { options.append(BranchOption(chatID: mine.chatID, messageID: nil, role: nil, preview: "")) }
        guard let index = options.firstIndex(where: { $0.chatID == mine.chatID }) else { return nil }
        return BranchPoint(messageID: at < mine.rows.count ? mine.rows[at].id : nil, index: index, options: options)
    }

    private static func startsTurn<ID, Key>(_ rows: [LineRow<ID, Key>], _ at: Int) -> Bool {
        at < rows.count && (rows[at].role == .user || at == 0 || rows[at - 1].role == .user)
    }

    private static func option<ChatID, ID, Key, Stamp>(
        _ chat: LineChat<ChatID, ID, Key, Stamp>, at: Int
    ) -> BranchOption<ChatID, ID> {
        let row = chat.rows[at]
        var turn = [row]
        if row.role != .user {
            turn += chat.rows[(at + 1)...].prefix { $0.role != .user }
        }
        return BranchOption(chatID: chat.chatID, messageID: row.id, role: row.role, preview: preview(turn))
    }

    /// The line a turn is shown by among a point's options: a question's
    /// first line of text, or what stands in for an image; a reply's last
    /// assistant line, or "(no text)".
    public static func preview<ID, Key>(_ turn: [LineRow<ID, Key>]) -> String {
        guard let first = turn.first else { return "" }
        if first.role == .user {
            let line = firstLine(first.text)
            if !line.isEmpty || first.images == 0 { return line }
            return first.images == 1 ? "An image" : "\(first.images) images"
        }
        let lines = turn.filter { $0.role == .assistant }.map { firstLine($0.text) }
        return lines.last { !$0.isEmpty } ?? "(no text)"
    }

    /// The first line of `text` with any text, trimmed, cut at
    /// ``previewLength`` Unicode scalars. A line ends at `\n` or `\r\n`, as
    /// Rust's `lines` ends one: Swift holds `\r\n` as one character.
    static func firstLine(_ text: String) -> String {
        let line =
            text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let scalars = line.unicodeScalars
        guard scalars.count > previewLength else { return line }
        var cut = String.UnicodeScalarView()
        cut.append(contentsOf: scalars.prefix(previewLength))
        return String(cut) + "…"
    }
}
