import GGChatCore
import XCTest

@testable import GGChatUI

/// Whether a hub can draw is asked of it, when a chat opens on it and when
/// its pipe comes up, and what it says is what greys the Draw switch.
@MainActor
final class DrawingAvailabilityTests: XCTestCase {
    private func until(_ what: String, _ condition: () -> Bool) async throws {
        try await AppModelRunTests.until(what, condition)
    }

    /// A paired Mac is asked once its pipe is up, and each answer has its
    /// sentence: nothing when it can draw, gglib's reason when it cannot,
    /// and one for a gglib from before drawing, which gives none.
    func testAHubIsAskedWhetherItCanDrawAndItsAnswerIsTheReason() async throws {
        let hub = FakeRunHub(frames: [])
        hub.with { $0.drawing = .success(Drawing(available: true, model: "flux-dev")) }
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub)
        let conversation = try XCTUnwrap(model.selectedConversation)
        XCTAssertTrue(model.offersDrawing(for: conversation))
        XCTAssertEqual(model.drawRefusal(for: conversation), "It is not known yet whether home can draw.")

        await model.open(config).value
        XCTAssertEqual(hub.with(\.drawingAsked), 1)
        XCTAssertNil(model.drawRefusal(for: conversation))

        hub.with {
            $0.drawing = .success(
                Drawing(available: false, code: "drawing_unavailable", reason: "there is no image model"))
        }
        await model.open(config).value
        XCTAssertEqual(model.drawRefusal(for: conversation), "home cannot draw: there is no image model")

        hub.with { $0.drawing = .success(Drawing(available: false)) }
        await model.open(config).value
        XCTAssertEqual(model.drawRefusal(for: conversation), "The gglib on home needs updating before it can draw.")
        XCTAssertEqual(hub.with(\.drawingAsked), 3)
    }

    /// An ask that fails keeps what the hub said before, and a provider
    /// that is removed takes its answer with it.
    func testAnAskThatFailsKeepsTheAnswerBefore() async throws {
        let hub = FakeRunHub(frames: [])
        hub.with { $0.drawing = .success(Drawing(available: true, model: "flux-dev")) }
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub)
        await model.open(config).value
        XCTAssertNil(model.drawRefusal(on: config))

        hub.with { $0.drawing = .failure(.transport("the hub could not be reached")) }
        await model.open(config).value
        XCTAssertEqual(hub.with(\.drawingAsked), 2)
        XCTAssertNil(model.drawRefusal(on: config), "a failed ask forgot that the hub can draw")

        model.removeProvider(config.id)
        XCTAssertNil(model.drawings[config.id])
    }

    /// A server added by address that never answered as gglib has no Draw
    /// switch. One that did has it, dimmed, saying drawing needs a paired
    /// Mac whatever was once heard of it: gglib draws only for a device it
    /// has paired. Neither is ever asked.
    func testOnlyGGLibIsAskedAndOfferedTheSwitch() async throws {
        let hub = FakeRunHub(frames: [])
        hub.with { $0.drawing = .success(Drawing(available: true, model: "flux-dev")) }
        let (model, config) = try await AppModelRunTests.makeModel(behind: hub, direct: true)
        let conversation = try XCTUnwrap(model.selectedConversation)
        model.proxyStatusAvailability[config.id] = false
        await model.open(config).value
        XCTAssertFalse(model.offersDrawing(for: conversation))
        XCTAssertEqual(hub.with(\.drawingAsked), 0)

        model.proxyStatusAvailability[config.id] = true
        await model.open(config).value
        XCTAssertTrue(model.offersDrawing(for: conversation))
        XCTAssertEqual(hub.with(\.drawingAsked), 0, "a gglib reached by address was asked whether it can draw")
        XCTAssertEqual(model.drawRefusal(for: conversation), "Drawing needs a paired Mac.")
        model.drawings[config.id] = Drawing(available: true, model: "flux-dev")
        XCTAssertEqual(model.drawRefusal(for: conversation), "Drawing needs a paired Mac.")
    }

    /// The chat open on a Mac asks its Mac as it opens, and says the same
    /// sentences.
    func testAMacsChatSaysWhyItsMacCannotDraw() async throws {
        let hub = FakeChatsHub()
        hub.runs.with {
            $0.drawing = .success(
                Drawing(available: false, code: "drawing_unavailable", reason: "there is no image model"))
        }
        let (model, _) = try await HubChatContinueTests.opened(hub)
        try await until("the answer") { model.hubDrawRefusal == "home cannot draw: there is no image model" }
        hub.runs.with { $0.drawing = .success(Drawing(available: true, model: "flux-dev")) }
        await model.catchUp(try XCTUnwrap(model.openedHubChat).providerID, quietly: true)
        XCTAssertNil(model.hubDrawRefusal)
    }
}
