import Foundation

// What a run says while a tool of its reply works, and while the reply
// waits for something else to finish: gglib's `tool_progress` and `waiting`
// agent events (`gglib-core/src/domain/agent/events.rs`), which a render that
// takes minutes sends so a person sees it moving, and the preview frame that
// travels beside them. The frames gglib records in
// `contracts/runs/tool_progress.json` are replayed against these types by
// `ToolProgressWireTests`.

/// How far a tool the reply called has got. A count the tool did not report
/// is absent, and reads as nil.
public struct ToolProgress: Decodable, Sendable, Equatable {
    /// Where the tool is in its work.
    public enum Stage: String, Decodable, Sendable, Equatable {
        /// Waiting in line behind other work.
        case queued
        /// Loading what it needs, an image model, before the first step.
        case loading
        /// Stepping through its work: `pass`, `done` and `total` say where.
        case sampling
        /// The last step is done, and the result is being made.
        case decoding
        /// Storing and returning what it made.
        case finishing
    }

    /// The call this reports on.
    public var callID: String
    public var stage: Stage
    /// Which pass is running, from 1: one per picture.
    public var pass: Int?
    /// Steps done in this pass, and how many it takes.
    public var done: Int?
    public var total: Int?
    /// Place in line while queued, 1 being next.
    public var position: Int?

    public init(
        callID: String, stage: Stage, pass: Int? = nil, done: Int? = nil, total: Int? = nil, position: Int? = nil
    ) {
        self.callID = callID
        self.stage = stage
        self.pass = pass
        self.done = done
        self.total = total
        self.position = position
    }

    enum CodingKeys: String, CodingKey {
        case callID = "tool_call_id"
        case stage, pass, done, total, position
    }
}

/// Why a reply cannot go on yet: something else has the machine. gglib
/// sends it again whenever what it reports changes.
public struct RunWait: Decodable, Sendable, Equatable {
    public enum Reason: String, Decodable, Sendable, Equatable {
        /// A picture is being drawn, and one thing is made at a time.
        case imageRender = "image_render"
        /// The model is loading.
        case modelLoad = "model_load"
    }

    public var reason: Reason
    /// The step the work in the way last reported, and how many it takes;
    /// 0 for either is unknown.
    public var step: Int
    public var total: Int
    /// This wait's place in line, 1 being next; 0 when not in a line.
    public var position: Int

    public init(reason: Reason, step: Int = 0, total: Int = 0, position: Int = 0) {
        self.reason = reason
        self.step = step
        self.total = total
        self.position = position
    }
}

/// The latest look at a picture being drawn: gglib's `preview` event, a
/// small PNG of about 128 pixels that sharpens step by step. It travels
/// beside a run's numbered events and is not one of them: gglib never logs
/// it, a reader that connects late is sent only the current one, and this
/// device shows the latest and keeps none.
public struct PreviewFrame: Decodable, Sendable, Equatable {
    /// The call the picture belongs to.
    public var callID: String
    /// The frame's type, `image/png`.
    public var mime: String
    /// The step the frame shows, and how many the pass takes.
    public var step: Int
    public var total: Int
    /// The frame's bytes.
    public var data: Data

    public init(callID: String, mime: String = ImageRef.png, step: Int, total: Int, data: Data) {
        self.callID = callID
        self.mime = mime
        self.step = step
        self.total = total
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "tool_call_id"
        case frame
    }

    private enum FrameKeys: String, CodingKey {
        case mime, step, total, b64
    }

    /// `{tool_call_id, frame: {mime, step, total, b64}}`. A frame whose
    /// bytes are not base64 does not read, and is passed over.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callID = try container.decode(String.self, forKey: .callID)
        let frame = try container.nestedContainer(keyedBy: FrameKeys.self, forKey: .frame)
        mime = try frame.decode(String.self, forKey: .mime)
        step = try frame.decode(Int.self, forKey: .step)
        total = try frame.decode(Int.self, forKey: .total)
        guard let bytes = Data(base64Encoded: try frame.decode(String.self, forKey: .b64)) else {
            throw DecodingError.dataCorruptedError(forKey: .b64, in: frame, debugDescription: "not base64")
        }
        data = bytes
    }
}
