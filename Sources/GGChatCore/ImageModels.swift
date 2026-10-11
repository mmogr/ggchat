// The image models a hub can draw with, as its answer about drawing lists
// them, and what is wrong with a choice among them.
//
// Written by hand to mirror gglib's `ImageModelRow`. gglib has recorded no
// answer with the list yet, so `contract-images-drawing-models.json` is
// written from the contract's own example and read by `ImageModelWireTests`.

/// One image model on a hub, as `GET /v1/images/drawing` lists it. The id
/// is that machine's own catalogue id and names nothing on another.
public struct ImageModelRow: Decodable, Sendable, Equatable, Identifiable {
    public let id: UInt64
    public let name: String
    /// The family as gglib wrote it: `flux1`, `sdxl`, `qwen-image-2.1`, or
    /// one this build has not heard of, kept as it came.
    public let family: String
    /// Whether it has every file it needs to draw.
    public let complete: Bool
    /// The roles of the files it lacks, as gglib wrote them: `vae`,
    /// `clip_l`, `t5xxl`, `llm`, or one this build has not heard of.
    public let missing: [String]
    /// Whether a message that names no image model is drawn with this one.
    public let isDefault: Bool
    /// Whether it is loaded now.
    public let resident: Bool

    public init(
        id: UInt64, name: String, family: String, complete: Bool = true, missing: [String] = [],
        isDefault: Bool = false, resident: Bool = false
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.complete = complete
        self.missing = missing
        self.isDefault = isDefault
        self.resident = resident
    }

    enum CodingKeys: String, CodingKey {
        case id, name, family, complete, missing, resident
        case isDefault = "default"
    }

    /// Only the id, the name and whether it is complete must be there. A
    /// family or a role is any string, so one gglib adds later reads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UInt64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        family = try container.decodeIfPresent(String.self, forKey: .family) ?? ""
        complete = try container.decode(Bool.self, forKey: .complete)
        missing = try container.decodeIfPresent([String].self, forKey: .missing) ?? []
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        resident = try container.decodeIfPresent(Bool.self, forKey: .resident) ?? false
    }

    /// The family as a person reads it, in gglib's words for the three it
    /// has (`ImageFamily::label`), and the raw string for any other.
    public var familyLabel: String {
        switch family {
        case "flux1": "Flux.1"
        case "sdxl": "SDXL"
        case "qwen-image-2.1": "Qwen-Image 2.1"
        default: family
        }
    }

    /// The files it lacks as a person reads them, in gglib's words for the
    /// four roles it has, and the raw string for any other.
    public var missingLabels: [String] {
        missing.map { role in
            switch role {
            case "vae": "VAE"
            case "clip_l": "CLIP-L"
            case "t5xxl": "T5-XXL"
            case "llm": "LLM"
            default: role
            }
        }
    }
}

/// What is wrong with an image model a chat chose, as the hub's list has it
/// now. gglib refuses a message that names such a model and never draws it
/// with another, so neither does this app pick another for it.
public enum ImageChoiceFault: Sendable, Equatable {
    /// The list no longer has it: `model_not_found` there.
    case gone
    /// The list has it without all its files: `image_model_incomplete`.
    case incomplete(ImageModelRow)
}

extension Drawing {
    /// Whether the hub's gglib takes `image_model` with a message that
    /// draws: its answer carried `models`, empty or not. One from before
    /// the list refuses a turn with a key it does not know, so it is never
    /// sent one.
    public var takesImageModel: Bool {
        models != nil
    }

    /// The model a message that names none is drawn with, when the list
    /// marks one.
    public var defaultImageModel: ImageModelRow? {
        models?.first(where: \.isDefault)
    }

    /// The row a chosen id names, or nil when the list has none such.
    public func imageModel(_ id: UInt64) -> ImageModelRow? {
        models?.first { $0.id == id }
    }

    /// What is wrong with a chosen id, or nil when the list has it complete
    /// or the hub sent no list to judge it by.
    public func fault(ofChoice id: UInt64) -> ImageChoiceFault? {
        guard models != nil else { return nil }
        guard let row = imageModel(id) else { return .gone }
        return row.complete ? nil : .incomplete(row)
    }
}
