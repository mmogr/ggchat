import CoreGraphics

/// The sums behind a picture opened whole and looked at closer: how far it
/// may be enlarged, where it sits while it is smaller than the sheet, and
/// what a double tap shows. Kept apart from the view so they are tested
/// where there is no touch screen.
nonisolated enum PictureZoom {
    /// The least a picture may always be enlarged to, as a multiple of the
    /// size it is fitted at.
    static let least: CGFloat = 4
    /// How much closer a double tap goes.
    static let doubleTap: CGFloat = 2.5

    /// How far a picture `natural` pixels in size may be enlarged from
    /// `fitted`: until each of its pixels is a point across, and never less
    /// than `least`, so a small picture can still be looked into.
    static func most(of natural: CGSize, fitted: CGSize) -> CGFloat {
        guard fitted.width > 0, fitted.height > 0 else { return least }
        return max(least, natural.width / fitted.width, natural.height / fitted.height)
    }

    /// The space left each side of `content` in `space`, across and down:
    /// what keeps a picture smaller than the sheet in its middle, and
    /// nothing once it is larger.
    static func margins(of content: CGSize, in space: CGSize) -> CGSize {
        CGSize(
            width: max(0, (space.width - content.width) / 2), height: max(0, (space.height - content.height) / 2))
    }

    /// The part of the picture a double tap at `point` fills `space` with:
    /// `doubleTap` times closer, or as close as it goes (`most`) when that
    /// is less, and `point` in its middle.
    static func part(around point: CGPoint, in space: CGSize, most: CGFloat) -> CGRect {
        let scale = max(1, min(doubleTap, most))
        let size = CGSize(width: space.width / scale, height: space.height / scale)
        return CGRect(
            x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
    }
}

#if os(iOS)
    import SwiftUI
    import UIKit

    /// A picture fitted to the space it is given, that a pinch enlarges, a
    /// drag moves about and a double tap brings closer or puts back. A
    /// scroll view and not a gesture of SwiftUI's, for the pinch that stays
    /// under the fingers and the edges that give as Photos' do.
    struct ZoomablePicture: UIViewRepresentable {
        let picture: CGImage

        func makeUIView(context: Context) -> ZoomingPictureView { ZoomingPictureView() }

        func updateUIView(_ view: ZoomingPictureView, context: Context) { view.show(picture) }
    }

    final class ZoomingPictureView: UIScrollView, UIScrollViewDelegate {
        private let pictureView = UIImageView()
        private var natural = CGSize.zero
        /// The size the picture was last fitted to, so it is fitted again
        /// when the sheet changes size and not at each scroll.
        private var fittedTo = CGSize.zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            showsVerticalScrollIndicator = false
            showsHorizontalScrollIndicator = false
            contentInsetAdjustmentBehavior = .never
            addSubview(pictureView)
            let twice = UITapGestureRecognizer(target: self, action: #selector(tappedTwice))
            twice.numberOfTapsRequired = 2
            addGestureRecognizer(twice)
        }

        required init?(coder: NSCoder) { nil }

        /// Shows `picture`, and fits it again only when its size is another:
        /// the sheet reads the same picture afresh each time it is drawn, and
        /// a picture fitted again at each would lose how close it was.
        func show(_ picture: CGImage) {
            pictureView.image = UIImage(cgImage: picture)
            let size = CGSize(width: picture.width, height: picture.height)
            guard size != natural else { return }
            natural = size
            fittedTo = .zero
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != fittedTo { fit() }
            centre()
        }

        private func fit() {
            fittedTo = bounds.size
            zoomScale = 1
            let fitted = PictureCanvas.box(of: natural, in: bounds.size).size
            pictureView.frame = CGRect(origin: .zero, size: fitted)
            contentSize = fitted
            maximumZoomScale = PictureZoom.most(of: natural, fitted: fitted)
        }

        private func centre() {
            let margins = PictureZoom.margins(of: contentSize, in: bounds.size)
            let inset = UIEdgeInsets(
                top: margins.height, left: margins.width, bottom: margins.height, right: margins.width)
            if contentInset != inset { contentInset = inset }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { pictureView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centre() }

        @objc private func tappedTwice(_ tap: UITapGestureRecognizer) {
            guard zoomScale == minimumZoomScale else { return setZoomScale(minimumZoomScale, animated: true) }
            zoom(
                to: PictureZoom.part(around: tap.location(in: pictureView), in: bounds.size, most: maximumZoomScale),
                animated: true)
        }
    }
#endif
