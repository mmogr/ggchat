import Foundation
import GGChatCore

extension AppModel {
    /// Seeded, in-memory, for previews.
    ///
    /// The pipe connector is the initializer's default, `PipeConnectorFactory`,
    /// and not a `MockPipeConnector` named here: the mock does not exist
    /// outside DEBUG, and `#Preview` bodies are compiled in every
    /// configuration. Previews therefore get the factory's mock — a
    /// `ContinuousClockSleeper` at 900ms rather than the mock's own
    /// `ImmediateSleeper` at 700ms — so the status pill walks idle → relayed →
    /// direct over 1.8 seconds instead of arriving at direct at once. That is
    /// the app's own timing, which is the more useful thing for a preview to
    /// show.
    public static var preview: AppModel {
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(),
            diagnostics: Diagnostics(defaults: UserDefaults(suiteName: "preview")!))
        try? model.addProvider(
            ProviderConfig(name: "Mock", kind: .openAICompatible(baseURL: mockBaseURL), defaultModel: "mock-27b"),
            credentials: [:])
        // modelpipe's normative vector 1, so the seeded pipe carries a ticket
        // that would actually pass the shape check the form applies.
        try? model.addProvider(
            ProviderConfig(name: "Home", kind: .pipe(ticketDigest: "0123456789abcdef")),
            credentials: [
                .ticket: "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na", .token: "preview",
            ])
        let conversation = model.newConversation()
        var seeded = conversation
        seeded.messages = [
            Message(role: .user, content: "What does a ticket look like?", createdAt: seeded.createdAt),
            Message(
                role: .assistant,
                content: "It starts with `pipe` and is followed by base32 with no padding.",
                createdAt: seeded.createdAt),
        ]
        model.update(seeded)
        return model
    }
}
