import GGChatCore
import XCTest

@testable import GGChatUI

/// What the Draw control's menu lists, and what the control says of the
/// image model that draws.
@MainActor
final class ImageModelMenuTests: XCTestCase {
    private typealias Choice = ImageModelChoiceTests

    private func row(
        _ model: UInt64?, _ title: String, _ detail: String?, enabled: Bool = true, checked: Bool = false
    ) -> DrawMenu.Row {
        DrawMenu.Row(model: model, title: title, detail: detail, enabled: enabled, checked: checked)
    }

    /// The contract's example: "Default" first, naming the model the Mac's
    /// own rule picks and ticked while none is chosen, then each model in
    /// the order given, with its family, "loaded" for the one loaded now,
    /// and for one that lacks a file what it lacks, dimmed.
    func testTheMenuListsTheDefaultThenEachModelInTheOrderGiven() throws {
        let drawing = try JSONDecoder().decode(
            Drawing.self, from: Data(contentsOf: try XCTUnwrap(Self.contractAnswer)))
        let menu = DrawMenu(drawing, chosen: nil)
        XCTAssertEqual(
            menu.rows,
            [
                row(nil, "Default (flux1-schnell-q8_0)", nil, checked: true),
                row(3, "flux1-schnell-q8_0", "Flux.1 \u{B7} loaded"),
                row(7, "qwen_image_2.1-Q8_0", "Qwen-Image 2.1 \u{B7} missing LLM", enabled: false),
            ])
        XCTAssertEqual(menu.rows.map(\.id), ["default", "3", "7"])
        XCTAssertEqual(menu.drawsWith, "flux1-schnell-q8_0")
        XCTAssertTrue(menu.isOffered)

        let chosen = DrawMenu(Choice.lists, chosen: 7)
        XCTAssertEqual(chosen.rows.map(\.checked), [false, false, true, false])
        XCTAssertEqual(chosen.rows.map(\.enabled), [true, true, true, false])
        XCTAssertEqual(chosen.rows.last?.detail, "SDXL \u{B7} missing VAE")
        XCTAssertEqual(chosen.drawsWith, "qwen_image_2.1-Q8_0")
    }

    /// The fixture the core tests read, found beside this file's package.
    private static var contractAnswer: URL? {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "GGChatCoreTests/Fixtures/contract-images-drawing-models.json")
    }

    /// There is a menu only where there is a choice to make or one to undo.
    /// A Mac from before the list, one not heard from, one with no image
    /// model and one with a single model have none, and the control is the
    /// plain switch. A chat that holds a choice has one whatever is listed,
    /// so the choice can be put back to the default; a choice the list does
    /// not have ticks no row and names no model.
    func testThereIsAMenuOnlyWhereThereIsAChoice() {
        let one = Drawing(available: true, model: Choice.flux.name, modelID: 3, models: [Choice.flux])
        let empty = Drawing(available: false, code: "drawing_unavailable", reason: "no image model", models: [])
        for drawing in [nil, Choice.older, empty, one] {
            XCTAssertEqual(DrawMenu(drawing, chosen: nil), .none)
            XCTAssertFalse(DrawMenu(drawing, chosen: nil).isOffered)
        }
        XCTAssertEqual(DrawMenu(nil, chosen: 7), .none)
        XCTAssertEqual(DrawMenu(Choice.older, chosen: 7), .none, "a Mac from before the list was given a menu")

        let stale = DrawMenu(one, chosen: 7)
        XCTAssertEqual(
            stale.rows,
            [row(nil, "Default (flux1-schnell-q8_0)", nil), row(3, "flux1-schnell-q8_0", "Flux.1 \u{B7} loaded")])
        XCTAssertNil(stale.drawsWith)
        XCTAssertEqual(DrawMenu(empty, chosen: 7).rows, [row(nil, "Default", nil)])

        let plain = ImageModelRow(id: 5, name: "odd", family: "", complete: false)
        XCTAssertEqual(DrawMenu.detail(of: plain), "missing a file")
        XCTAssertNil(DrawMenu.detail(of: ImageModelRow(id: 5, name: "odd", family: "")))
        XCTAssertEqual(DrawMenu.detail(of: ImageModelRow(id: 5, name: "odd", family: "wan-3")), "wan-3")
    }

    /// A Mac with several image models and no default has no "Default"
    /// row while nothing is chosen, since it would name no model; with a
    /// choice made the row is back, to undo it. The control then waits for
    /// a choice: it is off and not unavailable, and a press opens the
    /// models. Over the field, a line names the model while Draw is on.
    func testWithNoDefaultTheMenuListsOnlyTheModelsAndTheControlOpensIt() {
        let flux = ImageModelRow(id: 3, name: "flux1-schnell-q8_0", family: "flux1")
        let unpicked = Drawing(
            available: false, code: "drawing_unavailable", reason: "several and no default",
            models: [flux, Choice.qwen])
        XCTAssertEqual(
            DrawMenu(unpicked, chosen: nil).rows,
            [row(3, "flux1-schnell-q8_0", "Flux.1"), row(7, "qwen_image_2.1-Q8_0", "Qwen-Image 2.1")])
        XCTAssertNil(DrawMenu(unpicked, chosen: nil).drawsWith)
        XCTAssertEqual(DrawMenu(unpicked, chosen: 7).rows.map(\.title).first, "Default")
        XCTAssertEqual(DrawMenu(unpicked, chosen: 7).rows.map(\.checked), [false, false, true])

        XCTAssertEqual(DrawToggle.value(isOn: false, refusal: "no", choosing: true), "Off, no image model chosen")
        XCTAssertEqual(DrawToggle.value(isOn: true, refusal: "no", choosing: true), "Off, no image model chosen")
        XCTAssertEqual(
            DrawToggle.hint(refusal: "no", hasMenu: true, choosing: true), "Opens the image models to choose from")
        XCTAssertEqual(DrawToggle.hint(refusal: "no", hasMenu: true), "no. Hold to choose the image model.")

        XCTAssertEqual(DrawsWithLine.line(shown: true, model: "flux"), "Drawing with flux")
        XCTAssertNil(DrawsWithLine.line(shown: false, model: "flux"), "a line was shown with Draw off")
        XCTAssertNil(DrawsWithLine.line(shown: true, model: nil))
        XCTAssertNil(DrawsWithLine.line(shown: true, model: ""))
    }

    /// With a menu, VoiceOver hears the image model that draws after the
    /// state, and that holding the control opens the choice; without one
    /// the control says what it always said.
    func testTheControlSaysWhichModelDraws() {
        XCTAssertEqual(DrawToggle.value(isOn: true, refusal: nil, drawsWith: "flux"), "On, draws with flux")
        XCTAssertEqual(DrawToggle.value(isOn: false, refusal: nil, drawsWith: "flux"), "Off, draws with flux")
        XCTAssertEqual(DrawToggle.value(isOn: true, refusal: "no", drawsWith: nil), "Unavailable")
        XCTAssertEqual(DrawToggle.value(isOn: false, refusal: nil), "Off")
        XCTAssertEqual(DrawToggle.hint(refusal: nil, hasMenu: false), "Asks for a picture with this message")
        XCTAssertEqual(
            DrawToggle.hint(refusal: nil, hasMenu: true),
            "Asks for a picture with this message. Hold to choose the image model.")
        XCTAssertEqual(DrawToggle.hint(refusal: "home cannot draw: no", hasMenu: false), "home cannot draw: no")
        XCTAssertEqual(
            DrawToggle.hint(refusal: "Pick another from the Draw menu.", hasMenu: true),
            "Pick another from the Draw menu. Hold to choose the image model.")
    }
}
