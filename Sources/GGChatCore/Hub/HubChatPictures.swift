import Foundation

// Which of a hub's chat's images its drawing tool made, and from what words:
// what fixing or redoing one starts from. A reply's row names the tools it
// called in its metadata (`tool_calls`), a tool's row the call it answers
// (`tool_call_id`), and a tool's images are on the tool's row.

/// A tool a saved reply called, as its row's metadata names it: the call's
/// id, the tool's name, and of what the model gave it, only `prompt`.
public struct HubToolCall: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// The `prompt` argument, when the arguments have one that is text.
    public let prompt: String?

    public init(id: String, name: String, prompt: String? = nil) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }

    /// The name gglib's drawing tool is called by (`DRAW_TOOL_NAME` there).
    public static let drawingTool = "builtin:generate_image"

    enum CodingKeys: String, CodingKey {
        case id, name, arguments
    }

    private struct Arguments: Codable {
        var prompt: String?
    }

    /// The arguments are read as an object, or as JSON text of one, which
    /// is how an OpenAI history writes them. Any other shape has no prompt.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let given = try? container.decodeIfPresent(Arguments.self, forKey: .arguments) {
            prompt = given.prompt
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .arguments) {
            prompt = (try? JSONDecoder().decode(Arguments.self, from: Data(text.utf8)))?.prompt
        } else {
            prompt = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(Arguments(prompt: prompt), forKey: .arguments)
    }
}

extension HubChatOpen {
    /// What each picture the drawing tool made was drawn from, by the
    /// picture's id: the `prompt` of the call its tool row answers. A
    /// picture kept after a fix or a redo is on its source's row, so it has
    /// its source's words. An image of a question, of another tool, or of a
    /// call with no words to read is in none.
    public var drawnPrompts: [String: String] {
        var words: [String: String] = [:]
        for row in messages where row.role == "assistant" {
            for call in row.metadata?.toolCalls ?? [] where call.name == HubToolCall.drawingTool {
                let prompt = call.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !prompt.isEmpty { words[call.id] = prompt }
            }
        }
        var prompts: [String: String] = [:]
        for row in messages where row.role == "tool" {
            guard let call = row.metadata?.toolCallID, let prompt = words[call] else { continue }
            for image in row.images ?? [] { prompts[image.id] = prompt }
        }
        return prompts
    }
}
