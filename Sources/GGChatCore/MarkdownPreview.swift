import Foundation

/// The opening of a message, as a long press lifts it: whole blocks from the
/// top, as many as fit a budget of characters, so a reply of two hundred
/// lines lifts as a card of its first few rather than the whole reply shrunk
/// until nothing in it can be read.
public struct MarkdownPreview: Equatable, Sendable {
    /// The blocks the card shows, in order.
    public let blocks: [MarkdownBlock]
    /// Whether blocks were left out after them.
    public let isCut: Bool

    /// The characters a card holds before its blocks stop: about twenty
    /// lines of body text at the card's width.
    public static let budget = 700

    /// Whole blocks from the top of `blocks` until the next would pass
    /// `budget` characters. The first block is always taken, however long:
    /// the card's own height cuts it, and a card with nothing in it says
    /// nothing.
    public init(_ blocks: [MarkdownBlock], budget: Int = Self.budget) {
        var taken: [MarkdownBlock] = []
        var spent = 0
        for block in blocks {
            let cost = Self.characters(in: block)
            if !taken.isEmpty, spent + cost > budget { break }
            taken.append(block)
            spent += cost
        }
        self.blocks = taken
        isCut = taken.count < blocks.count
    }

    /// The characters a block shows, counted as read rather than as typed.
    static func characters(in block: MarkdownBlock) -> Int {
        switch block {
        case .paragraph(let text), .heading(_, let text):
            text.characters.count
        case .code(_, let text):
            text.count
        case .list(_, let items):
            items.reduce(0) { $0 + $1.characters.count }
        case .quote(let inner):
            inner.reduce(0) { $0 + characters(in: $1) }
        case .thematicBreak:
            0
        case .table(let table):
            (table.rows + [table.header]).joined().reduce(0) { $0 + $1.characters.count }
        }
    }
}
