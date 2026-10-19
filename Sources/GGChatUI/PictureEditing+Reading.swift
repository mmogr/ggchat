import Foundation
import GGChatCore

// What the editor's views ask of a picture being fixed or drawn again:
// nothing here changes it.
extension PictureEditing {
    /// The brush's narrowest and widest, by the picture's longer side.
    var brushes: ClosedRange<CGFloat> {
        let long = max(size.width, size.height)
        return max(1, (long * 0.01).rounded())...max(2, (long * 0.25).rounded())
    }

    /// The image models to choose from, where the Mac lists more than one
    /// that can draw, and no menu otherwise.
    var menu: DrawMenu {
        guard (drawing?.models ?? []).count(where: \.complete) > 1 else { return .none }
        return DrawMenu(drawing, chosen: model)
    }

    /// Why the picture cannot be asked for yet, or nil when it can.
    var blocked: String? {
        if words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Say what the picture should show." }
        if mode == .fix, !strokes.marksSomething { return "Brush over the part to fix first." }
        // A Mac with several image models and no default draws for none
        // until one is named, so the editor asks, as the line over the composer's field does.
        if model == nil, drawing?.awaitsImageChoice == true { return "Choose an image model first." }
        return nil
    }

    /// What the button that asks says.
    var askTitle: String {
        mode == .fix ? "Fix this part" : "Draw it again"
    }

    /// Whether leaving would lose something: a render, a drawn picture not
    /// yet kept, or a Keep on its way.
    var holdsWork: Bool {
        switch phase {
        case .drawing, .drawn, .keeping: true
        case .idle, .failed: false
        }
    }

    /// Whether the choices can be changed: nothing is drawn or being drawn.
    var isEditing: Bool {
        switch phase {
        case .idle, .failed: true
        case .drawing, .drawn, .keeping: false
        }
    }

    /// Whether a Keep is on its way.
    var isKeeping: Bool {
        if case .keeping = phase { return true }
        return false
    }

    /// The drawn picture, while one is held.
    var drawn: Data? {
        switch phase {
        case .drawn(let picture), .keeping(let picture): picture
        case .idle, .drawing, .failed: nil
        }
    }

    /// Whether the Mac is drawing now.
    var isDrawing: Bool {
        if case .drawing = phase { return true }
        return false
    }
}
