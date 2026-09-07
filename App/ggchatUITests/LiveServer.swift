import Darwin
import Foundation

/// Which server the live walks drive, and what they authenticate with.
///
/// The two names are the ones the SwiftPM live tests already read, so one
/// recipe configures both halves of the live suite:
///
/// ```sh
/// GGCHAT_LIVE_BASE_URL=http://127.0.0.1:8080/v1 GGCHAT_LIVE_API_KEY=... make uitest
/// ```
///
/// They reach this process through the `TEST_RUNNER_` prefix. A test runner
/// on a simulator does not inherit the environment `xcodebuild` was invoked
/// with; it is given the variables named `TEST_RUNNER_<NAME>`, with the
/// prefix stripped. The Makefile and `scripts/screenshots.sh` set them that
/// way, which is the only reason the bare names are readable here.
struct LiveServer {
    /// The `/v1` root typed into the provider form's address field.
    let baseURL: String

    /// Typed into the API key field when it is not empty. Before this the
    /// walks typed nothing, so they could only ever pass against a server
    /// that enforces no key.
    let apiKey: String

    /// Where gglib listens by default. The simulator shares the host's
    /// loopback, so this is the same server the Mac is running.
    static let defaultHost = "127.0.0.1"
    static let defaultPort = 8080
    static var defaultBaseURL: String { "http://\(defaultHost):\(defaultPort)/v1" }

    /// The server a live walk should drive, or `nil` when it should skip.
    ///
    /// A `GGCHAT_LIVE_BASE_URL` that is set is taken at its word and never
    /// probed: naming a server and then failing to reach it is a result worth
    /// seeing, and the same reasoning already makes `make test-live` refuse to
    /// run without it rather than pass having exercised nothing.
    ///
    /// With it unset the default loopback is probed and nothing listening
    /// means skip. That is exactly what these walks did before, and keeping it
    /// is what leaves CI -- where no gglib runs and no variable is set -- green,
    /// and what lets `scripts/screenshots.sh` go on taking the two live
    /// screenshots against a keyless gglib without being told where it is.
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        probe: (String, Int) -> Bool = somethingIsListening
    ) -> LiveServer? {
        // An unset variable and one set to the empty string are the same
        // thing here: the Makefile forwards `TEST_RUNNER_GGCHAT_LIVE_BASE_URL`
        // unconditionally, so an empty value is what "the caller set nothing"
        // looks like by the time it arrives.
        let key = environment["GGCHAT_LIVE_API_KEY"] ?? ""
        if let named = environment["GGCHAT_LIVE_BASE_URL"], !named.isEmpty {
            return LiveServer(baseURL: named, apiKey: key)
        }
        guard probe(defaultHost, defaultPort) else { return nil }
        return LiveServer(baseURL: defaultBaseURL, apiKey: key)
    }

    /// Why a walk skipped, in the sentence the developer needs to un-skip it.
    static var absenceReason: String {
        "no live server: nothing is listening on \(defaultBaseURL) and GGCHAT_LIVE_BASE_URL is not set."
            + " Start gglib, or set GGCHAT_LIVE_BASE_URL (and GGCHAT_LIVE_API_KEY if it wants one)."
    }

    /// A plain TCP connect, so the probe is not subject to the test runner's
    /// transport security rules. Only ever aimed at ``defaultHost``, which is
    /// a dotted quad: `inet_addr` does not resolve names, and a named server
    /// is not probed at all.
    static func somethingIsListening(host: String, port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr(host)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connected == 0
    }
}
