import GGChatCore

/// Yields one token and then never finishes, so a reply can be caught
/// mid-flight without any of it depending on a clock.
///
/// `MockProvider` always reaches a terminal event, and `finish(_:finished:)`
/// clears `liveReply` when it does — so a test that wants a close to land
/// while a reply is genuinely still streaming cannot use it. Every test that
/// asks "was a reply in flight when this happened?" holds the reply open with
/// this and cancels it afterwards.
struct HangingProvider: Provider {
    func models() async throws -> [ModelInfo] {
        MockProvider.sampleModels
    }

    func stream(_ request: ChatRequest) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            continuation.yield(.delta("half "))
        }
    }
}
