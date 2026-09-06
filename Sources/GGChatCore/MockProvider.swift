import Foundation

/// Streams canned replies with timing. Previews and tests use it; the mock
/// pipe session points at one. It takes a `Sleeper`, so a test runs it in
/// microseconds and a preview at a readable pace.
public struct MockProvider: Provider {
    public struct Script: Sendable, Equatable {
        public var reasoning: String?
        public var text: String

        public init(reasoning: String? = nil, text: String) {
            self.reasoning = reasoning
            self.text = text
        }
    }

    public var modelList: [ModelInfo]
    public var scripts: [Script]
    public var sleeper: any Sleeper
    public var tokenDelay: Duration
    /// When set, the stream drops with a transport error after this many
    /// content tokens, to exercise the partial-reply path.
    public var failAfterTokens: Int?

    public init(
        models: [ModelInfo] = MockProvider.sampleModels,
        scripts: [Script] = [MockProvider.sampleScript],
        sleeper: any Sleeper = ImmediateSleeper(),
        tokenDelay: Duration = .milliseconds(30),
        failAfterTokens: Int? = nil
    ) {
        self.modelList = models
        self.scripts = scripts
        self.sleeper = sleeper
        self.tokenDelay = tokenDelay
        self.failAfterTokens = failAfterTokens
    }

    public func models() async throws -> [ModelInfo] {
        modelList
    }

    public func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        let script =
            scripts.isEmpty
            ? Self.sampleScript
            : scripts[request.messages.count % scripts.count]
        return AsyncStream { continuation in
            let task = Task {
                do {
                    if let reasoning = script.reasoning {
                        for token in Self.tokens(of: reasoning) {
                            try await sleeper.sleep(for: tokenDelay)
                            continuation.yield(.reasoning(token))
                        }
                    }
                    for (index, token) in Self.tokens(of: script.text).enumerated() {
                        if let limit = failAfterTokens, index >= limit {
                            continuation.yield(.error(.transport("the mock connection dropped")))
                            continuation.finish()
                            return
                        }
                        try await sleeper.sleep(for: tokenDelay)
                        continuation.yield(.delta(token))
                    }
                    let words = script.text.split(separator: " ").count
                    continuation.yield(.finished(reason: "stop", usage: Usage(completionTokens: words)))
                } catch {
                    // Cancelled: end without a terminal event, like the real provider.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Word-sized pieces with their trailing whitespace attached, so joining
    /// them reproduces the text exactly.
    public static func tokens(of text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == " " || character == "\n" {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    public static let sampleModels: [ModelInfo] = [
        ModelInfo(id: "mock-27b", ownedBy: "ggchat", description: "a canned model", contextWindow: 131_072),
        ModelInfo(id: "mock-4b", ownedBy: "ggchat", description: "a smaller canned model", contextWindow: 32_768),
    ]

    public static let sampleScript = Script(
        reasoning: "The user wants a short answer with a code sample. Keep it to one paragraph and one block.",
        text: """
            Here is a **small** example. It reads a file and finds its longest line:

            ```swift
            let text = try String(contentsOfFile: "notes.txt", encoding: .utf8)
            let lines = text.split(separator: "\\n")
            let longest = lines.max { $0.count < $1.count }
            ```

            That is all there is to it.
            """
    )
}
