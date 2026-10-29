import XCTest

@testable import GGChatCore

final class ProviderConfigTests: XCTestCase {
    func testURLProviderRoundTrips() throws {
        let config = ProviderConfig(
            name: "gglib on the Mac",
            kind: .openAICompatible(baseURL: URL(string: "http://127.0.0.1:8080/v1")!),
            defaultModel: "Qwen3.8-27B")
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(ProviderConfig.self, from: data), config)
        XCTAssertFalse(config.isPipe)
    }

    func testPipeProviderRoundTripsAndHoldsOnlyADigest() throws {
        // modelpipe's normative vector 1: a real ticket, so what is asserted
        // absent from the encoded config is a real ticket's worth of secret.
        let ticket = "pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na"
        let config = ProviderConfig(name: "home", kind: .pipe(ticketDigest: Ticket.digest(ticket)))
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(ProviderConfig.self, from: data), config)
        XCTAssertTrue(config.isPipe)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(ticket))
    }

    func testSecretsAreKeyedByProviderAndKind() throws {
        let secrets = InMemorySecrets()
        let id = UUID()
        try secrets.setSecret("k", .apiKey, for: id)
        try secrets.setSecret("t", .token, for: id)
        XCTAssertEqual(try secrets.secret(.apiKey, for: id), "k")
        XCTAssertEqual(try secrets.secret(.token, for: id), "t")
        XCTAssertNil(try secrets.secret(.ticket, for: id))
        XCTAssertNil(try secrets.secret(.apiKey, for: UUID()))
        try secrets.removeAll(for: id)
        XCTAssertNil(try secrets.secret(.apiKey, for: id))
    }

    // MARK: - What each kind is

    // Whether it has a session to bring up and tear down, whether it is a
    // paired Mac, and whether it is a pipe: one case per question per kind,
    // so a kind that is added answers each one here.

    private static let address = ProviderConfig(
        name: "gglib on the Mac", kind: .openAICompatible(baseURL: URL(string: "http://127.0.0.1:8080/v1")!))
    private static let pipe = ProviderConfig(
        name: "home",
        kind: .pipe(ticketDigest: Ticket.digest("pipeadlvvgabqkyqvn6vjp7nhslea45a5yls6pnkmizfv4bbu2hxa5iruaaauhlp2na")))

    /// A server by address is asked by its requests alone: nothing is
    /// dialled before one, waited for, or hung up after.
    func testAnAddressHasNoSession() {
        XCTAssertFalse(Self.address.hasSession)
    }

    /// A pipe is dialled before anything goes through it, a send waits for
    /// it, and it is hung up on the way to the background.
    func testAPipeHasASession() {
        XCTAssertTrue(Self.pipe.hasSession)
    }

    /// A server by address has no chats of its own to list, no runs a Mac
    /// keeps, and draws nothing: gglib keeps those for a device it paired.
    func testAnAddressIsNotAPairedMac() {
        XCTAssertFalse(Self.address.isPairedMac)
    }

    func testAPipeIsAPairedMac() {
        XCTAssertTrue(Self.pipe.isPairedMac)
    }

    func testAnAddressIsNotAPipe() {
        XCTAssertFalse(Self.address.isPipe)
    }

    func testAPipeIsAPipe() {
        XCTAssertTrue(Self.pipe.isPipe)
    }
}

final class BaseURLNormalizationTests: XCTestCase {
    func testBareHostGetsV1AndTrailingSlashIsDropped() {
        XCTAssertEqual(
            ProviderConfig.normalizedBaseURL(from: "http://127.0.0.1:8080")?.absoluteString, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(
            ProviderConfig.normalizedBaseURL(from: "http://127.0.0.1:8080/")?.absoluteString, "http://127.0.0.1:8080/v1"
        )
        XCTAssertEqual(
            ProviderConfig.normalizedBaseURL(from: " http://mac.local:8080/v1/ ")?.absoluteString,
            "http://mac.local:8080/v1")
        XCTAssertEqual(
            ProviderConfig.normalizedBaseURL(from: "HTTPS://api.example.com/openai/v1")?.absoluteString,
            "https://api.example.com/openai/v1")
    }

    func testNonHTTPOrHostlessIsRejectedAndSecretsAreStripped() {
        XCTAssertNil(ProviderConfig.normalizedBaseURL(from: "127.0.0.1:8080"))
        XCTAssertNil(ProviderConfig.normalizedBaseURL(from: "ftp://x"))
        XCTAssertNil(ProviderConfig.normalizedBaseURL(from: "http://"))
        XCTAssertNil(ProviderConfig.normalizedBaseURL(from: ""))
        XCTAssertEqual(ProviderConfig.normalizedBaseURL(from: "http://u:p@h/v1?k=1#f")?.absoluteString, "http://h/v1")
    }
}
