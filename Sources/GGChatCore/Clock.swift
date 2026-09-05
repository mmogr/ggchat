/// Time is an argument. Anything in Core that waits takes a `Sleeper`, so
/// previews and tests can run the same code without waiting.
public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

/// The real thing.
public struct ContinuousClockSleeper: Sleeper {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

/// Returns at once, still honouring cancellation, so a walk that would take
/// seconds completes in a test in microseconds.
public struct ImmediateSleeper: Sleeper {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}
