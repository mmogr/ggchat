import Foundation

/// The seam between the app and the engine that runs models on this device.
/// `EngineFactory` chooses the one behind it: `MockEngine` in a DEBUG build
/// launched with `-ggchat-mock-engine`, and `UnavailableEngine` everywhere
/// else, a release build included, until gglib's engine is linked.
///
/// Shaped after the pipe's seam (``PipeConnector``, ``PipeSession``) and
/// after gglib-ffi's `Library.serve`, call for call, so the binding maps onto
/// it without reshaping. Chat never crosses it: a session hands back a
/// loopback base URL and a key, and the unchanged `OpenAICompatibleProvider`
/// talks to that, as it does to a pipe (ADR 0001).
public protocol LocalEngine: Sendable {
    /// Whether this build and this device can run a model at all. Nothing
    /// on-device is offered where it is false.
    var isAvailable: Bool { get }
    /// Starts serving: gglib's proxy in front of the engine, at a loopback
    /// port of its own, with a key of its own. No model is loaded yet; the
    /// first request that names one loads it, and ``EngineSession/status``
    /// says how that goes.
    ///
    /// - Parameter reading: this device's memory, read once for the session:
    ///   every model the session admits is fitted to the same budget.
    func serve(reading: DeviceReading) async throws -> any EngineSession
}

/// A serving engine. Requests go to `baseURL` with `apiKey` as the bearer,
/// through an ordinary `OpenAICompatibleProvider`.
///
/// Requirements rather than extras with defaults, for ``PipeSession``'s
/// reason: a session that forgot to report its status would read as idle
/// for ever, and nothing would fail.
public protocol EngineSession: Sendable {
    /// `http://127.0.0.1:<port>/v1`
    var baseURL: URL { get }
    /// The bearer this session's proxy admits, a new one each time the
    /// engine is served. Named so `scripts/check_log_calls.sh` refuses a log
    /// line that reads it.
    var apiKey: String { get }
    /// Current value first, then every change; it ends once the session
    /// has stopped.
    var status: AsyncStream<EngineStatus> { get }
    /// Puts the model down and closes the session's port. Idempotent.
    func shutdown() async
}

/// The engine's state as the app sees it, mirroring gglib-ffi's
/// `EngineState`: one model resident at most.
public enum EngineStatus: Sendable, Equatable, Hashable {
    /// Serving, with no model loaded.
    case idle
    /// `model` is being loaded; `fraction` runs from 0 to 1.
    case loading(model: String, fraction: Double)
    /// `model` is loaded with a context of `nCtx` tokens, the size the
    /// context ring reads against.
    case ready(model: String, nCtx: UInt64)
    /// `model` could not be loaded; `reason` is the engine's sentence. The
    /// next request that names a model tries again.
    case failed(model: String, reason: String)
    /// The session has ended. Nothing follows it.
    case stopped
}

/// This device's memory, as the app read it, mirroring gglib-ffi's
/// `DeviceReading`. The app only reads it; gglib makes the budget a model may
/// spend from it, and every verdict and every admission is gglib's.
public struct DeviceReading: Sendable, Equatable, Hashable {
    /// The device's physical memory, in bytes.
    public var physicalBytes: UInt64
    /// The memory this process can still allocate, in bytes.
    public var availableBytes: UInt64
    /// The reading was taken on a simulator, whose memory is the host's.
    public var isSimulator: Bool

    public init(physicalBytes: UInt64, availableBytes: UInt64, isSimulator: Bool) {
        self.physicalBytes = physicalBytes
        self.availableBytes = availableBytes
        self.isSimulator = isSimulator
    }
}
