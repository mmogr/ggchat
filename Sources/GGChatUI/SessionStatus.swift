import GGChatCore

/// What the status pill beside a conversation's model says: how the pipe
/// behind it is, or how this device's engine is with the conversation's
/// model. One pill, in the one glass slot the composer keeps for it, serves
/// both. A server by address has no session and no pill.
nonisolated public enum SessionStatus: Sendable, Equatable {
    case pipe(PipeStatus)
    case engine(ModelState)

    /// The conversation's model on this device's engine, as the pill says it.
    /// gglib's engine holds one model at a time, so a model other than the
    /// conversation's being loaded or ready is this one not loaded.
    public enum ModelState: Sendable, Equatable {
        /// The engine is not serving, or holds another model or none.
        case notLoaded
        /// The model is loading; `fraction` runs from 0 to 1.
        case loading(fraction: Double)
        case ready
        /// The engine could not load it. Pressing the pill loads it again.
        case failed
        /// The engine refused it as too big for this device. Pressing the
        /// pill opens the model browser.
        case tooBig
    }

    /// The pill's words.
    public var words: String {
        switch self {
        case .pipe(.idle): "Connecting"
        case .pipe(.direct): "Direct"
        case .pipe(.relayed): "Relayed"
        case .pipe(.closed): "Reconnect"
        case .engine(.notLoaded): "Not loaded"
        case .engine(.loading(let fraction)): "Loading \(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
        case .engine(.ready): "Ready"
        case .engine(.failed): "Load again"
        case .engine(.tooBig): "Too big"
        }
    }

    /// The pill's symbol: an antenna for a pipe, a memory chip for the
    /// engine.
    public var symbol: String {
        switch self {
        case .pipe(.closed): "antenna.radiowaves.left.and.right.slash"
        case .pipe: "antenna.radiowaves.left.and.right"
        case .engine: "memorychip"
        }
    }

    /// What VoiceOver reads: what the pill is about, then its words.
    public var accessibilityLabel: String {
        switch self {
        case .pipe: "Connection \(words)"
        case .engine: "Model \(words)"
        }
    }

    /// What pressing the pill does, for VoiceOver, when it does anything.
    public var accessibilityHint: String {
        switch self {
        case .pipe: "Reconnects"
        case .engine(.failed): "Loads the model again"
        case .engine(.tooBig): "Opens the model browser"
        case .engine: ""
        }
    }

    /// Whether the pill is tinted: only when it is asking to be pressed,
    /// Reconnect and Load again. The others read as status, and those that
    /// are pressable are so without saying it.
    public var asksToBePressed: Bool {
        self == .pipe(.closed) || self == .engine(.failed)
    }

    /// Whether something is under way, which the symbol animates: a pipe
    /// connecting, a model loading.
    public var isUnderWay: Bool {
        switch self {
        case .pipe(.idle), .engine(.loading): true
        case .pipe, .engine: false
        }
    }
}

extension AppModel {
    /// The status of the session behind this conversation, or nil for a
    /// server added by address, for a pipe never dialled, and for This
    /// iPhone in a build that runs no model.
    public func sessionStatus(for conversation: Conversation) -> SessionStatus? {
        guard let config = provider(for: conversation), config.hasSession else { return nil }
        switch config.kind {
        case .pipe: return pipeStatuses[config.id].map(SessionStatus.pipe)
        case .onDevice:
            guard engine.isAvailable else { return nil }
            return .engine(modelState(of: conversation.model ?? config.defaultModel))
        case .openAICompatible: return nil
        }
    }

    /// How the engine is with `modelID`, as the pill says it.
    func modelState(of modelID: String?) -> SessionStatus.ModelState {
        guard let modelID else { return .notLoaded }
        if onDevice.tooBig.contains(modelID) { return .tooBig }
        switch engineStatus {
        case .loading(modelID, let fraction)?: return .loading(fraction: fraction)
        case .ready(modelID, _)?: return .ready
        case .failed(modelID, _)?: return .failed
        default: return .notLoaded
        }
    }

    /// Whether pressing the pill does anything now. Reconnect is offered in
    /// every state but a dial in flight (`canReconnect(_:)`); Load again
    /// while no reply is going through the engine; Too big wherever the
    /// browser can open.
    public func offersPress(on status: SessionStatus, in conversation: Conversation) -> Bool {
        guard let config = provider(for: conversation) else { return false }
        switch status {
        case .pipe: return canReconnect(config.id)
        case .engine(.failed): return liveReplies(through: config.id).isEmpty
        case .engine(.tooBig): return runsModelsHere
        case .engine: return false
        }
    }

    /// Presses the pill: the pipe is dialled again, the model loaded again,
    /// or the browser opened. Returns the work, so a test can wait on it.
    @discardableResult
    public func press(_ status: SessionStatus, in conversation: Conversation) -> Task<Void, Never>? {
        guard offersPress(on: status, in: conversation), let config = provider(for: conversation) else { return nil }
        switch status {
        case .pipe: return Task { await reconnectPipe(for: config) }
        case .engine(.failed): return loadAgain(conversation.id)
        case .engine(.tooBig):
            openModelBrowser()
            return nil
        case .engine: return nil
        }
    }
}
