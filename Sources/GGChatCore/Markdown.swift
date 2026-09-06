import Foundation
import Markdown

/// The transcript's shape: a flat list of blocks. Prose is an
/// `AttributedString` with inline styling; code is kept raw for the inset
/// panel and its copy button.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(AttributedString)
    case heading(level: Int, AttributedString)
    case code(language: String?, text: String)
    case list(ordered: Bool, items: [AttributedString])
    case quote([MarkdownBlock])
    case thematicBreak
}

public enum MarkdownBlocks {
    /// Parses CommonMark. An unterminated fence, as seen mid-stream, is a
    /// code block to the end of the text, so streaming code never flashes
    /// as prose.
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let document = Document(parsing: text)
        return document.children.compactMap(block(for:))
    }

    private static func block(for markup: any Markup) -> MarkdownBlock? {
        switch markup {
        case let paragraph as Paragraph:
            return .paragraph(inline(paragraph))
        case let heading as Heading:
            return .heading(level: heading.level, inline(heading))
        case let code as CodeBlock:
            let language = code.language?.trimmingCharacters(in: .whitespaces)
            var text = code.code
            if text.hasSuffix("\n") { text.removeLast() }
            return .code(language: language.flatMap { $0.isEmpty ? nil : $0 }, text: text)
        case let list as UnorderedList:
            return .list(ordered: false, items: list.children.map(listItem(for:)))
        case let list as OrderedList:
            return .list(ordered: true, items: list.children.map(listItem(for:)))
        case let quote as BlockQuote:
            return .quote(quote.children.compactMap(block(for:)))
        case is ThematicBreak:
            return .thematicBreak
        case let html as HTMLBlock:
            return .code(language: "html", text: html.rawHTML)
        case let table as Table:
            return .code(language: nil, text: table.format())
        default:
            return .paragraph(AttributedString(markup.format()))
        }
    }

    private static func listItem(for markup: any Markup) -> AttributedString {
        let pieces = markup.children.map { child -> AttributedString in
            if let paragraph = child as? Paragraph { return inline(paragraph) }
            return AttributedString(child.format().trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var joined = AttributedString()
        for (index, piece) in pieces.enumerated() {
            if index > 0 { joined += AttributedString("\n") }
            joined += piece
        }
        return joined
    }

    /// Inline styling via Foundation, which understands emphasis, strong,
    /// code spans and links.
    private static func inline(_ container: some Markup) -> AttributedString {
        // `format()` renders a node in the context of its ancestors, so a
        // paragraph inside a block quote comes back with its "> " marker and
        // one inside a list item comes back indented. Detaching drops that
        // context, leaving the inline markdown alone.
        let source: String = container.detachedFromParent.children.map { $0.format() }.joined()
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}
