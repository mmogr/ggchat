import Foundation

/// A tool a reply called, and what the tool answered: what a run's agent
/// events say of it (`tool_call_start`, `tool_call_complete`), kept so a
/// later request can say again how the reply came about. Never drawn.
///
/// `arguments` is what the model gave the tool, as JSON text: an OpenAI
/// history writes a call's arguments as a string. `result` is the tool's
/// answer word for word, and nil until it has answered: a call and its
/// answer are two events of the run, and a reply can be put down between
/// them.
public struct ToolExchange: Codable, Sendable, Equatable, Hashable {
    public var callID: String
    public var name: String
    public var arguments: String
    public var result: String?

    public init(callID: String, name: String, arguments: String, result: String? = nil) {
        self.callID = callID
        self.name = name
        self.arguments = arguments
        self.result = result
    }
}

extension [ToolExchange] {
    /// Takes one event of a run: a call is added, in place of one already
    /// held under its id, and an answer is put on the call it answers. An
    /// answer to a call that is not held, and any other event, change
    /// nothing.
    public mutating func take(_ event: ChatEvent) {
        switch event {
        case .toolCalled(let call): self.merge([call])
        case .toolAnswered(let callID, let text):
            guard let index = lastIndex(where: { $0.callID == callID }) else { return }
            self[index].result = text
        default: break
        }
    }

    /// Adds `later`, each in place of the one held under its call's id when
    /// one is: the later reading of a call knows its answer.
    public mutating func merge(_ later: [ToolExchange]) {
        for exchange in later {
            if let index = lastIndex(where: { $0.callID == exchange.callID }) {
                self[index] = exchange
            } else {
                append(exchange)
            }
        }
    }
}

/// The parts of gglib's `tool_call_start` and `tool_call_complete` that say
/// what was called and what it answered.
enum ToolFrames {
    /// The call a `tool_call_start` names: `tool_call.id`, `.name` and
    /// `.arguments`. Arguments that came as JSON are written as text, keys
    /// sorted; ones that came as text are kept as they came; none is `{}`.
    static func call(in data: Data) -> ToolExchange? {
        guard let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let call = frame["tool_call"] as? [String: Any],
            let id = call["id"] as? String, let name = call["name"] as? String
        else { return nil }
        return ToolExchange(callID: id, name: name, arguments: text(of: call["arguments"]))
    }

    private static func text(of arguments: Any?) -> String {
        if let written = arguments as? String { return written }
        guard let arguments, arguments is [String: Any] || arguments is [Any],
            let data = try? JSONSerialization.data(
                withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension Message {
    /// What a reply's picture was drawn from: the `prompt` of the one call
    /// of gglib's drawing tool the reply holds that drew, which is one
    /// answered "Drew …", as gglib reads it. Nil for a reply that holds no
    /// such call, or several: which call made which picture is not kept, so
    /// with several a picture's own words are not known.
    public var drawnPrompt: String? {
        let drew = exchanges.filter { $0.name == HubToolCall.drawingTool && $0.result?.hasPrefix("Drew ") == true }
        guard drew.count == 1,
            let given = try? JSONSerialization.jsonObject(with: Data(drew[0].arguments.utf8)) as? [String: Any],
            let prompt = (given["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !prompt.isEmpty
        else { return nil }
        return prompt
    }
}
