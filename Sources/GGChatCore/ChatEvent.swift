/// What a provider's stream yields. `.finished` and `.error` are terminal.
public enum ChatEvent: Sendable, Equatable {
    case delta(String)
    case reasoning(String)
    /// How much of the prompt has been read, sent before the first word by
    /// gglib when the request asks for it.
    case progress(PromptProgress)
    /// A tool the reply called, as one line: its name and what it was given.
    /// Only a hub's agent run sends one.
    case tool(String)
    /// What one finished model call of a run counted, and why the call ended:
    /// gglib's usage frame on a chat run, its `turn_usage` on an agent run.
    /// A run can send several, and the last is the reply's. The chat route
    /// says both in `.finished` and never sends this.
    case usage(Usage, reason: String?)
    case finished(reason: String?, usage: Usage?)
    case error(ProviderError)
}
