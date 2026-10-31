import Foundation
import Synchronization
import XCTest

/// A `modelpipe serve` on this machine, run by the binary `MODELPIPE_BIN`
/// names, for a test that dials it through the shipped connector.
///
/// Hermetic, as modelpipe's own `serve_ticket.rs` runs it: discovery and port
/// mapping off, a relay URL that parses and answers nothing, and a backend on
/// a loopback port nothing listens on, which serve resolves at startup and
/// dials only when a request arrives. The pairing forms over the addresses
/// the ticket carries, and nothing past this machine is asked. `--no-state`
/// keeps it out of the real data directory, so a run never reads a
/// developer's identity and never leaves one behind.
///
/// `Process` is unguarded, as in `GGChatLocalTests`' `LiveEngineLibrary`: the
/// package's test targets are built for macOS only, by `swift test`.
struct ModelpipeServe {
    /// A relay URL that parses and answers nothing, so serve gives up looking
    /// for one after its ten seconds and dials nobody else.
    static let deadRelay = "https://127.0.0.1:1/"

    /// A backend that resolves to loopback and that nothing listens on.
    static let deadBackend = "http://127.0.0.1:9"

    /// How long serve has to print a ticket or end. Four times the ten seconds
    /// it should take, as modelpipe's own tests allow: what this guards is
    /// what serve said, not how quickly, and what it buys is a failure rather
    /// than a suite that hangs.
    static let patience: Duration = .seconds(40)

    /// How long serve has to end after each signal. The first asks for a
    /// graceful shutdown, which serve may spend draining; the second, a
    /// `SIGKILL`, is not one it can refuse.
    static let grace: Duration = .seconds(5)

    /// What this serve prints, and so what a dial goes to.
    let ticket: String
    /// The bearer token this serve requires.
    let token: String
    private let process: Process
    private let stdout: FileHandle
    private let stderr: URL

    /// The binary to run: a skip when none is named, so `swift test` and the
    /// main CI job stay hermetic, and a failure when `GGCHAT_PIPE_REQUIRED=1`,
    /// which `make test-pipe` sets, so that target cannot pass having run
    /// nothing.
    static func binary() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["MODELPIPE_BIN"], !path.isEmpty else {
            if environment["GGCHAT_PIPE_REQUIRED"] == "1" { throw Refusal.unnamed }
            throw XCTSkip("MODELPIPE_BIN is not set; `make test-pipe` says what it needs")
        }
        return URL(filePath: path)
    }

    /// Starts serve and waits for its ticket. A binary that is named and does
    /// not print one is a failure, not a skip, and says what serve wrote.
    static func start(requiring token: String) async throws -> ModelpipeServe {
        let binary = try binary()
        let stderr = FileManager.default.temporaryDirectory.appending(
            path: "ggchat-modelpipe-serve-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: stderr.path(percentEncoded: false), contents: nil) else {
            throw Refusal.noLog(stderr.path(percentEncoded: false))
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "serve", deadBackend, "--token", token, "--no-state", "--no-qr", "--no-discovery", "--no-portmap",
            "--relay", deadRelay,
        ]
        // None of these may leak in from the developer's shell: the first two
        // would move or name a state folder, the third would name a token.
        var environment = ProcessInfo.processInfo.environment
        for name in ["XDG_DATA_HOME", "MODELPIPE_STATE_DIR", "MODELPIPE_TOKEN"] {
            environment[name] = nil
        }
        process.environment = environment
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        // A file rather than a pipe: nothing reads serve's notes while it
        // runs, and a pipe nobody drains is one a chatty child blocks on.
        process.standardError = try FileHandle(forWritingTo: stderr)
        try process.run()

        let stdout = output.fileHandleForReading
        let outcome = await firstTicket(on: stdout)
        guard case .ticket(let ticket) = outcome else {
            let ending = await ending(of: process, after: outcome)
            stdout.readabilityHandler = nil
            let said = (try? String(contentsOf: stderr, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: stderr)
            throw Refusal.noTicket(ending: ending, said: said)
        }
        return ModelpipeServe(ticket: ticket, token: token, process: process, stdout: stdout, stderr: stderr)
    }

    /// Ends serve, by the process this test started and nothing else, and
    /// takes its log away.
    func stop() async {
        await Self.stop(process)
        stdout.readabilityHandler = nil
        try? FileManager.default.removeItem(at: stderr)
    }

    /// `SIGTERM`, and `SIGKILL` if serve is still there after ``grace``. Never
    /// a bare `waitUntilExit()`: serve's first signal starts a graceful
    /// shutdown, and one that stalls would hang the teardown with it.
    private static func stop(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        if await exited(process, within: grace) { return }
        kill(process.processIdentifier, SIGKILL)
        _ = await exited(process, within: grace)
    }

    /// Whether `process` has ended, asked until `limit` runs out. Polled, so
    /// that nothing blocks a thread the test's other tasks may need.
    private static func exited(_ process: Process, within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while process.isRunning {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// How serve came to print no ticket, said once it is no longer running.
    /// A serve that ended on its own is reported by its own status, not by
    /// the signal this side would otherwise send it.
    private static func ending(of process: Process, after outcome: Outcome) async -> String {
        if case .ended = outcome { _ = await exited(process, within: grace) }
        if !process.isRunning { return "ended with status \(process.terminationStatus)" }
        await stop(process)
        if case .ended = outcome { return "closed its stdout without ending, and was stopped" }
        return "printed nothing that was a ticket within \(patience), and was stopped at that limit"
    }

    /// What reading serve's stdout came to.
    enum Outcome: Sendable {
        case ticket(String)
        /// Its stdout reached its end.
        case ended
        case outOfPatience
    }

    /// The first `ticket: ` line on serve's stdout, the stream's end, or
    /// ``patience`` running out, whichever comes first.
    ///
    /// Read through `readabilityHandler` rather than a task blocked on the
    /// stream, so the limit returns on time even when something — a child of
    /// serve's, say — holds stdout open. The handler goes on draining after a
    /// ticket, so a serve that keeps talking never blocks on a full pipe.
    private static func firstTicket(on stdout: FileHandle) async -> Outcome {
        let (outcomes, events) = AsyncStream.makeStream(of: Outcome.self)
        let lines = LineBuffer()
        stdout.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                events.yield(.ended)
                return
            }
            if let ticket = lines.ticket(after: chunk) { events.yield(.ticket(ticket)) }
        }
        let timer = Task {
            try? await Task.sleep(for: patience)
            events.yield(.outOfPatience)
        }
        defer {
            timer.cancel()
            events.finish()
        }
        for await outcome in outcomes { return outcome }
        return .outOfPatience
    }

    /// What serve has written so far that is not yet a whole line, and
    /// whether a ticket has already been found in it.
    private final class LineBuffer: Sendable {
        private let state = Mutex((pending: Data(), found: false))

        /// The ticket on the first whole `ticket: ` line `chunk` completes, or
        /// `nil`; after one is found, every later chunk is dropped.
        func ticket(after chunk: Data) -> String? {
            state.withLock { state in
                guard !state.found else { return nil }
                state.pending.append(chunk)
                while let newline = state.pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = String(decoding: state.pending[..<newline], as: UTF8.self)
                    state.pending.removeSubrange(...newline)
                    if line.hasPrefix("ticket: ") {
                        state.found = true
                        state.pending = Data()
                        return String(line.dropFirst("ticket: ".count))
                    }
                }
                return nil
            }
        }
    }

    enum Refusal: Error, CustomStringConvertible {
        case unnamed
        case noLog(String)
        case noTicket(ending: String, said: String)

        var description: String {
            switch self {
            case .unnamed:
                "GGCHAT_PIPE_REQUIRED=1 and MODELPIPE_BIN is not set, so the real pipe would be skipped"
            case .noLog(let path):
                "could not make \(path) for serve's notes"
            case .noTicket(let ending, let said):
                "modelpipe serve printed no ticket: it \(ending). It said:\n\(said)"
            }
        }
    }
}
