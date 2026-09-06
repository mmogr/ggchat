import Foundation
import Synchronization

#if canImport(os)
    import os
#endif

public enum LogLevel: String, Sendable {
    case debug
    case info
    case error
}

/// Every log line in Core goes through one of these, so a test can capture
/// the output and assert that no credential ever appears in it.
public protocol LogSink: Sendable {
    func log(_ level: LogLevel, _ message: String)
}

public struct NoopLogSink: LogSink {
    public init() {}
    public func log(_ level: LogLevel, _ message: String) {}
}

/// Keeps every line in memory. Used by tests and by the in-app diagnostics.
public final class CapturingLogSink: LogSink, Sendable {
    private let storage = Mutex<[String]>([])

    public init() {}

    public func log(_ level: LogLevel, _ message: String) {
        storage.withLock { $0.append("[\(level.rawValue)] \(message)") }
    }

    public var lines: [String] {
        storage.withLock { $0 }
    }
}

#if canImport(os)
    public struct OSLogSink: LogSink {
        private let logger: Logger

        public init(subsystem: String = "com.mattogrady.ggchat", category: String) {
            logger = Logger(subsystem: subsystem, category: category)
        }

        public func log(_ level: LogLevel, _ message: String) {
            switch level {
            case .debug: logger.debug("\(message, privacy: .public)")
            case .info: logger.info("\(message, privacy: .public)")
            case .error: logger.error("\(message, privacy: .public)")
            }
        }
    }
#endif

/// What a URL looks like in a log line: scheme, host, port and path only.
/// No query, no user info, and headers are never logged at all.
public enum Redaction {
    public static func describe(_ url: URL) -> String {
        var parts = ""
        if let scheme = url.scheme { parts += scheme + "://" }
        if let host = url.host() { parts += host }
        if let port = url.port { parts += ":\(port)" }
        parts += url.path()
        return parts
    }
}
