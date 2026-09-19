import XCTest

@testable import GGChatCore

final class RedactedDescriptionTests: XCTestCase {
    private static let key = "sk-this-key-must-never-print"
    private static let ticket = "pipethisticketmustneverprint"

    /// Every way a value is printed whole, which the log gate cannot see by
    /// name: interpolation, `String(reflecting:)` (the debugger's `po` and
    /// `debugPrint`'s), and `dump` (which prints the stored properties unless
    /// a custom mirror says otherwise).
    private func renderings(of value: some Any) -> [String: String] {
        var dumped = ""
        dump(value, to: &dumped)
        return ["interpolated": "\(value)", "reflected": String(reflecting: value), "dumped": dumped]
    }

    /// The key stays out of every rendering, with and without the pipe a
    /// pairing hands back, and each rendering still says which device the
    /// pairing was for, so a test cannot pass on an empty description. The
    /// exact form pins the description itself: a mirror alone would also
    /// redact, in another shape.
    func testAPairedPipePrintsItsDeviceAndNeverItsKey() async throws {
        let session = try await MockPipeConnector(registry: LoopbackProviderRegistry())
            .connect(ticket: "pipe-ticket", token: "token")
        let withSession = PairedPipe(session: session, token: Self.key, device: "phone-1")
        let withoutSession = PairedPipe(session: nil, token: Self.key, device: "phone-1")
        for paired in [withSession, withoutSession] {
            for (how, text) in renderings(of: paired) {
                XCTAssertFalse(text.contains(Self.key), "\(how) printed the key: \(text)")
                XCTAssertTrue(text.contains("<redacted>"), "\(how): \(text)")
                XCTAssertTrue(text.contains("phone-1"), "\(how): \(text)")
            }
        }
        XCTAssertEqual("\(withSession)", "PairedPipe(device: phone-1, token: <redacted>, session: up)")
        XCTAssertEqual("\(withoutSession)", "PairedPipe(device: phone-1, token: <redacted>, session: none)")
        await session.shutdown()
    }

    /// The ticket stays out, and its digest stands in: the fingerprint a
    /// `ProviderConfig` keeps, so two readings that differ still print
    /// differently.
    func testAReadPairingPrintsItsDigestAndNeverItsTicket() {
        let read = ReadPairing(ticket: Self.ticket, hasCode: true)
        let other = ReadPairing(ticket: "pipeanotherticketentirely", hasCode: true)
        for (how, text) in renderings(of: read) {
            XCTAssertFalse(text.contains(Self.ticket), "\(how) printed the ticket: \(text)")
            XCTAssertTrue(text.contains(Ticket.digest(Self.ticket)), "\(how): \(text)")
            XCTAssertTrue(text.contains("true"), "\(how): \(text)")
        }
        XCTAssertEqual("\(read)", "ReadPairing(ticket: <digest \(Ticket.digest(Self.ticket))>, hasCode: true)")
        XCTAssertNotEqual("\(read)", "\(other)")
    }

    /// For a pipe the provider's key is this device's own, from its pairing.
    /// It stays out; the address stays in, less the user info and query that
    /// `Redaction` drops.
    func testAProviderPrintsItsAddressAndNeverItsKey() throws {
        let url = try XCTUnwrap(URL(string: "http://user:in-the-user-info@127.0.0.1:49333/v1?key=in-the-query"))
        let provider = OpenAICompatibleProvider(baseURL: url, apiKey: Self.key)
        for (how, text) in renderings(of: provider) {
            XCTAssertFalse(text.contains(Self.key), "\(how) printed the key: \(text)")
            XCTAssertFalse(text.contains("in-the-user-info"), "\(how) printed the user info: \(text)")
            XCTAssertFalse(text.contains("in-the-query"), "\(how) printed the query: \(text)")
            XCTAssertTrue(text.contains("<redacted>"), "\(how): \(text)")
            XCTAssertTrue(text.contains("127.0.0.1:49333/v1"), "\(how): \(text)")
        }
        XCTAssertEqual(
            "\(provider)", "OpenAICompatibleProvider(baseURL: http://127.0.0.1:49333/v1, apiKey: <redacted>)")
        XCTAssertEqual(
            "\(OpenAICompatibleProvider(baseURL: url))",
            "OpenAICompatibleProvider(baseURL: http://127.0.0.1:49333/v1, apiKey: none)")
    }
}
