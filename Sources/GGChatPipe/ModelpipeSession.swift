import Foundation
import GGChatCore
import Modelpipe
import Synchronization

/// A live pipe, as the app sees it.
///
/// Wraps `any MpPipeProtocol` rather than the concrete `MpPipe` so the whole
/// of this — the status walk, the grace, the close — can be driven by a fake
/// in a test with no network, no port and no far machine.
public final class ModelpipeSession: PipeSession, Sendable {
    public let baseURL: URL

    private let pipe: any MpPipeProtocol
    private let relay: PipeStatusRelay
    private let driver = Mutex<Task<Void, Never>?>(nil)
    private let deferred = Mutex<Task<Void, Never>?>(nil)

    /// How long `relayed` has to survive before it is worth showing.
    ///
    /// A pipe commonly establishes through a relay and hole-punches to a
    /// direct path a moment later — the spike measured 1.05s to relayed and
    /// 2.05s to direct. Publishing both puts "Relayed" on screen for a
    /// second, which reads as a warning about a connection that is in fact
    /// still being made. The grace is here rather than in the view because
    /// the app has exactly one writer of pipe status and a second one in the
    /// UI would be a second source of truth.
    private let grace: Duration
    private let sleeper: any Sleeper

    /// Fails rather than force-unwraps if the base URL is not the shape the
    /// seam promises.
    ///
    /// It checks the shape and not merely that `URL(string:)` returned
    /// something. `URL` parses far more than it looks like it does — it
    /// accepts strings with spaces and no scheme at all — so a nil check here
    /// would have passed almost anything through to become a provider's base
    /// URL. What the app relies on is `http://127.0.0.1:<port>/v1`: loopback,
    /// because the one hop with no encryption in front of it must not leave
    /// this device, and a port, because there is no pipe without one.
    init(
        pipe: any MpPipeProtocol,
        sleeper: any Sleeper = ContinuousClockSleeper(),
        grace: Duration = .milliseconds(1200)
    ) throws {
        let raw = pipe.baseUrl()
        guard let url = URL(string: raw), url.scheme == "http", url.port != nil,
            url.host == "127.0.0.1" || url.host == "localhost"
        else {
            throw PipeConnectError.dialFailed(
                message: "The pipe came up somewhere this app will not send a request.",
                retryable: true)
        }
        self.baseURL = url
        self.pipe = pipe
        self.sleeper = sleeper
        self.grace = grace
        self.relay = PipeStatusRelay(initial: PipeStatus(pipe.status()))
        start()
    }

    public var status: AsyncStream<PipeStatus> { relay.stream() }

    /// Pumps the binding's poll into the relay, in the shape modelpipe-ffi's
    /// own documentation asks for: the caller holds the snapshot, so no
    /// transition is coalesced away and the sequence ends instead of
    /// answering `closed` for ever.
    private func start() {
        driver.withLock {
            $0 = Task { [pipe, relay, weak self] in
                var held = pipe.status()
                while let next = await pipe.statusChangedSince(snapshot: held) {
                    held = next
                    self?.publish(PipeStatus(next))
                }
                // The sequence ends on *any* close, `listenerFailed` included,
                // and nothing above this writes a status when a stream merely
                // finishes. Without this line a pipe that died on its own
                // would leave the pill reading "Direct" over a dead port,
                // leave the close uncounted, and leave the provider pointed at
                // a listener that is gone.
                self?.cancelDeferred()
                relay.send(.closed)
                relay.finish()
            }
        }
    }

    /// Publishes a status, holding `relayed` back for the grace in case a
    /// direct path is a moment behind it.
    private func publish(_ status: PipeStatus) {
        cancelDeferred()
        guard status == .relayed else {
            relay.send(status)
            return
        }
        deferred.withLock {
            $0 = Task { [relay, sleeper, grace] in
                guard (try? await sleeper.sleep(for: grace)) != nil else { return }
                relay.send(.relayed)
            }
        }
    }

    private func cancelDeferred() {
        deferred.withLock {
            $0?.cancel()
            $0 = nil
        }
    }

    /// Idempotent, and the base URL refuses rather than hangs afterwards.
    ///
    /// The close is written here as well as in the driver: `shutdown` is the
    /// path the app takes on its way to the background, and it must not
    /// depend on the driver waking up to record what just happened.
    public func shutdown() async {
        await pipe.shutdown()
        cancelDeferred()
        driver.withLock {
            $0?.cancel()
            $0 = nil
        }
        relay.send(.closed)
        relay.finish()
    }

    /// What the pipe last said about why it closed, if it has closed.
    public var closeReason: MpCloseReason? { pipe.closeReason() }

    /// The loopback port, for a diagnostic that wants the number alone.
    public var port: UInt16 { pipe.port() }

    /// Relay counters for this pipe's endpoint.
    public var networkMetrics: MpNetworkMetrics { pipe.networkMetrics() }

    /// Tell the endpoint its network may have moved.
    public func notifyNetworkChange() async { await pipe.notifyNetworkChange() }
}
