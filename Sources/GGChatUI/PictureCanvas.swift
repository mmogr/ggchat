import CoreGraphics
import GGChatCore
import SwiftUI

/// The picture in the editor, fitted to the space it has, with what lies
/// over it: the latest look at a render, and while a part is being chosen,
/// what was brushed, in a tint the picture shows through. A finger, a
/// pointer or a Pencil dragged over it is the brush.
///
/// The picture, the strokes and the brush are all placed by one box
/// (`box`), so a stroke lands on the mask where it was seen to land.
struct PictureCanvas: View {
    /// The picture shown: the original, or the one drawn again.
    let picture: CGImage?
    /// The latest look at the render, laid over the picture.
    let look: CGImage?
    /// The picture's own size in pixels, which the strokes are in.
    let natural: CGSize
    /// What was brushed, or none when nothing is being chosen.
    let strokes: [MaskStroke]
    /// Whether a drag brushes.
    let brushes: Bool
    let begin: (CGPoint) -> Void
    let extend: (CGPoint) -> Void
    /// Whether a stroke is under way, and whether a touch is down. The
    /// second goes back to false by itself when a drag is cancelled, which
    /// tells no one, and takes the first with it: the next touch then
    /// starts a stroke of its own.
    @State private var painting = false
    @GestureState private var touching = false

    var body: some View {
        GeometryReader { space in
            let box = Self.box(of: natural, in: space.size)
            Canvas { context, _ in
                if let picture { context.draw(Image(decorative: picture, scale: 1), in: box) }
                if let look {
                    context.draw(Image(decorative: look, scale: 1).interpolation(.high), in: box)
                }
                Self.paint(strokes, over: box, of: natural, in: &context)
            }
            // Ahead of the editor's own scrolling, so a stroke up or down the
            // picture paints and does not scroll.
            .highPriorityGesture(brush(in: box), isEnabled: brushes)
            .onChange(of: touching) { _, down in
                if !down { painting = false }
            }
        }
        .aspectRatio(natural.width / max(natural.height, 1), contentMode: .fit)
    }

    private func brush(in box: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, down, _ in down = true }
            .onChanged { drag in
                let point = MaskStroke.point(at: drag.location, in: box, of: natural)
                if painting {
                    extend(point)
                } else {
                    painting = true
                    begin(point)
                }
            }
            .onEnded { _ in painting = false }
    }

    /// Where a picture `natural` in size is drawn in `space`: as large as
    /// fits, in the middle, its shape kept.
    nonisolated static func box(of natural: CGSize, in space: CGSize) -> CGRect {
        guard natural.width > 0, natural.height > 0, space.width > 0, space.height > 0 else { return .zero }
        let scale = min(space.width / natural.width, space.height / natural.height)
        let size = CGSize(width: natural.width * scale, height: natural.height * scale)
        return CGRect(
            x: (space.width - size.width) / 2, y: (space.height - size.height) / 2, width: size.width,
            height: size.height)
    }

    /// How much of the tint's own colour shows over the picture.
    static let tintShare = 0.5

    /// The strokes as a person sees them: each in one solid tint, one that
    /// rubs out taking the tint off again, and the whole laid over the
    /// picture part clear, so strokes that cross do not darken.
    static func paint(_ strokes: [MaskStroke], over box: CGRect, of natural: CGSize, in context: inout GraphicsContext)
    {
        guard !strokes.isEmpty, natural.width > 0 else { return }
        let scale = box.width / natural.width
        var tinted = context
        tinted.opacity = tintShare
        tinted.drawLayer { layer in
            for stroke in strokes {
                layer.blendMode = stroke.erases ? .destinationOut : .normal
                let width = stroke.width * scale
                let points = stroke.points.map { CGPoint(x: box.minX + $0.x * scale, y: box.minY + $0.y * scale) }
                guard let first = points.first else { continue }
                if points.count == 1 {
                    let dot = CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width)
                    layer.fill(Path(ellipseIn: dot), with: .color(.red))
                } else {
                    var path = Path()
                    path.addLines(points)
                    layer.stroke(
                        path, with: .color(.red),
                        style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
