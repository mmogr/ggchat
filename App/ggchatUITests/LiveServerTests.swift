import XCTest

/// Covers ``LiveServer/resolve(environment:probe:)`` and nothing beyond it:
/// which server a live walk picks, and when it skips instead.
///
/// It deliberately does not claim more. That a walk goes on to type the key
/// it resolved is not asserted here and cannot be: it needs the app running
/// on a simulator against a server that rejects an unauthenticated request,
/// and CI has neither. Deleting the key-typing line leaves every test in this
/// file green, which is why the pull request says so rather than pointing at
/// these.
final class LiveServerTests: XCTestCase {
    /// Counts the probes, so "taken at its word, not probed" is a checkable
    /// claim rather than a stated intention.
    private final class Probe {
        private(set) var calls = 0
        private let answer: Bool
        init(answer: Bool) { self.answer = answer }
        func reply(host: String, port: Int) -> Bool {
            calls += 1
            return answer
        }
    }

    func testANamedServerIsUsedAsGivenAndIsNotProbed() throws {
        let probe = Probe(answer: false)
        let live = try XCTUnwrap(
            LiveServer.resolve(
                environment: ["GGCHAT_LIVE_BASE_URL": "http://10.0.0.2:9099/v1"],
                probe: probe.reply))
        XCTAssertEqual(live.baseURL, "http://10.0.0.2:9099/v1")
        XCTAssertEqual(
            probe.calls, 0,
            "a server named outright was probed, so an unreachable one would skip instead of failing")
    }

    func testAnUnnamedServerFallsBackToTheLoopbackThatAnswers() throws {
        let probe = Probe(answer: true)
        let live = try XCTUnwrap(LiveServer.resolve(environment: [:], probe: probe.reply))
        XCTAssertEqual(live.baseURL, LiveServer.defaultBaseURL)
        XCTAssertEqual(probe.calls, 1, "the fallback did not probe before using the default")
    }

    /// The case CI is in: no variable set, and no gglib listening.
    func testNothingNamedAndNothingListeningIsASkip() {
        XCTAssertNil(LiveServer.resolve(environment: [:], probe: Probe(answer: false).reply))
    }

    /// The Makefile forwards the variable whether or not the caller set it,
    /// so an empty value is what "unset" looks like by the time it lands here.
    func testAnEmptyBaseURLIsTreatedAsUnset() {
        XCTAssertNil(
            LiveServer.resolve(environment: ["GGCHAT_LIVE_BASE_URL": ""], probe: Probe(answer: false).reply),
            "an empty GGCHAT_LIVE_BASE_URL was taken for a server address")
    }

    func testTheKeyIsCarriedOnBothPaths() throws {
        let named = try XCTUnwrap(
            LiveServer.resolve(
                environment: [
                    "GGCHAT_LIVE_BASE_URL": "http://10.0.0.2:9099/v1", "GGCHAT_LIVE_API_KEY": "sk-named",
                ],
                probe: Probe(answer: false).reply))
        XCTAssertEqual(named.apiKey, "sk-named")

        let fallback = try XCTUnwrap(
            LiveServer.resolve(
                environment: ["GGCHAT_LIVE_API_KEY": "sk-fallback"],
                probe: Probe(answer: true).reply))
        XCTAssertEqual(fallback.apiKey, "sk-fallback", "a key set without an address was dropped")
        XCTAssertEqual(fallback.baseURL, LiveServer.defaultBaseURL)
    }

    /// An absent key is empty rather than nil, because the walk decides
    /// whether to type by asking whether it is empty.
    func testAnAbsentKeyIsEmpty() throws {
        let live = try XCTUnwrap(LiveServer.resolve(environment: [:], probe: Probe(answer: true).reply))
        XCTAssertEqual(live.apiKey, "")
    }
}
