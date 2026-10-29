import GGChatCore
import GGLib
import Synchronization
import XCTest

@testable import GGChatLocal

/// A download's steps as the app follows them, pulled from gglib's watch:
/// the stream the app's download row reads. A stream that ends reads to the
/// app as a download that finished or failed, so it ends only when gglib's
/// watch does, never at a pause; and the app calling a download off is the
/// stream ending first, which must reach gglib.
final class DownloadStepsTests: XCTestCase {
    private func ours(_ bytes: UInt64, _ state: GGChatCore.DownloadState) -> GGChatCore.DownloadProgress {
        GGChatCore.DownloadProgress(id: "owner/model-GGUF:Q4_K_M", bytes: bytes, total: 100, state: state)
    }

    /// Paused, then running again, in one stream: the stream is still open
    /// after the pause, and the steps after the resume arrive in it.
    func testAPauseKeepsTheStreamOpenAndTheResumeGoesOnInIt() async {
        let watch = FakeWatch()
        var steps = GglibLibrary.steps(of: watch).makeAsyncIterator()

        watch.send(step(10, .running))
        let running = await steps.next()
        watch.send(step(10, .paused))
        let paused = await steps.next()
        watch.send(step(40, .running))
        let resumed = await steps.next()
        watch.send(step(100, .done))
        let done = await steps.next()
        watch.send(nil)
        let end = await steps.next()

        XCTAssertEqual(
            [running, paused, resumed, done],
            [ours(10, .running), ours(10, .paused), ours(40, .running), ours(100, .done)])
        XCTAssertNil(end, "the stream went on after gglib's watch ended")
        XCTAssertFalse(watch.isCancelled, "a download that finished was called off")
    }

    /// A download asked of the library is followed through gglib's watch:
    /// the library hands the watch back, and its steps are the stream's.
    func testADownloadAskedOfTheLibraryIsFollowedThroughItsWatch() async throws {
        let watch = FakeWatch()
        let library = GglibLibrary(open: { FakeLibrary(watch: watch) })
        watch.send(step(10, .running))
        watch.send(step(100, .done))
        watch.send(nil)

        var seen: [GGChatCore.DownloadProgress] = []
        for await step in try await library.download(repo: "owner/model-GGUF", quantization: "Q4_K_M") {
            seen.append(step)
        }

        XCTAssertEqual(seen, [ours(10, .running), ours(100, .done)])
    }

    /// A failure is said with gglib's reason, and then the stream ends.
    func testAFailureIsSaidWithItsReasonAndEndsTheStream() async {
        let watch = FakeWatch()
        watch.send(step(0, .queued))
        watch.send(step(30, .failed(reason: "the Hub hung up")))
        watch.send(nil)

        var seen: [GGChatCore.DownloadProgress] = []
        for await step in GglibLibrary.steps(of: watch) { seen.append(step) }

        XCTAssertEqual(seen, [ours(0, .queued), ours(30, .failed(reason: "the Hub hung up"))])
        XCTAssertFalse(watch.isCancelled)
    }

    /// The app calls a download off by ending its stream: the follower's task
    /// is cancelled. That cancels gglib's watch, which stops the download and
    /// ends the pull waiting on it; nothing is left asking gglib.
    func testCancellingTheConsumerCancelsTheWatch() async {
        let watch = FakeWatch()
        let steps = GglibLibrary.steps(of: watch)
        let seen = Seen()
        let follower = Task {
            for await step in steps { seen.keep(step) }
        }
        watch.send(step(10, .running))
        let following = await eventually { seen.steps.count == 1 && watch.isWaiting }
        XCTAssertTrue(following, "the step never arrived, or the pull never came back for the next")

        follower.cancel()
        let cancelled = await eventually { watch.isCancelled && !watch.isWaiting }
        await follower.value

        XCTAssertTrue(cancelled, "ending the stream left gglib's download going")
        XCTAssertEqual(seen.steps, [ours(10, .running)])
    }

    /// Polls `condition` for up to two seconds.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

/// The steps a follower has read so far, for a test to look at while it
/// reads.
private final class Seen: Sendable {
    private let kept = Mutex<[GGChatCore.DownloadProgress]>([])

    var steps: [GGChatCore.DownloadProgress] { kept.withLock { $0 } }

    func keep(_ step: GGChatCore.DownloadProgress) {
        kept.withLock { $0.append(step) }
    }
}
