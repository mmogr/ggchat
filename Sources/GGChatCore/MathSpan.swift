import Foundation

/// A math span in a reply's text, as the parse marks it: the text keeps the
/// span exactly as written, delimiters and all, so a copy reads as the model
/// wrote it, and a view that can typeset the LaTeX draws this instead.
public struct MathSpan: Hashable, Sendable {
    /// The LaTeX between the delimiters, trimmed.
    public let latex: String
    /// Written as display math, `$$…$$` or `\[…\]`, rather than `$…$` or
    /// `\(…\)`.
    public let isDisplay: Bool

    public init(latex: String, isDisplay: Bool) {
        self.latex = latex
        self.isDisplay = isDisplay
    }

    /// The span `source` is, delimiters and all, as `MathSpans` finds them.
    init(source: String) {
        let delimiters: [(open: String, close: String)] = [
            ("$$", "$$"), (#"\["#, #"\]"#), (#"\("#, #"\)"#), ("$", "$"),
        ]
        let match = delimiters.first { source.count >= $0.open.count + $0.close.count && source.hasPrefix($0.open) }
        guard let match, source.hasSuffix(match.close) else {
            self.init(latex: source, isDisplay: false)
            return
        }
        let inner = source.dropFirst(match.open.count).dropLast(match.close.count)
        let display = match.open == "$$" || match.open == #"\["#
        self.init(latex: inner.trimmingCharacters(in: .whitespacesAndNewlines), isDisplay: display)
    }

    /// The span `text` is, when it is nothing but one display math span and
    /// the space around it: math that stands as a block of its own.
    public static func standingAlone(in text: AttributedString) -> MathSpan? {
        var found: MathSpan?
        for run in text.runs {
            if let span = run[MathAttribute.self] {
                guard found == nil, span.isDisplay else { return nil }
                found = span
            } else if !String(text[run.range].characters).allSatisfy(\.isWhitespace) {
                return nil
            }
        }
        return found
    }
}

/// Marks a run of a reply's text as math.
public enum MathAttribute: AttributedStringKey {
    public typealias Value = MathSpan
    public static let name = "ggchat.math"
}
