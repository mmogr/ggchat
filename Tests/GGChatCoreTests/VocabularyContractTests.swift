import XCTest

@testable import GGChatCore

/// Holds the words this app says gglib's states in to gglib's own. The file
/// is gglib's, `contracts/vocabulary/words.json`, copied here byte for byte
/// as `gglib-vocabulary-words.json` from gglib's main at ee456712. The file,
/// not this build, says what is right: a failure here is fixed in
/// `GGLibWords`, or in the file on both sides at once.
final class VocabularyContractTests: XCTestCase {
    /// One group of the file, as each state's word by its state.
    private func group(_ name: String) throws -> [String: String] {
        let file = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-vocabulary-words.json"))
        let rows = try XCTUnwrap((file as? [String: Any])?[name] as? [[String: String]], "the file has no \(name)")
        var words: [String: String] = [:]
        for row in rows {
            let state = try XCTUnwrap(row["state"], "\(name): a row with no state")
            XCTAssertNil(words[state], "\(name): \(state) is in the file twice")
            words[state] = try XCTUnwrap(row["word"], "\(name): \(state) has no word")
        }
        return words
    }

    /// Every residency and every reach gglib words is one here, with the
    /// same word, and there is none here that gglib does not word.
    func testEveryWordShownIsGGLibs() throws {
        let residency = try group("residency")
        XCTAssertEqual(Set(GGLibWords.Residency.allCases.map(\.rawValue)), Set(residency.keys))
        for state in GGLibWords.Residency.allCases {
            XCTAssertEqual(state.word, residency[state.rawValue], "residency \(state.rawValue)")
        }
        let reach = try group("reach")
        XCTAssertEqual(Set(GGLibWords.Reach.allCases.map(\.rawValue)), Set(reach.keys))
        for state in GGLibWords.Reach.allCases {
            XCTAssertEqual(state.word, reach[state.rawValue], "reach \(state.rawValue)")
        }
    }

    /// The away line is gglib's, with the reach's word in it: since a time
    /// when there is one, and without "since" when nobody knows.
    func testTheAwayLineIsGGLibs() {
        XCTAssertEqual(GGLibWords.awayLine("desk", since: "14:02"), "desk is away since 14:02. Your message will wait.")
        XCTAssertEqual(GGLibWords.awayLine("desk", since: nil), "desk is away. Your message will wait.")
        XCTAssertEqual(GGLibWords.loadItAgain, "Load it again")
    }
}
