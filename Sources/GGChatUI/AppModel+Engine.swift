import Foundation
import GGChatCore

// The engine on this device: the one provider that runs on it, serving it
// when a conversation on that provider opens or a send waits for it, the
// provider a request goes through, and taking it down. `AppModel.swift` keeps
// the state these work on. A session is put down on the way to the
// background, on a memory warning and when its provider is removed (ADR
// 0015); see `AppModel+Engine+Lifecycle`.
extension AppModel {
    /// What the provider for this device's engine is called when it is
    /// added.
    static let thisIPhone = "This iPhone"

    /// Adds the provider for this device's engine, unless one is there: a
    /// device has one engine, so it has one such provider. Returns the
    /// provider, found or added.
    @discardableResult
    func addThisIPhone(defaultModel: String?) throws -> ProviderConfig {
        if let found = providers.first(where: { $0.kind == .onDevice }) { return found }
        let config = ProviderConfig(name: Self.thisIPhone, kind: .onDevice, defaultModel: defaultModel)
        try addProvider(config, credentials: [:])
        return config
    }

    /// Adds This iPhone at launch in a DEBUG build launched with
    /// `-ggchat-mock-engine`, over the mock engine, or with
    /// `-ggchat-live-engine-model <id>`, over gglib's with that model chosen,
    /// which is how a walk is given one, as "Add mock provider" gives it a
    /// server. Nothing anywhere else: a build without an engine offers
    /// nothing on-device.
    func addThisIPhoneForAWalk() {
        #if DEBUG
            guard engine.isAvailable else { return }
            let model: String?
            if let behaviour = EngineFactory.mockBehaviour {
                model = behaviour == .noModels ? nil : MockEngine.model.id
            } else if let live = EngineFactory.liveEngineModel {
                model = live
            } else {
                return
            }
            do {
                try addThisIPhone(defaultModel: model)
            } catch {
                report(error)
            }
        #endif
    }

    /// Serves the engine, unless a session is up, this build has no engine,
    /// or the app is away: the engine runs in the foreground only. A serve in
    /// flight is joined rather than doubled, and one asked for while the
    /// engine is going down waits until it is down: the engine has one port,
    /// and a session ending unbinds it.
    ///
    /// Every serve's end wakes the sends waiting for the engine, whether it
    /// landed, was refused or took its own session down, once it is no
    /// longer under way: a wait that joined it looks again, and serves the
    /// engine itself if nothing is up.
    func serveEngine() async {
        if let shuttingDown = engineShuttingDown { await shuttingDown.value }
        if let serving = engineServing { return await serving.value }
        guard engineSession == nil, engine.isAvailable, !isAway else { return }
        let serving = Task {
            await serve()
            engineServing = nil
            if let id = thisIPhoneID { wakeWaitingSend(for: id) }
        }
        engineServing = serving
        await serving.value
    }

    /// One serve, with this device's memory read afresh for it: the session
    /// is kept and its status followed until it ends. A session that ends
    /// without being taken down has stopped on its own, and is forgotten, so
    /// the next opening or send serves again.
    ///
    /// A serve that lands after a shutdown has begun, or while the app is
    /// away, takes its own session down: nothing else would, and a model
    /// would be loaded into it by the next request. A failure goes to a send
    /// waiting for the engine, as a refused dial's does, or else the alert.
    private func serve() async {
        let stamp = onDevice.engineGeneration
        do {
            let session = try await engine.serve(reading: Self.readThisDevice())
            guard onDevice.engineGeneration == stamp, !isAway else {
                await putDown(lateSession: session)
                return
            }
            onDevice.tooBig = []
            engineSession = session
            log.log(.info, "engine serving at \(Redaction.describe(session.baseURL))")
            engineFollowing = Task { [weak self] in
                for await status in session.status { self?.setEngineStatus(status) }
                guard !Task.isCancelled else { return }
                self?.engineSession = nil
                self?.engineFollowing = nil
            }
        } catch {
            if let id = thisIPhoneID, handToWaitingSend(error.localizedDescription, for: id) {
                log.log(.info, "the engine did not serve: \(error.localizedDescription)")
            } else {
                report(error)
            }
        }
    }

    /// Takes down a session whose serve landed too late to be kept, inside a
    /// background assertion of its own, for `installPipe`'s reason: the serve
    /// belonged to no pass that holds one.
    private func putDown(lateSession session: any EngineSession) async {
        log.log(.info, "engine served too late to be kept; taking that session down")
        let assertion = BackgroundAssertion(name: "put down an engine served late")
        await session.shutdown()
        assertion.end()
    }

    /// Takes the engine down, if it is up, freeing the model it holds: what
    /// removing its provider, the background, a memory warning and Load
    /// again do. A serve in flight is let land first and takes its own
    /// session down, since the stamp has moved on, and a shutdown in flight
    /// is joined. The session is forgotten once it is down, so a serve cannot
    /// bind the port before it is free; while it goes down no request is
    /// sent to it (`sessionIsUp`).
    func shutDownEngine() async {
        if let shuttingDown = engineShuttingDown { return await shuttingDown.value }
        onDevice.engineGeneration += 1
        let shuttingDown = Task {
            if let serving = engineServing { await serving.value }
            engineFollowing?.cancel()
            engineFollowing = nil
            if let session = engineSession {
                setEngineStatus(nil)
                await session.shutdown()
                engineSession = nil
            }
            engineShuttingDown = nil
        }
        engineShuttingDown = shuttingDown
        await shuttingDown.value
    }

    /// The engine's provider: an ordinary OpenAI-compatible provider at the
    /// session's loopback URL with the session's key, or nil, with a
    /// sentence, while no session is up.
    func makeEngineProvider(for config: ProviderConfig) -> (any Provider)? {
        guard let session = engineSession else {
            // Never over the top of a sentence already waiting to be read,
            // for `makePipeProvider`'s reason.
            if lastError == nil {
                lastError =
                    engine.isAvailable
                    ? "\(config.name) has not started its engine yet."
                    : OnDeviceError.engineUnavailable.localizedDescription
            }
            return nil
        }
        return registry.makeProvider(baseURL: session.baseURL, apiKey: session.apiKey, log: log)
    }

    /// Whether the session behind `config` takes a request now: a pipe once
    /// it is connected, this device's engine once it is served and while it
    /// is not going down. A server by address has no session, so it always
    /// does.
    func sessionIsUp(_ config: ProviderConfig) -> Bool {
        switch config.kind {
        case .openAICompatible: true
        case .pipe: pipeSessions[config.id] != nil && pipeStatuses[config.id]?.isConnected == true
        case .onDevice: engineSession != nil && engineShuttingDown == nil
        }
    }

    /// This device's engine's provider's id, while there is one.
    var thisIPhoneID: UUID? {
        providers.first { $0.kind == .onDevice }?.id
    }

    /// This device's memory, read once per serve: `DeviceReadingSampler`'s
    /// reading on iOS. Elsewhere the sampler reads nothing and no engine
    /// runs, so the physical memory stands for what is available too.
    static func readThisDevice() -> DeviceReading {
        if let reading = DeviceReadingSampler.sample() { return reading }
        let physical = ProcessInfo.processInfo.physicalMemory
        return DeviceReading(physicalBytes: physical, availableBytes: physical, isSimulator: false)
    }
}
