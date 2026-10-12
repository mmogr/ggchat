import CoreGraphics
import Foundation

// A picture drawn again from itself: gglib's `POST /v1/images/generations`
// sent the picture, a strength, and a mask when only a part is to change.
// What a person brushed, the request's body, and what the stream it answers
// says. Written by hand to mirror gglib's ADR 0018, decisions 20 and 21.

/// One pass of the brush over a picture: where it went, how wide it was, and
/// whether it painted or rubbed out. In the picture's own pixels from its top
/// left, so the same strokes paint what a person sees and the mask the Mac is
/// sent, and undo is a stroke taken off the end.
public struct MaskStroke: Sendable, Equatable {
    public var points: [CGPoint]
    /// The brush's width, in the picture's pixels.
    public var width: CGFloat
    /// A stroke that takes paint off, where one before it put it on.
    public var erases: Bool

    public init(points: [CGPoint], width: CGFloat, erases: Bool = false) {
        self.points = points
        self.width = width
        self.erases = erases
    }

    /// Where on the picture a pointer is, in the picture's pixels: `place`
    /// is the pointer's, `box` the picture's on screen, both in one space,
    /// and `natural` the picture's own size. Held inside the picture, and
    /// its top left for a box with no size.
    public static func point(at place: CGPoint, in box: CGRect, of natural: CGSize) -> CGPoint {
        func along(_ at: CGFloat, _ start: CGFloat, _ shown: CGFloat, _ real: CGFloat) -> CGFloat {
            shown > 0 ? min(real, max(0, (at - start) / shown * real)) : 0
        }
        return CGPoint(
            x: along(place.x, box.minX, box.width, natural.width),
            y: along(place.y, box.minY, box.height, natural.height))
    }
}

extension [MaskStroke] {
    /// Whether any of them paints. Paint a later stroke rubbed out entirely
    /// still counts here; the Mac refuses a mask with no white in it.
    public var marksSomething: Bool {
        contains { !$0.erases && !$0.points.isEmpty }
    }
}

/// A picture to draw again: what `images/generations` reads of one.
public struct PictureRedraw: Sendable, Equatable, Encodable {
    /// What the picture, or the part under the mask, should show.
    public var prompt: String
    /// The picture's own bytes, a PNG.
    public var image: Data
    /// A PNG the picture's size, white over what to draw again; nil to draw
    /// all of it again.
    public var mask: Data?
    /// How far from the picture the result may go, from 0.05 to 1.
    public var strength: Double
    /// The image model to draw with, by its id on the hub; nil for the
    /// hub's own choice.
    public var model: UInt64?

    public init(prompt: String, image: Data, mask: Data? = nil, strength: Double, model: UInt64? = nil) {
        self.prompt = prompt
        self.image = image
        self.mask = mask
        self.strength = strength
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case prompt, image, mask, strength, model, stream
    }

    /// The body: the prompt without the space around it, the picture and
    /// the mask as base64, the strength to two places, the model's id as
    /// text, and `stream`. No `mask` key without a mask, and no `model` key
    /// without a choice.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prompt.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .prompt)
        try container.encode(image.base64EncodedString(), forKey: .image)
        try container.encodeIfPresent(mask?.base64EncodedString(), forKey: .mask)
        try container.encode((strength * 100).rounded() / 100, forKey: .strength)
        try container.encodeIfPresent(model.map { String($0) }, forKey: .model)
        try container.encode(true, forKey: .stream)
    }
}

/// Where a redraw has got to, as its stream last said.
public struct RedrawProgress: Sendable, Equatable {
    /// `queued`, `loading`, `sampling`, `decoding` or `finishing`.
    public var stage: String
    /// The step finished, while sampling.
    public var step: Int?
    /// The steps the pass takes, while sampling.
    public var total: Int?
    /// The place in line, while queued.
    public var position: Int?
    /// The step's look at the picture, a small PNG. It is the Mac's own
    /// frame: for a masked redraw, not yet laid over the picture.
    public var frame: Data?

    public init(stage: String, step: Int? = nil, total: Int? = nil, position: Int? = nil, frame: Data? = nil) {
        self.stage = stage
        self.step = step
        self.total = total
        self.position = position
        self.frame = frame
    }

    /// Where a render has got to, in words, with `locale`'s digits. Before
    /// the first word, and at any stage this build does not know, it is
    /// loading.
    public static func line(for progress: RedrawProgress?, in locale: Locale) -> String {
        func digits(_ number: Int) -> String { number.formatted(.number.locale(locale)) }
        switch progress?.stage {
        case "queued":
            guard let position = progress?.position, position > 0 else { return "Waiting for the GPU\u{2026}" }
            return "Waiting for the GPU, place \(digits(position)) in line\u{2026}"
        case "sampling":
            guard let step = progress?.step, let total = progress?.total, step > 0, total > 0 else {
                return "Drawing\u{2026}"
            }
            return "Drawing, step \(digits(step)) of \(digits(total))\u{2026}"
        case "decoding", "finishing":
            return "Finishing the picture\u{2026}"
        default:
            return "Loading the image model\u{2026}"
        }
    }
}

/// What a redraw's stream says. `.drawn` and `.failed` end it.
public enum RedrawEvent: Sendable, Equatable {
    case progress(RedrawProgress)
    /// The picture drawn, a PNG.
    case drawn(Data)
    /// Why nothing was drawn, in the Mac's words.
    case failed(String)

    /// What a stream that ends with no picture and no error is said as.
    public static let endedWithoutAPicture = "The render ended without a picture."
    static let unreadablePicture = "The picture that came back could not be read."
    static let noReason = "The picture could not be drawn."

    /// What one event of the stream means: its progress, the picture, or
    /// the failure, and nil for one that means nothing here, such as
    /// `image_generation.partial_image` or progress with no stage.
    init?(_ event: SSEEvent) {
        let data = Data(event.data.utf8)
        switch event.event {
        case "image_generation.progress":
            guard let said = try? JSONDecoder().decode(ProgressFrame.self, from: data), let stage = said.stage
            else { return nil }
            self = .progress(
                RedrawProgress(
                    stage: stage, step: said.step, total: said.total, position: said.position,
                    frame: said.frame.flatMap { Data(base64Encoded: $0) }))
        case "image_generation.completed":
            let png = (try? JSONDecoder().decode(CompletedFrame.self, from: data))?.picture
            self = png.flatMap { Data(base64Encoded: $0) }.map(RedrawEvent.drawn) ?? .failed(Self.unreadablePicture)
        case "error":
            let said = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error.message
            self = .failed(said ?? Self.noReason)
        default:
            return nil
        }
    }

    private struct ProgressFrame: Decodable {
        var stage: String?
        var step: Int?
        var total: Int?
        var position: Int?
        var frame: String?

        enum CodingKeys: String, CodingKey {
            case stage, step, total, position
            case frame = "frame_b64"
        }
    }

    private struct CompletedFrame: Decodable {
        var picture: String?

        enum CodingKeys: String, CodingKey {
            case picture = "b64_json"
        }
    }
}

/// A provider whose hub draws a picture again from itself.
public protocol PictureProvider: Provider {
    /// Draws `redraw`'s picture again and says how the render goes, ending
    /// with the picture or with why there is none. Never throws. Cancelling
    /// the consuming task ends the stream with no last event, and the hub
    /// stops a render nobody reads.
    func redraw(_ redraw: PictureRedraw) -> AsyncStream<RedrawEvent>
}

/// What `POST chats/{id}/pictures` is sent: the picture a newer one was made
/// from and the newer one, both by their ids in the hub's store.
public struct KeptPicture: Sendable, Equatable, Encodable {
    public var from: String
    public var image: String

    public init(from: String, image: String) {
        self.from = from
        self.image = image
    }
}
