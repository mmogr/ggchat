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
    /// The images a tool the reply called made, in the order it made them,
    /// by reference: the bytes are the hub's, read by id when drawn. Only a
    /// hub's agent run sends one.
    case images([ImageRef])
    /// How far a tool the reply called has got, while it works. Only a
    /// hub's agent run sends one, and nothing of it is kept.
    case toolProgress(ToolProgress)
    /// A tool the reply called has finished, well or badly, named by its
    /// call's id: what was shown of its progress is dropped. Sent ahead of
    /// the images it made, when it made any.
    case toolEnded(String)
    /// The reply cannot go on until something else finishes. Only a hub's
    /// agent run sends one.
    case waiting(RunWait)
    /// What one finished model call of a run counted, and why the call ended:
    /// gglib's usage frame on a chat run, its `turn_usage` on an agent run.
    /// A run can send several, and the last is the reply's. The chat route
    /// says both in `.finished` and never sends this.
    case usage(Usage, reason: String?)
    case finished(reason: String?, usage: Usage?)
    case error(ProviderError)
}
