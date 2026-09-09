#if os(iOS)
    import UIKit
#endif

/// A little more time to finish going to the background.
///
/// ``AppModel/didEnterBackground()`` now awaits real work: it puts the reply
/// in flight down, and then hangs up each pipe, which with a real connector
/// means a QUIC close that tells the far side rather than leaving it to time
/// out. It is started from an un-awaited `Task` off the scene phase, so
/// nothing holds the process open while it runs.
///
/// If iOS suspends the app part-way through, the `.closed` that
/// `disconnectPipe` writes never lands. The pill comes back reading whatever
/// it last said, and ADR 0002's denominator loses the close that is by far
/// its commonest case — a phone going to the background is how nearly every
/// pipe in this app ends. The reading would then be taken over a denominator
/// missing the thing it exists to measure.
///
/// So this asks for the usual grace, and gives it back the moment the work is
/// done. Nothing here retries or defends against expiry: if the system takes
/// the time back, the work was going to be cut short either way, and the
/// point is to make that rare rather than to pretend it cannot happen.
///
/// On macOS there is no such thing and no need for one — a Mac app is not
/// suspended out from under itself — so this is an empty shell there rather
/// than a branch at every call site.
@MainActor
struct BackgroundAssertion {
    #if os(iOS)
        private let identifier: UIBackgroundTaskIdentifier
    #endif

    init(name: String) {
        #if os(iOS)
            identifier = UIApplication.shared.beginBackgroundTask(withName: name)
        #endif
    }

    /// Idempotent in the only way that matters: ending an assertion the
    /// system already reclaimed is documented as harmless, and `.invalid` is
    /// what `beginBackgroundTask` returns when it granted nothing at all.
    func end() {
        #if os(iOS)
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
        #endif
    }
}
