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

/// Settings' line naming the gglib a server runs: there once its model list
/// said so, and not for a server whose list said nothing.
@MainActor
final class SettingsServerVersionsTests: XCTestCase {
    func testALineNamesTheGGLibEachServerSaidItRuns() async throws {
        let registry = LoopbackProviderRegistry()
        let deskURL = URL(string: "http://127.0.0.1:49990/v1")!
        let otherURL = URL(string: "http://127.0.0.1:49991/v1")!
        registry.register(MockProvider(gglib: .serving("0.35.0")), at: deskURL)
        registry.register(MockProvider(), at: otherURL)
        let defaults = UserDefaults(suiteName: "SettingsServerVersionsTests.\(UUID().uuidString)")!
        let model = AppModel(
            store: InMemoryStore(), secrets: InMemorySecrets(), log: NoopLogSink(), registry: registry,
            pipeConnector: MockPipeConnector(sleeper: ImmediateSleeper(), registry: registry),
            diagnostics: Diagnostics(defaults: defaults), now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let desk = ProviderConfig(name: "desk", kind: .openAICompatible(baseURL: deskURL))
        let other = ProviderConfig(name: "other", kind: .openAICompatible(baseURL: otherURL))
        try model.addProvider(desk, credentials: [:])
        try model.addProvider(other, credentials: [:])
        XCTAssertEqual(model.serverGGLibLines, [], "a line before any list was read")

        await model.refreshModels(for: desk)
        await model.refreshModels(for: other)
        XCTAssertEqual(model.serverGGLibLines, ["desk runs gglib 0.35.0"])
    }
}
