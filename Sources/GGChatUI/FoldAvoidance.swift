import SwiftUI

/// The fold of a book-style iPhone, as SwiftUI reports it: a division region
/// that is active while the phone is half open and absent while it is flat.
/// Nothing here moves scrolling content. A transcript runs across the fold,
/// as Apple asks of feeds and documents, and only a control near it moves.
enum Fold {
    /// The active division regions in `proxy`'s own space, mirrored for a
    /// right-to-left language. None before iOS 27.1, and none on a Mac.
    nonisolated static func divisions(in proxy: GeometryProxy) -> [CGRect] {
        #if os(iOS) && compiler(>=6.4)
            if #available(iOS 27.1, *) {
                return proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
            }
        #endif
        return []
    }

    #if os(iOS)
        /// Whether the app was launched with `-ggchat-fold YES`, which the
        /// walk of a Duo's pages passes: no simulator can be half opened by
        /// a test.
        nonisolated static var isFaked: Bool {
            UserDefaults.standard.bool(forKey: "ggchat-fold")
        }

        /// The divisions the window's layout reads, which under `isFaked`
        /// are a fold down the middle of `proxy`. Only the window's: a
        /// control kept off the fold reads `divisions(in:)`, and moves for a
        /// real one alone.
        nonisolated static func windowDivisions(in proxy: GeometryProxy) -> [CGRect] {
            guard isFaked else { return divisions(in: proxy) }
            let size = proxy.size
            return [CGRect(x: (size.width / 2).rounded() - 12, y: 0, width: 24, height: size.height)]
        }
    #endif

    /// The narrowest pane a column is moved into. Beyond a fold nearer the
    /// trailing edge than this the column stays where it was, across the
    /// fold, which still works.
    nonisolated static let narrowest: CGFloat = 320

    /// How far in from the leading edge a column centred in `size` and at
    /// most `column` wide must start to clear a vertical fold it would cross:
    /// the fold's trailing edge, or zero when there is no such fold, the
    /// column misses it, or the pane beyond it is narrower than `narrowest`.
    /// A region wider than it is tall is a horizontal fold, the propped pose,
    /// and asks nothing of a column.
    nonisolated static func leadingClearance(
        column: CGFloat, in size: CGSize, avoiding folds: [CGRect]
    )
        -> CGFloat
    {
        let width = size.width
        guard let fold = folds.first(where: { $0.height > $0.width }) else { return 0 }
        let fitted = min(column, width)
        let start = (width - fitted) / 2
        guard fold.minX < start + fitted, fold.maxX > start else { return 0 }
        guard width - fold.maxX >= narrowest else { return 0 }
        return fold.maxX
    }
}

extension View {
    /// A column centred in its row and at most `maxWidth` wide, moved to the
    /// trailing side of a vertical fold it would otherwise cross. Where there
    /// is no fold this is `.frame(maxWidth:)` under `.frame(maxWidth: .infinity)`.
    func keptOffTheFold(maxWidth: CGFloat) -> some View {
        modifier(KeptOffTheFold(maxWidth: maxWidth))
    }
}

/// The fold is read from the padded view, which is always the whole row, so
/// the padding it sets never changes what it measures.
private struct KeptOffTheFold: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let maxWidth: CGFloat
    @State private var clearance: CGFloat = 0

    func body(content: Content) -> some View {
        let column = maxWidth
        content
            .frame(maxWidth: column)
            .frame(maxWidth: .infinity)
            .padding(.leading, clearance)
            .animation(reduceMotion ? nil : .snappy, value: clearance)
            .onGeometryChange(for: CGFloat.self) { proxy in
                Fold.leadingClearance(column: column, in: proxy.size, avoiding: Fold.divisions(in: proxy))
            } action: {
                clearance = $0
            }
    }
}
