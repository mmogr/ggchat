import GGChatCore
import GGLib

// gglib's library records said in the app's own types, field for field and
// case for case. The two modules name most of these types alike, so each is
// spelled with its module. Every switch is exhaustive with no default arm: a
// gglib release that adds a case or a field fails to build here, in one
// place, rather than being read as something it is not.

extension GGLib.DeviceReading {
    /// The reading the app took, as gglib takes it.
    init(_ reading: GGChatCore.DeviceReading) {
        self.init(
            physicalBytes: reading.physicalBytes, availableBytes: reading.availableBytes,
            isSimulator: reading.isSimulator)
    }
}

extension GGChatCore.FitVerdict {
    init(_ verdict: GGLib.FitVerdict) {
        switch verdict {
        case .fits(let ctx): self = .fits(ctx: ctx)
        case .tight(let ctx): self = .tight(ctx: ctx)
        case .tooBig(let needBytes, let haveBytes): self = .tooBig(needBytes: needBytes, haveBytes: haveBytes)
        case .unknown(let missing, let cutOff):
            self = .unknown(missing: GGChatCore.MissingInput(missing), cutOff: cutOff)
        }
    }
}

extension GGChatCore.MissingInput {
    init(_ missing: GGLib.MissingInput) {
        switch missing {
        case .trainedContext: self = .trainedContext
        case .kvShape: self = .kvShape
        case .weights: self = .weights
        case .budget: self = .budget
        }
    }
}

extension GGChatCore.FitWhy {
    init(_ why: GGLib.FitWhy) {
        self.init(
            weightsBytes: why.weightsBytes, kvBytesPerToken: why.kvBytesPerToken, budgetBytes: why.budgetBytes,
            trainedCtx: why.trainedCtx)
    }
}

extension GGChatCore.Suggestion {
    init(_ suggestion: GGLib.Suggestion) {
        self.init(
            repo: suggestion.repo, quantization: suggestion.quantization, bytes: suggestion.bytes,
            verdict: GGChatCore.FitVerdict(suggestion.verdict), why: GGChatCore.FitWhy(suggestion.why),
            rationale: suggestion.rationale)
    }
}

extension GGChatCore.SearchHit {
    init(_ hit: GGLib.SearchHit) {
        self.init(
            repo: hit.repo, likes: hit.likes, downloads: hit.downloads, parametersB: hit.parametersB,
            trainedCtx: hit.trainedCtx)
    }
}

extension GGChatCore.SearchPage {
    init(_ page: GGLib.SearchPage) {
        self.init(hits: page.hits.map(GGChatCore.SearchHit.init), nextCursor: page.nextCursor)
    }
}

extension GGChatCore.QuantOffer {
    init(_ offer: GGLib.QuantOffer) {
        self.init(
            name: offer.name, totalBytes: offer.totalBytes, shardCount: offer.shardCount,
            verdict: GGChatCore.FitVerdict(offer.verdict), why: GGChatCore.FitWhy(offer.why))
    }
}

extension GGChatCore.InstalledModel {
    init(_ model: GGLib.InstalledModel) {
        self.init(
            id: model.id, name: model.name, bytes: model.bytes, trainedCtx: model.trainedCtx,
            capabilities: model.capabilities, verdict: GGChatCore.FitVerdict(model.verdict))
    }
}

extension GGChatCore.DownloadProgress {
    init(_ progress: GGLib.DownloadProgress) {
        self.init(
            id: progress.id, bytes: progress.bytes, total: progress.total,
            state: GGChatCore.DownloadState(progress.state))
    }
}

extension GGChatCore.DownloadState {
    init(_ state: GGLib.DownloadState) {
        switch state {
        case .queued: self = .queued
        case .running: self = .running
        case .paused: self = .paused
        case .verifying: self = .verifying
        case .done: self = .done
        case .failed(let reason): self = .failed(reason: reason)
        }
    }
}

extension OnDeviceError {
    /// gglib's error, case for case.
    init(_ error: GglibError) {
        switch error {
        case .AuthRequired: self = .authRequired
        case .NotFound: self = .notFound
        case .RateLimited: self = .rateLimited
        case .NoSpace: self = .noSpace
        case .Network(let message): self = .network(message: message)
        case .DoesNotFit(let need, let have): self = .doesNotFit(need: need, have: have)
        case .EngineUnavailable: self = .engineUnavailable
        case .Internal(let message): self = .internal(message: message)
        }
    }

    /// Whatever a call into the library threw, as the app says it: gglib's
    /// own error case for case, one of the app's own as it was, and anything
    /// else, which only uniffi's machinery throws, in its own words.
    init(thrown error: any Error) {
        switch error {
        case let error as GglibError: self.init(error)
        case let error as OnDeviceError: self = error
        default: self = .internal(message: String(describing: error))
        }
    }
}
