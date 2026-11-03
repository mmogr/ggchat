import GGChatCore
import SwiftMath
import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// A reply's inline text with its math typeset, at the size of `style` and
/// in the text's own colour. A span SwiftMath cannot read is shown as the
/// model wrote it. Selecting and copying the text gives an object character
/// where math was drawn, so a reply's menu copies it as written.
struct MathText: View {
    let text: AttributedString
    var style: Font.TextStyle = .body
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if text.runs.contains(where: { $0[MathAttribute.self] != nil }) {
            let size = MathImages.pointSize(for: style, typeSize: typeSize)
            text.runs.reduce(Text(verbatim: "")) { line, run in
                let piece = text[run.range]
                if let span = run[MathAttribute.self], let math = MathImages.text(for: span, size: size) {
                    return Text("\(line)\(math)")
                }
                return Text("\(line)\(Text(AttributedString(piece)))")
            }
        } else {
            Text(text)
        }
    }
}

/// Display math standing as a paragraph of its own: centred, and scrolled
/// sideways when it is wider than the transcript. Shown as written when
/// SwiftMath cannot read it.
struct MathBlockView: View {
    let span: MathSpan
    let source: AttributedString
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let math = MathImages.text(for: span, size: MathImages.pointSize(for: .body, typeSize: typeSize)) {
            ScrollView(.horizontal) {
                math
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        } else {
            Text(source)
                .textSelection(.enabled)
        }
    }
}

/// Typeset math, kept by what it was drawn from, so a reply that streams in
/// or scrolls back into view draws each span once.
enum MathImages {
    private final class Drawn {
        let text: Text?
        init(_ text: Text?) { self.text = text }
    }

    private static let cache: NSCache<NSString, Drawn> = {
        let cache = NSCache<NSString, Drawn>()
        cache.countLimit = 500
        return cache
    }()

    /// `span` drawn at `size` as an image in a line of text, sitting on its
    /// baseline, or nil when SwiftMath cannot read it.
    static func text(for span: MathSpan, size: CGFloat) -> Text? {
        let key = "\(span.isDisplay ? "D" : "T")\(size)|\(span.latex)" as NSString
        if let drawn = cache.object(forKey: key) { return drawn.text }
        let text = draw(span, size: size)
        cache.setObject(Drawn(text), forKey: key)
        return text
    }

    /// Whether SwiftMath can read `span`.
    static func canDraw(_ span: MathSpan) -> Bool {
        text(for: span, size: 17) != nil
    }

    private static func draw(_ span: MathSpan, size: CGFloat) -> Text? {
        var math = MathImage(
            latex: MathMacros.expand(span.latex), fontSize: size, textColor: .black,
            labelMode: span.isDisplay ? .display : .text, textAlignment: .left)
        guard case (nil, _?, let layout?) = math.asImage() else { return nil }
        // `MathImage` centres math shorter than half its font size in that
        // half, which puts its baseline below the image's bottom edge. Room
        // there, as much as it moves down, keeps the baseline where it was
        // and the glyphs in the picture.
        let height = layout.ascent + layout.descent
        if height < size / 2 {
            math.contentInsets.bottom = (size / 2 - height) / 2
        }
        guard case (nil, let image?, _?) = math.asImage() else { return nil }
        #if os(iOS)
            let picture = Image(uiImage: image)
        #elseif os(macOS)
            let picture = Image(nsImage: image)
        #endif
        return Text(picture.renderingMode(.template))
            .baselineOffset(-layout.descent)
            .accessibilityLabel(span.latex)
    }

    /// The point size of `style` at `typeSize`, which math in that text is
    /// drawn at.
    static func pointSize(for style: Font.TextStyle, typeSize: DynamicTypeSize) -> CGFloat {
        #if os(iOS)
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
            return UIFont.preferredFont(forTextStyle: platformStyle(style), compatibleWith: traits).pointSize
        #elseif os(macOS)
            return NSFont.preferredFont(forTextStyle: platformStyle(style)).pointSize
        #endif
    }

    #if os(iOS)
        private static func platformStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
            switch style {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            default: .body
            }
        }
    #elseif os(macOS)
        private static func platformStyle(_ style: Font.TextStyle) -> NSFont.TextStyle {
            switch style {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            default: .body
            }
        }
    #endif
}
