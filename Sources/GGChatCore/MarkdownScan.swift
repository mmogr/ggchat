/// Byte scans `LiveMarkdown` makes before trusting a parse of part of a
/// text. Its questions are answered on the safe side: a yes may be wrong,
/// a no may not.
enum MarkdownScan {
    /// Whether the bytes from `start` on may hold something that reaches
    /// across blocks: a carriage return or a byte-order mark, either of which
    /// would move where a line starts, or the `]:` of what may be a link
    /// reference definition. One byte before `start` is read again, for a
    /// `]` the earlier text ended on.
    static func mayReachAcrossBlocks(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Bool {
        var index = max(0, start - 1)
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\r"):
                return true
            case 0xEF where index + 2 < bytes.count && bytes[index + 1] == 0xBB && bytes[index + 2] == 0xBF:
                return true
            case UInt8(ascii: "]") where index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: ":"):
                if mayCloseADefinitionLabel(bytes, at: index) { return true }
            default:
                break
            }
            index += 1
        }
        return false
    }

    /// Whether the `]` at `close`, followed by `:`, may end the label of a
    /// link reference definition. Such a label opens with the first `[` on
    /// its line, after nothing but the markers of the blocks it sits in, and
    /// holds no other unescaped bracket and no blank line.
    static func mayCloseADefinitionLabel(_ bytes: UnsafeBufferPointer<UInt8>, at close: Int) -> Bool {
        var index = close - 1
        // The line walked so far; the one the `]` is on is not blank.
        var lineIsBlank = false
        while index >= 0 {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\n") {
                if lineIsBlank { return false }
                lineIsBlank = true
            } else if byte == UInt8(ascii: "]"), !isEscaped(bytes, at: index) {
                return false
            } else if byte == UInt8(ascii: "["), !isEscaped(bytes, at: index) {
                return startsItsLine(bytes, at: index)
            } else if byte != UInt8(ascii: " "), byte != UInt8(ascii: "\t") {
                lineIsBlank = false
            }
            index -= 1
        }
        return false
    }

    /// Whether only container markers stand between the line's start and
    /// `index`: indentation, `>`, a bullet or an ordered marker, and a task
    /// box, all of which the parser reads before a paragraph begins.
    private static func startsItsLine(_ bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
        var before = index - 1
        while before >= 0, bytes[before] != UInt8(ascii: "\n") {
            guard markerBytes.contains(bytes[before]) else { return false }
            before -= 1
        }
        return true
    }

    private static let markerBytes = Set(" \t>-+*.)[]xX0123456789".utf8)

    private static func isEscaped(_ bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
        var backslashes = 0
        var before = index - 1
        while before >= 0, bytes[before] == UInt8(ascii: "\\") {
            backslashes += 1
            before -= 1
        }
        return backslashes % 2 == 1
    }

    /// The UTF-8 offset where 1-based `line` starts, or the end when the
    /// bytes have fewer lines.
    static func offset(ofLine line: Int, in bytes: UnsafeBufferPointer<UInt8>) -> Int {
        var seen = 1
        var offset = 0
        while seen < line, offset < bytes.count {
            if bytes[offset] == UInt8(ascii: "\n") { seen += 1 }
            offset += 1
        }
        return offset
    }
}
