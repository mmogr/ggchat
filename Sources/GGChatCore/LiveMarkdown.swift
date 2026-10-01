import Markdown

/// A reply's markdown while it streams, parsed so that a token parses only
/// the text that can still change rather than the whole reply.
///
/// Markdown is read a line at a time, and a block is closed for good once a
/// complete line after it has started the next one. So the blocks before the
/// last such boundary are kept, and each update parses only from the line
/// after them. The last block stays open: a code fence or a table still
/// being written is parsed again with every token. ``blocks`` is always what
/// ``MarkdownBlocks/parse(_:)`` gives for the same text.
///
/// Two things reach across blocks, and text that may hold either is parsed
/// whole from then on: a link reference definition (`[label]: url`), which
/// can turn text in any block into a link, and a carriage return or a
/// byte-order mark, which would move where a line starts.
public struct LiveMarkdown: Sendable {
    /// The blocks for the text last given to ``update(to:)``.
    public private(set) var blocks: [MarkdownBlock] = []
    /// The text last given.
    private var text = ""
    /// The blocks no later text can change, and the UTF-8 offset of the line
    /// after them, where each parse starts.
    private var settled: [MarkdownBlock] = []
    private var settledEnd = 0
    /// How much of the text, in whole lines, has been looked at for a block
    /// to settle.
    private var checkedEnd = 0
    /// Set once the text may hold something that reaches across blocks.
    private var parsesWhole = false

    public init() {}

    /// Parses `newText`, keeping the settled blocks of the last parse when
    /// `newText` carries on from the text last given.
    public mutating func update(to newText: String) {
        var newText = newText
        var oldText = text
        newText.withUTF8 { new in
            oldText.withUTF8 { old in
                let carriesOn = Self.starts(new, with: old)
                if carriesOn, new.count == old.count { return }
                if !carriesOn { self = LiveMarkdown() }
                if !parsesWhole, MarkdownScan.mayReachAcrossBlocks(new, from: carriesOn ? old.count : 0) {
                    parsesWhole = true
                }
                if parsesWhole {
                    blocks = MarkdownBlocks.blocks(of: parse(new, from: 0, to: new.count))
                    return
                }
                let tail = parse(new, from: settledEnd, to: new.count)
                blocks = settled + MarkdownBlocks.blocks(of: tail)
                settle(new, tail: tail)
            }
        }
        text = newText
    }

    /// Moves `settledEnd` past every block a complete line has closed. Only
    /// complete lines are read for this: a line still arriving can end a
    /// block that the whole line carries on. Under a paragraph whose last
    /// line could be a table's header, `|---` makes a table and ends the
    /// paragraph above it, until the line turns out to be `|---x`.
    private mutating func settle(_ new: UnsafeBufferPointer<UInt8>, tail: [any Markup]) {
        var completeEnd = new.count
        while completeEnd > checkedEnd, new[completeEnd - 1] != UInt8(ascii: "\n") { completeEnd -= 1 }
        guard completeEnd > checkedEnd else { return }
        checkedEnd = completeEnd
        let children = completeEnd == new.count ? tail : parse(new, from: settledEnd, to: completeEnd)
        let lines = children.map { $0.range.map { (first: $0.lowerBound.line, last: $0.upperBound.line) } }
        guard let next = Self.lastCleanStart(lines) else { return }
        settled += MarkdownBlocks.blocks(of: children[..<next.index])
        settledEnd += MarkdownScan.offset(ofLine: next.line, in: UnsafeBufferPointer(rebasing: new[settledEnd...]))
    }

    private func parse(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> [any Markup] {
        let source = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self)
        return MarkdownBlocks.children(parsing: source)
    }

    /// Given the lines each child spans, the last child, after the first,
    /// that starts on a line below the end of the one before it: everything
    /// before it is closed. A child whose lines are unknown is never a
    /// boundary, nor one that starts on a line the child before it reaches
    /// into. A table reaches back into the paragraph whose last line became
    /// its header; that paragraph has no lines today, and the table would
    /// overlap it if it had.
    static func lastCleanStart(_ lines: [(first: Int, last: Int)?]) -> (index: Int, line: Int)? {
        for index in lines.indices.dropFirst().reversed() {
            guard let span = lines[index], let before = lines[index - 1] else { continue }
            if span.first > before.last { return (index, span.first) }
        }
        return nil
    }

    private static func starts(_ bytes: UnsafeBufferPointer<UInt8>, with prefix: UnsafeBufferPointer<UInt8>) -> Bool {
        bytes.count >= prefix.count && bytes.prefix(prefix.count).elementsEqual(prefix)
    }
}
