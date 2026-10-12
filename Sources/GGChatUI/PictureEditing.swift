import CoreGraphics
import Foundation
import GGChatCore
import Observation

/// One picture the drawing tool made, being fixed or drawn again: what the
/// person chose, the render followed from the request to the picture, and
/// the picture then kept in its chat or thrown away.
///
/// Fix draws again only what was brushed, and Redo the whole picture from
/// itself. Nothing joins the chat until Keep. A Keep that fails leaves the
/// drawn picture where it was, with why, and can be pressed again: a
/// picture already stored is not stored twice. An event of a render that
/// was stopped, or that another has replaced, changes nothing. The
/// picture's bytes are held from the moment the editor opens, and the
/// device is kept awake for as long as a render is under way.
@Observable
final class PictureEditing {
    /// What is being done to the picture.
    enum Mode: Equatable {
        case fix
        case redo

        /// How far from the picture each starts: a fix may change its part
        /// a lot, and a redo keeps most of the picture.
        var startStrength: Double {
            self == .fix ? 0.75 : 0.4
        }
    }

    /// Where the redraw is.
    enum Phase: Equatable {
        case idle
        case drawing(RedrawProgress?)
        case drawn(Data)
        case keeping(Data)
        /// The render failed, in the Mac's words.
        case failed(String)
    }

    /// The strength slider's ends and step.
    static let strengths: ClosedRange<Double> = 0.1...1
    static let strengthStep = 0.05

    /// The picture's own size in pixels, read from its bytes when they are
    /// to hand: the mask is made this size.
    let size: CGSize
    /// What the chat's Mac said of drawing, for the image models to choose
    /// from.
    let drawing: Drawing?

    private(set) var phase = Phase.idle
    /// Whether the original is held up in the drawn picture's place. Off
    /// again whenever the redraw moves on.
    var comparing = false
    /// Why the last Keep failed, while the drawn picture it left is shown.
    private(set) var keepFailure: String?
    /// Whether the chat holds the newer picture: the editor then closes.
    private(set) var isKept = false
    private(set) var mode = Mode.fix
    private(set) var strokes: [MaskStroke] = []
    /// What the picture, or the brushed part, should show.
    var words: String
    var strength = Mode.fix.startStrength
    /// The brush's width, in the picture's pixels.
    var brush: CGFloat
    var erasing = false
    /// The image model to draw with, or nil for the Mac's own choice.
    var model: UInt64?

    @ObservationIgnored private let work: PictureWork
    /// The picture's bytes as they were when the editor opened, so a store
    /// that lets them go meanwhile costs nothing.
    @ObservationIgnored private let source: Data?
    /// The drawn picture decoded, once, for as long as it is the one held.
    @ObservationIgnored private var decoded: CGImage?
    /// Which render is waited on: an event of an older one is dropped.
    @ObservationIgnored private var asked = 0
    @ObservationIgnored private var render: Task<Void, Never>?
    /// The drawn picture as its chat's store names it, once stored.
    @ObservationIgnored private var stored: ImageRef?

    /// `chosen` is the image model the chat already draws with. The choice
    /// starts there when the Mac lists it with all its files, and at the
    /// Mac's own otherwise. A Mac that cannot draw without a model named
    /// and lists exactly one with all its files starts at that one, since
    /// there is then no menu to pick it from.
    init(picture: ImageRef, prompt: String, drawing: Drawing?, chosen: UInt64?, work: PictureWork) {
        self.drawing = drawing
        self.work = work
        words = prompt
        source = work.bytes()
        let read = source.flatMap(PictureMask.size(of:))
        size = CGSize(width: read?.width ?? max(picture.width, 1), height: read?.height ?? max(picture.height, 1))
        brush = (max(size.width, size.height) * 0.06).rounded()
        model = chosen.flatMap { drawing?.imageModel($0)?.complete == true ? $0 : nil }
        let able = (drawing?.models ?? []).filter(\.complete)
        if model == nil, drawing?.available == false, able.count == 1 { model = able[0].id }
    }

    /// The drawn picture as a picture, decoded once while it is held.
    var drawnPicture: CGImage? {
        guard let drawn else { return nil }
        if decoded == nil {
            decoded = ImageDownscale.thumbnail(of: drawn, longEdge: Int(max(size.width, size.height)))
        }
        return decoded
    }

    /// Moves the redraw on. The original is no longer held up, a picture
    /// decoded for the phase before is let go, and the device is kept
    /// awake from a render's start to its end, however it ends.
    private func move(to next: Phase) {
        let wasDrawing = isDrawing
        phase = next
        comparing = false
        decoded = nil
        if isDrawing != wasDrawing { work.stayAwake(isDrawing) }
    }

    // MARK: - Choosing

    /// Fix or Redo, each starting at its own strength.
    func choose(_ next: Mode) {
        mode = next
        strength = next.startStrength
    }

    /// The brush goes down at `point`, in the picture's pixels.
    func begin(at point: CGPoint) {
        strokes.append(MaskStroke(points: [point], width: brush, erases: erasing))
    }

    /// The brush moves to `point` without lifting.
    func extend(to point: CGPoint) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1].points.append(point)
    }

    /// Takes the last stroke off.
    func undo() {
        if !strokes.isEmpty { strokes.removeLast() }
    }

    func clear() {
        strokes = []
    }

    // MARK: - Drawing

    /// Draws the picture again as chosen: the brushed part for Fix, all of
    /// it for Redo. Nothing while it cannot be asked for, or a Keep is on
    /// its way. A drawn picture not kept is let go: this is Try again too.
    @discardableResult
    func ask() -> Task<Void, Never>? {
        guard blocked == nil else { return nil }
        if case .keeping = phase { return nil }
        render?.cancel()
        asked += 1
        let mine = asked
        stored = nil
        keepFailure = nil
        move(to: .drawing(nil))
        let (prompt, strength, model, strokes) = (words, strength, model, mode == .fix ? strokes : [])
        let task = Task { [weak self] in
            guard let self else { return }
            await self.draw(
                mine, PictureRedraw(prompt: prompt, image: Data(), strength: strength, model: model), strokes)
        }
        render = task
        return task
    }

    private func draw(_ mine: Int, _ blank: PictureRedraw, _ strokes: [MaskStroke]) async {
        guard let image = source ?? work.bytes() else { return fail(mine, "This device does not have this picture.") }
        var request = blank
        request.image = image
        if !strokes.isEmpty {
            guard let mask = PictureMask.png(of: strokes, width: Int(size.width), height: Int(size.height)) else {
                return fail(mine, "The mask could not be made.")
            }
            request.mask = mask
        }
        for await event in work.render(request) {
            guard asked == mine else { return }
            switch event {
            case .progress(var progress):
                // A report with no frame keeps the last frame shown.
                if progress.frame == nil, case .drawing(let was?) = phase { progress.frame = was.frame }
                move(to: .drawing(progress))
            case .drawn(let picture):
                move(to: .drawn(picture))
                return
            case .failed(let why):
                move(to: .failed(why))
                return
            }
        }
        fail(mine, RedrawEvent.endedWithoutAPicture)
    }

    private func fail(_ mine: Int, _ why: String) {
        if asked == mine { move(to: .failed(why)) }
    }

    /// Stops the render being drawn, and goes back to choosing. The Mac
    /// stops a render nobody reads.
    func stop() {
        guard case .drawing = phase else { return }
        asked += 1
        render?.cancel()
        render = nil
        move(to: .idle)
    }

    /// Throws the drawn picture away and goes back to choosing. Nothing of
    /// it joined the chat.
    func discard() {
        guard case .drawn = phase else { return }
        asked += 1
        stored = nil
        keepFailure = nil
        move(to: .idle)
    }

    /// The editor is gone: a render still going is stopped. A Keep on its
    /// way is left to land.
    func leave() {
        asked += 1
        render?.cancel()
        render = nil
        if isDrawing { move(to: .idle) }
    }

    // MARK: - Keeping

    /// Stores the drawn picture and puts it in the chat after the one it
    /// was made from. A failure of either leaves the picture drawn, with
    /// why, to be kept again; one already stored is only joined then.
    @discardableResult
    func keep() -> Task<Void, Never>? {
        guard case .drawn(let picture) = phase else { return nil }
        move(to: .keeping(picture))
        keepFailure = nil
        return Task { [weak self] in
            guard let self else { return }
            do throws(PictureKeepFailure) {
                let named: ImageRef
                if let stored {
                    named = stored
                } else {
                    named = try await work.store(picture)
                    stored = named
                }
                try await work.join(named, picture)
                move(to: .idle)
                isKept = true
            } catch {
                move(to: .drawn(picture))
                keepFailure = "The picture was drawn but could not be kept: \(error.words)"
            }
        }
    }
}
