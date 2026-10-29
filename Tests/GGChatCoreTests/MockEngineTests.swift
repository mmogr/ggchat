import XCTest

@testable import GGChatCore

/// The mock that stands in for gglib's engine in a DEBUG build and in the
/// app model's tests: what it serves, how its status walks, and what each
/// behaviour a walk can ask for does.
final class MockEngineTests: XCTestCase {
    private let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: true)

    /// The status is idle first, as a serve with no model loaded is, then
    /// one step per release of the sleeper to ready with the context the
    /// mock reports; a late subscriber hears the current state first, and
    /// shutting down says `stopped` and ends the stream.
    func testTheStatusWalksFromIdleToReadyAndEndsStopped() async throws {
        let sleeper = GatedSleeper()
        let engine = MockEngine(sleeper: sleeper, registry: LoopbackProviderRegistry())
        let session = try await engine.serve(reading: reading)
        var iterator = session.status.makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first, .idle)
        await sleeper.release()
        let second = await iterator.next()
        XCTAssertEqual(second, .loading(model: MockEngine.model.id, fraction: 0.5))
        await sleeper.release()
        let third = await iterator.next()
        XCTAssertEqual(third, .ready(model: MockEngine.model.id, nCtx: 4_096))

        var late = session.status.makeAsyncIterator()
        let lateFirst = await late.next()
        XCTAssertEqual(lateFirst, .ready(model: MockEngine.model.id, nCtx: 4_096), "a late subscriber starts late")

        await session.shutdown()
        let stopped = await iterator.next()
        XCTAssertEqual(stopped, .stopped)
        let end = await iterator.next()
        XCTAssertNil(end, "shutdown ends the stream")
    }

    /// Serving binds the mock at its one loopback address with its key, and
    /// shutting down unbinds it, so the address falls through to a real
    /// provider. A second shutdown leaves a later session's binding alone.
    func testServingBindsTheMockAtItsAddressUntilShutdown() async throws {
        let registry = LoopbackProviderRegistry()
        let engine = MockEngine(registry: registry)
        XCTAssertTrue(engine.isAvailable)
        let session = try await engine.serve(reading: reading)
        XCTAssertEqual((session as? MockEngineSession)?.reading, reading, "the session lost its reading")
        XCTAssertEqual(session.baseURL, MockEngine.baseURL)
        XCTAssertEqual(session.baseURL.host(), "127.0.0.1")
        XCTAssertFalse(session.apiKey.isEmpty)
        XCTAssertTrue(registry.makeProvider(baseURL: session.baseURL, apiKey: session.apiKey) is MockProvider)
        await session.shutdown()
        XCTAssertNil(registry.provider(for: MockEngine.baseURL))

        let again = try await engine.serve(reading: reading)
        await session.shutdown()
        XCTAssertNotNil(
            registry.provider(for: MockEngine.baseURL), "the first session's second shutdown unbound the next")
        await again.shutdown()
    }

    /// Each behaviour is spelled as `-ggchat-mock-engine` takes it, so a
    /// walk's launch argument reaches the case it names.
    func testEachBehaviourIsSpelledAsTheLaunchArgumentTakesIt() {
        XCTAssertEqual(
            MockEngine.Behaviour.allCases.map(\.rawValue), ["ready", "slow", "fails", "too-big", "no-models"])
    }

    /// The one model answers with the mock's reply and reports the context
    /// it loaded, so a reply raises the context ring.
    func testAReplyReportsTheContextTheModelLoaded() async throws {
        let usage = try await finishedUsage(of: MockEngine())
        XCTAssertEqual(usage?.contextSize, 4_096)
        XCTAssertNotNil(usage?.promptTokens)
        XCTAssertNotNil(usage?.completionTokens)
    }

    /// Too big refuses before the first token as gglib refuses a model too
    /// big for the device, and never loads: its status stays idle.
    func testTooBigIsRefusedAs507ModelDoesNotFitAndLoadsNothing() async throws {
        let engine = MockEngine(behaviour: .tooBig, registry: LoopbackProviderRegistry())
        XCTAssertEqual(engine.walk, [])
        let events = try await reply(from: engine)
        guard case .error(.server(let status, let code, _))? = events.first else {
            return XCTFail("too big answered \(events)")
        }
        XCTAssertEqual(status, 507)
        XCTAssertEqual(code, ProviderError.Code.modelDoesNotFit.rawValue)
        XCTAssertEqual(ProviderError.whereToLook(forCode: code), .request, "a smaller model is the remedy")
    }

    /// Slow loads in ten steps; fails ends failed and refuses a chat; no
    /// models lists none and loads nothing.
    func testTheOtherBehavioursWalkAndListAsTheyAreNamed() async throws {
        let slow = MockEngine(behaviour: .slow).walk
        XCTAssertEqual(slow.count, 11)
        XCTAssertEqual(slow.last, .ready(model: MockEngine.model.id, nCtx: 4_096))

        let fails = MockEngine(behaviour: .fails, registry: LoopbackProviderRegistry())
        guard case .failed? = fails.walk.last else { return XCTFail("fails walked \(fails.walk)") }
        let refused = try await reply(from: fails)
        guard case .error? = refused.first else { return XCTFail("a failed load answered \(refused)") }

        let none = MockEngine(behaviour: .noModels, registry: LoopbackProviderRegistry())
        XCTAssertEqual(none.walk, [])
        let listed = try await none.answering.models()
        XCTAssertEqual(listed, [])
    }

    /// The events of one reply from what `engine` serves.
    private func reply(from engine: MockEngine) async throws -> [ChatEvent] {
        let session = try await engine.serve(reading: reading)
        let provider = engine.registry.makeProvider(baseURL: session.baseURL, apiKey: session.apiKey)
        var events: [ChatEvent] = []
        for await event in provider.stream(ChatRequest(model: MockEngine.model.id, messages: [])) {
            events.append(event)
        }
        await session.shutdown()
        return events
    }

    private func finishedUsage(of engine: MockEngine) async throws -> Usage? {
        let registry = LoopbackProviderRegistry()
        var engine = engine
        engine.registry = registry
        for event in try await reply(from: engine) {
            if case .finished(_, let usage) = event { return usage }
        }
        return nil
    }
}

/// The library beside the mock engine: a verdict of each kind, as gglib
/// would hand them over, and a download that walks to done.
final class MockLibraryTests: XCTestCase {
    private let reading = DeviceReading(physicalBytes: 12 << 30, availableBytes: 6 << 30, isSimulator: true)

    /// The phone's repository has a quantization for each verdict there is,
    /// another has none that fits, and each reading asked with is kept.
    func testTheQuantizationsCarryAVerdictOfEachKind() async throws {
        let library = MockLibrary()
        let offers = try await library.quantizations(repo: MockLibrary.phoneRepo, reading: reading)
        let desk = try await library.quantizations(repo: MockLibrary.deskRepo, reading: reading)
        XCTAssertEqual(desk.map(\.verdict), [MockLibrary.tooBig])
        XCTAssertEqual(library.readings.all, [reading, reading])
        let kinds = offers.map { offer -> String in
            switch offer.verdict {
            case .fits: "fits"
            case .tight: "tight"
            case .tooBig: "too big"
            case .unknown: "unknown"
            }
        }
        XCTAssertEqual(kinds, ["fits", "tight", "too big", "unknown"])
    }

    /// The engine's model is installed, but for no-models, and too big for
    /// too-big.
    func testWhatIsInstalledFollowsTheBehaviour() async throws {
        let installed = try await MockLibrary().installed()
        XCTAssertEqual(installed.map(\.name), [MockEngine.model.id])
        let none = try await MockLibrary(behaviour: .noModels).installed()
        XCTAssertEqual(none, [])
        let tooBig = try await MockLibrary(behaviour: .tooBig).installed()
        guard case .tooBig? = tooBig.first?.verdict else {
            return XCTFail("too-big installed a model that fits")
        }
    }

    /// A search answers one hit a page, the cursor naming the next, and a
    /// removal is refused for a model that is not installed.
    func testASearchPagesOneHitAtATimeAndARemovalNeedsAnInstalledModel() async throws {
        let library = MockLibrary()
        let first = try await library.search(query: "", cursor: nil)
        let second = try await library.search(query: "", cursor: first.nextCursor)
        XCTAssertEqual(first.hits.map(\.repo), [MockLibrary.phoneRepo])
        XCTAssertEqual(second.hits.map(\.repo), [MockLibrary.deskRepo])
        XCTAssertNil(second.nextCursor)
        let found = try await library.search(query: "DESK", cursor: nil)
        XCTAssertEqual(found.hits.map(\.repo), [MockLibrary.deskRepo])

        try await library.remove(id: 1)
        do {
            try await library.remove(id: 2)
            XCTFail("a model that is not installed was removed")
        } catch {
            XCTAssertEqual(error as? OnDeviceError, .notFound)
        }
    }

    /// A download is queued, runs with its bytes going up, verifies and is
    /// done, and the stream ends there.
    func testADownloadWalksToDoneWithItsBytesGoingUp() async throws {
        var states: [DownloadState] = []
        var bytes: [UInt64] = []
        for await step in try await MockLibrary().download(repo: "mock/phone-1.7b-GGUF", quantization: "Q4_K_M") {
            states.append(step.state)
            bytes.append(step.bytes)
        }
        XCTAssertEqual(states.first, .queued)
        XCTAssertEqual(states.suffix(2), [.verifying, .done])
        XCTAssertEqual(bytes, bytes.sorted(), "the bytes went down")
        XCTAssertEqual(bytes.last, MockLibrary.gigabyte)
    }
}

/// The engine in every build that has none.
final class UnavailableEngineTests: XCTestCase {
    /// Nothing on-device is offered, and a serve asked for anyway is refused
    /// with a sentence about the build, as are the library's questions.
    func testABuildWithNoEngineOffersNoneAndRefusesToServe() async {
        XCTAssertFalse(UnavailableEngine().isAvailable)
        let reading = DeviceReading(physicalBytes: 8 << 30, availableBytes: 4 << 30, isSimulator: false)
        do {
            _ = try await UnavailableEngine().serve(reading: reading)
            XCTFail("a build with no engine served one")
        } catch {
            XCTAssertEqual(error as? OnDeviceError, .engineUnavailable)
        }
        do {
            _ = try await UnavailableLibrary().installed()
            XCTFail("a build with no engine listed models")
        } catch {
            XCTAssertEqual(error as? OnDeviceError, .engineUnavailable)
        }
        XCTAssertTrue(OnDeviceError.engineUnavailable.localizedDescription.contains("build"))
    }
}
