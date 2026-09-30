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
    case finished(reason: String?, usage: Usage?)
    case error(ProviderError)
}
