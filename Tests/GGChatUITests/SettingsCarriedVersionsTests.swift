import GGChatCore
import GGChatLocal
import XCTest

@testable import GGChatUI

/// Settings' line naming the gglib and the llama.cpp this build carries.
final class SettingsCarriedVersionsTests: XCTestCase {
    /// gglib's version and then llama.cpp's pin, a middle dot between them;
    /// the uniffi version is the binding's business and is not shown.
    @MainActor
    func testTheLineNamesGglibsVersionAndTheLlamaCppPin() {
        let build = GGLibBuild(gglibVersion: "0.28.0-rc.2", uniffiVersion: "0.32.2", llamaPin: "b11669")
        XCTAssertEqual(SettingsView.carriedLine(build), "gglib 0.28.0-rc.2 \u{B7} llama.cpp b11669")
    }

    /// The row reads the framework the app links, so a new gglib taken is a
    /// new line with nothing here to edit.
    @MainActor
    func testTheRowReadsTheLinkedFramework() {
        XCTAssertEqual(SettingsView.carried, GGLibBuild.linked())
    }
}
