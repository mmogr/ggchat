import Foundation
import XCTest

@testable import GGChatCore

/// The image models a hub lists, and the choice among them a message that
/// draws carries, as this device reads and writes them. gglib's recorded
/// answers are `contracts/images/drawing.json` there, copied here byte for
/// byte as `gglib-images-drawing.json` from gglib's main at ee456712.
final class ImageModelWireTests: XCTestCase {
    private func answer(_ body: String) throws -> Drawing {
        try JSONDecoder().decode(Drawing.self, from: Data(body.utf8))
    }

    /// gglib's recorded answers, by the name it records each under.
    private func recorded() throws -> [String: Drawing] {
        try JSONDecoder().decode([String: Drawing].self, from: try Fixtures.data("gglib-images-drawing.json"))
    }

    /// Every answer gglib records reads, the models in the order given,
    /// each with its family, whether it is complete, what it lacks, whether
    /// it is the default and whether it is loaded. With no model named the
    /// default draws; one named draws itself; a named one that lacks files
    /// and one that is gone are those faults; several complete models and
    /// no default wait for a choice.
    func testTheContractsAnswerListsTheImageModelsInOrder() throws {
        let answers = try recorded()
        XCTAssertEqual(
            answers.keys.sorted(),
            ["chosen", "chosen_gone", "chosen_incomplete", "several_and_no_default", "unnamed"])
        let flux = ImageModelRow(
            id: 2, name: "flux", family: "flux1", complete: false, missing: ["vae", "clip_l", "t5xxl"])
        let sdxl = ImageModelRow(id: 1, name: "sdxl", family: "sdxl", resident: true)
        let turbo = ImageModelRow(id: 4, name: "sdxl-turbo", family: "sdxl", isDefault: true)
        let listed = [flux, sdxl, turbo]

        let unnamed = try XCTUnwrap(answers["unnamed"])
        XCTAssertEqual(unnamed, Drawing(available: true, model: "sdxl-turbo", modelID: 4, models: listed))
        XCTAssertTrue(unnamed.takesImageModel)
        XCTAssertEqual(unnamed.defaultImageModel, turbo)
        XCTAssertEqual(unnamed.models?.map(\.familyLabel), ["Flux.1", "SDXL", "SDXL"])
        XCTAssertEqual(unnamed.models?.map(\.missingLabels), [["VAE", "CLIP-L", "T5-XXL"], [], []])
        XCTAssertFalse(unnamed.awaitsImageChoice)

        let chosen = try XCTUnwrap(answers["chosen"])
        XCTAssertEqual(chosen, Drawing(available: true, model: "sdxl", modelID: 1, models: listed))
        XCTAssertNil(chosen.fault(ofChoice: 1))
        XCTAssertEqual(chosen.imageModel(1), sdxl)

        let incomplete = try XCTUnwrap(answers["chosen_incomplete"])
        XCTAssertFalse(incomplete.available)
        XCTAssertEqual(incomplete.code, "image_model_incomplete")
        XCTAssertEqual(incomplete.fault(ofChoice: 2), .incomplete(flux))

        let gone = try XCTUnwrap(answers["chosen_gone"])
        XCTAssertEqual(gone.code, "model_not_found")
        XCTAssertEqual(gone.fault(ofChoice: 99), .gone)

        let several = try XCTUnwrap(answers["several_and_no_default"])
        XCTAssertEqual(several.code, "drawing_unavailable")
        XCTAssertNil(several.defaultImageModel)
        XCTAssertTrue(several.awaitsImageChoice)
    }

    /// A turn to a Mac's chat that draws with a chosen image model reads as
    /// gglib records it (`image_model_turn` in `gglib-chats-recorded.json`)
    /// and is sent as exactly that body: `draw` and the model's id beside
    /// the text.
    func testATurnThatDrawsWithAChosenModelIsTheRecordedBody() throws {
        let file = try JSONSerialization.jsonObject(with: try Fixtures.data("gglib-chats-recorded.json"))
        let body = try XCTUnwrap((file as? [String: Any])?["image_model_turn"] as? [String: Any])
        let turn = HubTurn(conversationID: 12, content: "Draw a red dot.", draw: true, imageModel: 7)
        let data = try JSONSerialization.data(withJSONObject: body)
        XCTAssertEqual(try JSONDecoder().decode(HubTurn.self, from: data), turn)
        let sent = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(turn)) as? [String: Any]
        XCTAssertEqual(sent.map { $0 as NSDictionary }, body as NSDictionary)
    }

    /// An answer with no `models` is a gglib from before the list: it
    /// still reads, it lists nothing, it is not one to send `image_model`
    /// to, and no choice is judged by it. An empty list is a gglib that has
    /// the list and no image model, which takes the word.
    func testAnAnswerWithoutTheListIsAnOlderGGLibAndAnEmptyListIsNot() throws {
        let older = try answer(#"{"available":true,"model":"flux-dev"}"#)
        XCTAssertEqual(older, Drawing(available: true, model: "flux-dev"))
        XCTAssertNil(older.models)
        XCTAssertNil(older.modelID)
        XCTAssertFalse(older.takesImageModel)
        XCTAssertNil(older.fault(ofChoice: 3), "a choice was judged by a list that was never sent")

        let none = try answer(
            #"{"available":false,"code":"drawing_unavailable","reason":"there is no image model","models":[]}"#)
        XCTAssertEqual(none.models, [])
        XCTAssertTrue(none.takesImageModel)
        XCTAssertNil(none.defaultImageModel)
        XCTAssertEqual(none.fault(ofChoice: 3), .gone)
    }

    /// A hub waits for a choice when it cannot draw, marks no default and
    /// lists two or more image models with all their files. One that can
    /// draw, one with a default, one with a single complete model and one
    /// from before the list do not: a choice is not what they lack.
    func testAHubAwaitsAChoiceWithSeveralCompleteModelsAndNoDefault() {
        let flux = ImageModelRow(id: 3, name: "flux", family: "flux1")
        let zimage = ImageModelRow(id: 4, name: "z-image", family: "z-image")
        let broken = ImageModelRow(id: 9, name: "sdxl", family: "sdxl", complete: false, missing: ["vae"])
        let marked = ImageModelRow(id: 3, name: "flux", family: "flux1", isDefault: true)
        func refused(_ models: [ImageModelRow]?) -> Drawing {
            Drawing(available: false, code: "drawing_unavailable", reason: "no", models: models)
        }
        XCTAssertTrue(refused([flux, zimage]).awaitsImageChoice)
        XCTAssertTrue(refused([flux, broken, zimage]).awaitsImageChoice)
        XCTAssertFalse(refused([flux, broken]).awaitsImageChoice, "one complete model is no choice")
        XCTAssertFalse(refused([marked, zimage]).awaitsImageChoice, "a hub with a default lacks something else")
        XCTAssertFalse(refused([]).awaitsImageChoice)
        XCTAssertFalse(refused(nil).awaitsImageChoice, "a hub from before the list takes no choice")
        XCTAssertFalse(Drawing(available: true, model: "flux", modelID: 3, models: [flux, zimage]).awaitsImageChoice)
    }

    /// A family or a role this build has not heard of reads as the string
    /// it came as and is shown so; the whole answer still reads. A row with
    /// only what it must have reads too, with nothing missing, not the
    /// default and not loaded.
    func testAFamilyOrARoleThisBuildDoesNotKnowStillReads() throws {
        let body = #"""
            {"available":true,"model":"a","model_id":1,"models":[
              {"id":1,"name":"a","family":"sdxl","complete":true,"missing":[],"default":true,"resident":false},
              {"id":2,"name":"b","family":"wan-3","complete":false,"missing":["vae","clip_l","t5xxl","unet_x"],
               "default":false,"resident":false,"last_render":{"ms":1}},
              {"id":18446744073709551615,"name":"c","complete":true}
            ]}
            """#
        let rows = try XCTUnwrap(try answer(body).models)
        XCTAssertEqual(rows.map(\.family), ["sdxl", "wan-3", ""])
        XCTAssertEqual(rows.map(\.familyLabel), ["SDXL", "wan-3", ""])
        XCTAssertEqual(rows[1].missing, ["vae", "clip_l", "t5xxl", "unet_x"])
        XCTAssertEqual(rows[1].missingLabels, ["VAE", "CLIP-L", "T5-XXL", "unet_x"])
        XCTAssertEqual(rows[2], ImageModelRow(id: .max, name: "c", family: ""))
    }

    /// Every family gglib names reads in gglib's words (`ImageFamily::label`),
    /// and one it does not name stays the string it came as.
    func testEveryFamilyGGLibNamesReadsInItsWords() {
        let families = [
            "flux1", "sdxl", "qwen-image-2.1", "z-image", "flux3-klein", "flux2-klein", "wan-3",
        ]
        let labels = families.map { ImageModelRow(id: 1, name: "m", family: $0).familyLabel }
        XCTAssertEqual(
            labels,
            ["Flux.1", "SDXL", "Qwen-Image 2.1", "Z-Image", "FLUX 3 Klein", "FLUX.2 klein", "wan-3"])
    }

    /// The question can name an image model, `?image_model=<id>`, and the
    /// answer is then gglib's judgement of a message that names it. With
    /// none the request has no query, as it always had.
    func testTheQuestionCanNameAnImageModelToBeJudged() async throws {
        let path = "/v1/gglib/images/drawing"
        let refusal =
            #"{"available":false,"code":"image_model_incomplete","reason":"qwen lacks its llm","models":[]}"#
        ChatsHub.serve(.init(body: refusal), at: path, on: "judged.drawing.test")
        let hub = ChatsHub.provider(at: "judged.drawing.test")
        let judged = try await hub.drawing(judging: 7)
        XCTAssertEqual(judged.code, "image_model_incomplete")
        XCTAssertEqual(judged.reason, "qwen lacks its llm")
        _ = try await hub.drawing()
        let asked = ChatsHub.requests(at: "judged.drawing.test")
        XCTAssertEqual(asked.map { $0.url?.path() }, [path, path])
        XCTAssertEqual(asked.map { $0.url?.query() }, ["image_model=7", nil])
    }

    /// A turn says `image_model` only when it draws and a model is chosen:
    /// gglib refuses the key without `draw`, and a gglib from before it
    /// refuses the key outright, so a turn with none is the body it always
    /// was.
    func testATurnNamesItsImageModelOnlyWhenItDraws() throws {
        func sent(_ turn: HubTurn) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(turn)) as? [String: Any])
        }
        let chosen = HubTurn(conversationID: 12, content: "a fox in snow", draw: true, imageModel: 7)
        XCTAssertEqual(try sent(chosen).keys.sorted(), ["content", "conversation_id", "draw", "image_model"])
        XCTAssertEqual(try sent(chosen)["image_model"] as? UInt64, 7)
        let unchosen = HubTurn(conversationID: 12, content: "a fox in snow", draw: true)
        XCTAssertEqual(try sent(unchosen).keys.sorted(), ["content", "conversation_id", "draw"])
        let plain = HubTurn(conversationID: 12, content: "a fox in snow", imageModel: 7)
        XCTAssertEqual(
            try sent(plain).keys.sorted(), ["content", "conversation_id"],
            "a turn that does not draw named an image model")

        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(HubTurn.self, from: try JSONEncoder().encode(chosen)), chosen)
        XCTAssertNotEqual(chosen, unchosen)
        let body = Data(#"{"conversation_id":12,"content":"a fox in snow","draw":true,"image_model":7}"#.utf8)
        XCTAssertEqual(try decoder.decode(HubTurn.self, from: body), chosen)
    }

    /// A run that draws with a chosen image model adds `image_model=<id>`
    /// to its query, after `draw=true`; one that draws with none has the
    /// three words it had; and one that does not draw has no query, chosen
    /// model or not. The body is the same in all of them.
    func testARunNamesItsImageModelInItsQueryOnlyWhenItDraws() async throws {
        func request(draws: Bool, chosen: UInt64?) -> ChatRequest {
            ChatRequest(
                model: "Qwen3.8-27B",
                messages: [Message(role: .user, content: "a fox in snow", createdAt: Date(timeIntervalSince1970: 0))],
                returnProgress: true, draws: draws, imageModelID: chosen)
        }
        var script = RunHub.Script(frames: [], ending: RunHub.report("run-m", "completed", lastSeq: 0))
        script.put = (201, RunHub.report("run-m", "queued", lastSeq: 0))
        var queries: [String?] = []
        for (host, draws, chosen) in [
            ("chosen.model.test", true, UInt64(7)), ("unchosen.model.test", true, nil),
            ("plain.model.test", false, UInt64(7)),
        ] {
            RunHub.serve(script, at: host)
            _ = try await RunHub.provider(at: host).startRun(id: "run-m", request(draws: draws, chosen: chosen))
            queries.append(try XCTUnwrap(RunHub.requests(at: host).first).url?.query())
        }
        XCTAssertEqual(
            queries, ["kind=chat&tools=none&draw=true&image_model=7", "kind=chat&tools=none&draw=true", nil])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let body = try encoder.encode(try ChatCompletionRequest(request(draws: false, chosen: nil)))
        XCTAssertEqual(try encoder.encode(try ChatCompletionRequest(request(draws: true, chosen: 7))), body)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("image_model"))
    }
}
