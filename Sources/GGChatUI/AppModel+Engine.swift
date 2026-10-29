import Foundation
import GGChatCore

// The engine on this device: the one provider that runs on it, serving it
// when a conversation on that provider opens, the provider a request goes
// through, and taking it down. `AppModel.swift` keeps the state these work
// on. A session stays up once served, through the background too, until its
// provider is removed; a send that finds none is refused with a sentence
// rather than waiting for one.
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

    /// Adds the mock engine's provider at launch in a DEBUG build launched
    /// with `-ggchat-mock-engine`, which is how a walk is given one, as
    /// "Add mock provider" gives it a server. Nothing anywhere else: a build
    /// without an engine offers nothing on-device.
    func addThisIPhoneForAWalk() {
        #if DEBUG
            guard let behaviour = EngineFactory.mockBehaviour, engine.isAvailable else { return }
            do {
                try addThisIPhone(defaultModel: behaviour == .noModels ? nil : MockEngine.model.id)
            } catch {
                report(error)
            }
        #endif
    }

    /// Serves the engine, unless a session is up or this build has no
    /// engine. A serve in flight is joined rather than doubled, and one
    /// asked for while the engine is going down waits until it is down: the
    /// engine has one port, and a session ending unbinds it.
    func serveEngine() async {
        if let shuttingDown = engineShuttingDown { await shuttingDown.value }
        if let serving = engineServing { return await serving.value }
        guard engineSession == nil, engine.isAvailable else { return }
        let serving = Task {
            await serve()
            engineServing = nil
        }
        engineServing = serving
        await serving.value
    }

    /// One serve: the session is kept, and its status followed until it
    /// ends. A session that ends without being taken down has stopped on
    /// its own, and is forgotten, so the next opening serves again.
    private func serve() async {
        do {
            let session = try await engine.serve(reading: Self.readThisDevice())
            engineSession = session
            log.log(.info, "engine serving at \(Redaction.describe(session.baseURL))")
            engineFollowing = Task { [weak self] in
                for await status in session.status { self?.engineStatus = status }
                guard !Task.isCancelled else { return }
                self?.engineSession = nil
                self?.engineFollowing = nil
            }
        } catch {
            report(error)
        }
    }

    /// Takes the engine down, if it is up: what removing its provider does.
    /// A serve in flight is let land first and its session taken down, and
    /// a shutdown in flight is joined. The session is forgotten once it is
    /// down, so a serve cannot bind the port before it is free.
    func shutDownEngine() async {
        if let shuttingDown = engineShuttingDown { return await shuttingDown.value }
        let shuttingDown = Task {
            if let serving = engineServing { await serving.value }
            engineFollowing?.cancel()
            engineFollowing = nil
            if let session = engineSession {
                engineStatus = nil
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
    /// it is connected, this device's engine once it is served. A server by
    /// address has no session, so it always does.
    func sessionIsUp(_ config: ProviderConfig) -> Bool {
        switch config.kind {
        case .openAICompatible: true
        case .pipe: pipeSessions[config.id] != nil && pipeStatuses[config.id]?.isConnected == true
        case .onDevice: engineSession != nil
        }
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
