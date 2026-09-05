/// What a provider's stream yields. `.finished` and `.error` are terminal.
public enum ChatEvent: Sendable, Equatable {
    case delta(String)
    case reasoning(String)
    case finished(reason: String?, usage: Usage?)
    case error(ProviderError)
}
