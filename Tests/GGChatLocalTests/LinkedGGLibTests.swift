import Foundation
import GGChatCore
import GGChatLocal
import XCTest

/// That gglib's framework is really linked, and is the one the vendored
/// binding was generated for.
///
/// The framework is a binary taken from a gglib release, and uniffi checks
/// it against the vendored Swift only at the first call, where a mismatch is
/// a trap rather than a build error. So a call has to cross into it on every
/// CI run, through the real framework on the Mac's slice, and this is it.
final class LinkedGGLibTests: XCTestCase {
    /// What the release's swift archive says the framework reports, under
    /// `build_info()`'s own field names.
    private struct Named: Decodable {
        let gglibVersion: String
        let uniffiVersion: String
        let llamaPin: String
    }

    /// `binding.json`, vendored beside the Swift it describes.
    private static var vendoredBinding: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/GGLib/binding.json")
    }

    /// `build_info()` answers, through the framework, what the vendored
    /// binding says it should: the gglib, the uniffi and the llama.cpp pin
    /// it was taken with, each in its own field.
    func testTheLinkedFrameworkIsTheOneTheVendoredBindingNames() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let named = try decoder.decode(Named.self, from: Data(contentsOf: Self.vendoredBinding))

        XCTAssertEqual(
            GGLibBuild.linked(),
            GGLibBuild(gglibVersion: named.gglibVersion, uniffiVersion: named.uniffiVersion, llamaPin: named.llamaPin))
    }
}
