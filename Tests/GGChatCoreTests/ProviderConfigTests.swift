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
        let ticket = "pipeabcdefghijklmnop"
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
}
