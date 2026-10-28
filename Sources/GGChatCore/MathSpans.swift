import Foundation

/// Math in a reply, kept from the markdown parse so it reads as written.
///
/// CommonMark would read LaTeX as markdown: `\{` and `\,` as escapes that
/// lose their backslash, `\\` as one backslash, and the `*` of `f*g` as
/// emphasis. So before a parse each math span is wrapped as a code span,
/// which both parsers ggchat runs leave alone, with a private-use marker at
/// its start, and after it the marked code spans are unwrapped again.
///
/// The spans are those KaTeX reads: `$$…$$`, `\[…\]` and `\(…\)`, which may
/// run over lines, and `$…$`, which may not. A `$` opens math only before a
/// character that is not a space and closes it only after one, and not
/// before a digit, so `$5 and $6` stays text. A backslash and
/// the punctuation after it are one unit wherever they are, so `\$` is
/// neither an opener nor a closer, and the `\[` of `\\[4pt]` opens nothing.
/// A `|` inside a span stands in as ``pipe`` while it is wrapped, since a
/// table splits its row at every `|`, code spans included. Wrapping adds no
/// newline, so a line of the text is the same line after it.
enum MathSpans {
    /// Starts every code span `protect` makes. It and ``pipe`` sit in the
    /// private use area, so no reply means them.
    static let marker: Character = "\u{E000}"
    static let pipe: Character = "\u{E001}"

    /// `text` with each math span wrapped as a code span starting with
    /// ``marker``.
    static func protect(_ text: String) -> String {
        let bytes = Array(text.utf8)
        guard bytes.contains(dollar) || bytes.contains(backslash) else { return text }
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + 16)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == backtick {
                // A code span is copied whole; a run with no match is text.
                let end = codeSpanEnd(bytes, at: index)
                out += bytes[index..<end]
                index = end
                continue
            }
            if let end = spanEnd(bytes, at: index) {
                out += Array("`\(marker)".utf8)
                for byte in bytes[index..<end] {
                    if byte == UInt8(ascii: "|") { out += Array(String(pipe).utf8) } else { out.append(byte) }
                }
                out.append(backtick)
                index = end
                continue
            }
            let width = byte == backslash && index + 1 < bytes.count && isPunctuation(bytes[index + 1]) ? 2 : 1
            out += bytes[index..<index + width]
            index += width
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// `text` with each code span `protect` made back as plain text, and any
    /// other ``marker`` dropped, so a span the parser broke shows a stray
    /// backtick at worst. Each ``pipe`` is a `|` again.
    static func unwrap(_ text: AttributedString) -> AttributedString {
        guard text.characters.contains(marker) else { return text }
        var text = text
        let spans = text.runs.filter { run in
            run.inlinePresentationIntent?.contains(.code) == true && text[run.range].characters.first == marker
        }
        for run in spans {
            let intent = run.inlinePresentationIntent?.subtracting(.code)
            text[run.range].inlinePresentationIntent = intent?.isEmpty == true ? nil : intent
        }
        while let index = text.characters.firstIndex(of: marker) {
            text.characters.remove(at: index)
        }
        while let index = text.characters.firstIndex(of: pipe) {
            text.characters.replaceSubrange(index...index, with: "|")
        }
        return text
    }

    /// `text`, where markdown is shown as written, with each code span
    /// `protect` made back as its content.
    static func unwrap(_ text: String) -> String {
        guard text.contains(marker) else { return text }
        return text.replacing(/`\u{E000}([^`]*)`/) { $0.1 }
            .replacing(String(marker), with: "")
            .replacing(String(pipe), with: "|")
    }

    // MARK: - Spans

    /// The end of the math span opening at `index`, if one does.
    private static func spanEnd(_ bytes: [UInt8], at index: Int) -> Int? {
        let next = index + 1 < bytes.count ? bytes[index + 1] : nil
        switch (bytes[index], next) {
        case (dollar, dollar):
            return multilineEnd(bytes, from: index + 2, closer: [dollar, dollar])
        case (backslash, UInt8(ascii: "[")):
            return multilineEnd(bytes, from: index + 2, closer: [backslash, UInt8(ascii: "]")])
        case (backslash, UInt8(ascii: "(")):
            return multilineEnd(bytes, from: index + 2, closer: [backslash, UInt8(ascii: ")")])
        case (dollar, let next?) where !isSpace(next):
            return dollarEnd(bytes, from: index + 1)
        default:
            return nil
        }
    }

    /// The end of `$…$` whose content starts at `start`. The first `$` after
    /// the opener is its only closer: if that one cannot close, nothing does.
    private static func dollarEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\n"), backtick:
                return nil
            case backslash where index + 1 < bytes.count && isPunctuation(bytes[index + 1]):
                index += 2
                continue
            case dollar:
                let closes = !isSpace(bytes[index - 1]) && (index + 1 == bytes.count || !isDigit(bytes[index + 1]))
                return closes ? index + 1 : nil
            default:
                break
            }
            index += 1
        }
        return nil
    }

    /// The end of a span whose content starts at `start`, which ends with
    /// `closer` and may run over lines while they are one paragraph's.
    private static func multilineEnd(_ bytes: [UInt8], from start: Int, closer: [UInt8]) -> Int? {
        let quoted = opensInAQuote(bytes, at: start)
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case backtick:
                return nil
            case UInt8(ascii: "\n"):
                if !runsOn(bytes, at: index, quoted: quoted) { return nil }
            case closer[0] where index + 1 < bytes.count && bytes[index + 1] == closer[1]:
                return index + 2
            case backslash where index + 1 < bytes.count && isPunctuation(bytes[index + 1]):
                index += 2
                continue
            default:
                break
            }
            index += 1
        }
        return nil
    }

    // MARK: - Lines

    /// Whether inline text runs on past the newline at `newline` into the
    /// next line, as a paragraph's does. A heading or a table row ends at
    /// its line, so neither runs on, nor does a paragraph the next line could
    /// end. The parse of a streaming reply restarts at a line where a block
    /// starts, so a span read over such a line would be read differently.
    private static func runsOn(_ bytes: [UInt8], at newline: Int, quoted: Bool) -> Bool {
        let start = lineStart(bytes, at: newline)
        let line = bytes[start..<newline]
        if line.drop(while: { " \t>-+*.)0123456789".utf8.contains($0) }).first == UInt8(ascii: "#") { return false }
        if isTableRow(bytes, lineAt: start) { return false }
        return continuesAParagraph(bytes, lineAt: newline + 1, quoted: quoted)
    }

    /// Whether the line starting at `start` is a table's: it and every line
    /// up to a delimiter row above it hold a `|`.
    private static func isTableRow(_ bytes: [UInt8], lineAt start: Int) -> Bool {
        var start = start
        while true {
            let line = bytes[start..<lineEnd(bytes, at: start)]
            guard line.contains(UInt8(ascii: "|")) else { return false }
            if isDelimiterRow(line) { return true }
            guard start > 0 else { return false }
            start = lineStart(bytes, at: start - 1)
        }
    }

    /// Whether `line` could be a table's delimiter row: only `|`, `:` and
    /// `-`, with a `-`.
    private static func isDelimiterRow(_ line: ArraySlice<UInt8>) -> Bool {
        let marks = line.filter { !isSpace($0) }
        return marks.contains(UInt8(ascii: "-")) && marks.allSatisfy { "|:-".utf8.contains($0) }
    }

    /// The start of the line holding `index`.
    private static func lineStart(_ bytes: [UInt8], at index: Int) -> Int {
        var start = index
        while start > 0, bytes[start - 1] != UInt8(ascii: "\n") { start -= 1 }
        return start
    }

    /// The end of the line holding `index`, before its newline.
    private static func lineEnd(_ bytes: [UInt8], at index: Int) -> Int {
        var end = index
        while end < bytes.count, bytes[end] != UInt8(ascii: "\n") { end += 1 }
        return end
    }

    /// Whether the line starting at `start` carries on a paragraph whatever
    /// it holds: it is not blank and could not start a heading, a fence, a
    /// quote, HTML, a list item, a thematic break, a setext underline or a
    /// table's delimiter row. Indentation is no block of its own here, since
    /// indented code cannot interrupt a paragraph. `quoted` lets the `>` that
    /// carries on a quote stand at the start.
    private static func continuesAParagraph(_ bytes: [UInt8], lineAt start: Int, quoted: Bool) -> Bool {
        var line = bytes[start..<lineEnd(bytes, at: start)].drop(while: isSpace)
        if quoted { line = line.drop { $0 == UInt8(ascii: ">") || isSpace($0) } }
        guard let first = line.first else { return false }
        if "#<>".utf8.contains(first) { return false }
        if line.starts(with: "```".utf8) || line.starts(with: "~~~".utf8) { return false }
        let second = line.dropFirst().first
        if "-+*".utf8.contains(first), second.map(isSpace) ?? true { return false }
        let digits = line.prefix(while: isDigit)
        if !digits.isEmpty, let after = line.dropFirst(digits.count).first,
            after == UInt8(ascii: ".") || after == UInt8(ascii: ")"),
            line.dropFirst(digits.count + 1).first.map(isSpace) ?? true
        {
            return false
        }
        if "-*_=".utf8.contains(first), line.filter({ !isSpace($0) }).allSatisfy({ $0 == first }) { return false }
        return !isDelimiterRow(line)
    }

    /// Whether the line holding `index` is in a block quote: a `>` comes
    /// before anything but indentation.
    private static func opensInAQuote(_ bytes: [UInt8], at index: Int) -> Bool {
        bytes[lineStart(bytes, at: index)..<index].drop(while: isSpace).first == UInt8(ascii: ">")
    }

    /// The end of the backtick run at `index` and, when a run as long closes
    /// it within the paragraph, of the code span it opens.
    private static func codeSpanEnd(_ bytes: [UInt8], at index: Int) -> Int {
        let quoted = opensInAQuote(bytes, at: index)
        var runEnd = index
        while runEnd < bytes.count, bytes[runEnd] == backtick { runEnd += 1 }
        let length = runEnd - index
        var cursor = runEnd
        while cursor < bytes.count {
            if bytes[cursor] == UInt8(ascii: "\n"), !runsOn(bytes, at: cursor, quoted: quoted) {
                return runEnd
            }
            guard bytes[cursor] == backtick else {
                cursor += 1
                continue
            }
            var closeEnd = cursor
            while closeEnd < bytes.count, bytes[closeEnd] == backtick { closeEnd += 1 }
            if closeEnd - cursor == length { return closeEnd }
            cursor = closeEnd
        }
        return runEnd
    }

    // MARK: - Bytes

    private static let dollar = UInt8(ascii: "$")
    private static let backslash = UInt8(ascii: "\\")
    private static let backtick = UInt8(ascii: "`")

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n")
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    /// ASCII punctuation, which a backslash escapes in CommonMark.
    private static func isPunctuation(_ byte: UInt8) -> Bool {
        (0x21...0x2F).contains(byte) || (0x3A...0x40).contains(byte) || (0x5B...0x60).contains(byte)
            || (0x7B...0x7E).contains(byte)
    }
}
