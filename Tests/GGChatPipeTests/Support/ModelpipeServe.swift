import Foundation
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

    /// What this serve prints, and so what a dial goes to.
    let ticket: String
    /// The bearer token this serve requires.
    let token: String
    private let process: Process
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

        guard let ticket = await firstTicket(on: output.fileHandleForReading, from: process) else {
            stop(process)
            let said = (try? String(contentsOf: stderr, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(at: stderr)
            throw Refusal.noTicket(status: process.terminationStatus, said: said)
        }
        return ModelpipeServe(ticket: ticket, token: token, process: process, stderr: stderr)
    }

    /// Ends serve, by the process this test started and nothing else, and
    /// takes its log away.
    func stop() {
        Self.stop(process)
        try? FileManager.default.removeItem(at: stderr)
    }

    private static func stop(_ process: Process) {
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }

    /// The text after `ticket: ` on the first line that starts with it, or
    /// `nil` when serve ends or runs out of ``patience`` first.
    ///
    /// Serve that has printed a ticket goes on to run until it is stopped, so
    /// stdout is read while it runs rather than to its end. On running out of
    /// patience serve is stopped, which ends the stream the reader is blocked
    /// on; without that the group would wait on the reader for ever.
    private static func firstTicket(on stdout: FileHandle, from process: Process) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    for try await line in stdout.bytes.lines where line.hasPrefix("ticket: ") {
                        return String(line.dropFirst("ticket: ".count))
                    }
                } catch {
                    return nil
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: patience)
                return nil
            }
            let first = await group.next().flatMap { $0 }
            if first == nil { stop(process) }
            group.cancelAll()
            return first
        }
    }

    enum Refusal: Error, CustomStringConvertible {
        case unnamed
        case noLog(String)
        case noTicket(status: Int32, said: String)

        var description: String {
            switch self {
            case .unnamed:
                "GGCHAT_PIPE_REQUIRED=1 and MODELPIPE_BIN is not set, so the real pipe would be skipped"
            case .noLog(let path):
                "could not make \(path) for serve's notes"
            case .noTicket(let status, let said):
                "modelpipe serve printed no ticket before it ended or \(patience) ran out, "
                    + "and ended with status \(status); it said:\n\(said)"
            }
        }
    }
}
