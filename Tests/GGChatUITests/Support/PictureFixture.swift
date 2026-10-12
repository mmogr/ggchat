import GGChatCore
import XCTest

@testable import GGChatUI

/// A Mac's chat that holds a picture its drawing tool made, open on a
/// phone that has read the picture and heard the Mac can draw.
@MainActor
enum PictureFixture {
    static let prompt = "a red fox in snow"
    static let can = Drawing(available: true, model: "flux-dev")

    /// A Mac that lists three image models: its default, another that can
    /// draw, and one that lacks a file.
    static let lists = Drawing(
        available: true, model: "flux-dev", modelID: 1,
        models: [
            ImageModelRow(id: 1, name: "flux-dev", family: "flux1", isDefault: true),
            ImageModelRow(id: 2, name: "z-image", family: "z-image"),
            ImageModelRow(id: 3, name: "sdxl-base", family: "sdxl", complete: false, missing: ["vae"]),
        ])

    /// The phone, the Mac behind it, and the chat's picture.
    struct Scene {
        let model: AppModel
        let hub: FakeChatsHub
        let config: ProviderConfig
        let picture: DraftImage
    }

    /// The picture: 64 by 32 pixels, a PNG.
    static func picture() throws -> DraftImage {
        try HubChatImageSendTests.image(width: 64)
    }

    /// Chat 12 with a question that carries `asked`, a reply that called
    /// the drawing tool, the tool's row with `drawn`, and the reply's words.
    static func chat(_ drawn: ImageRef, asked: ImageRef? = nil) -> HubChatOpen {
        let call = HubToolCall(id: "call-draw-1", name: HubToolCall.drawingTool, prompt: prompt)
        return HubChatOpen(
            conversation: FakeChatsHub.opened.conversation,
            messages: [
                HubMessage(
                    id: 50, conversationID: 12, role: "user", content: "Draw a fox.", createdAt: "a",
                    images: asked.map { [$0] }),
                HubMessage(
                    id: 51, conversationID: 12, role: "assistant", content: "", createdAt: "b",
                    metadata: HubMessageMetadata(toolCalls: [call])),
                HubMessage(
                    id: 52, conversationID: 12, role: "tool", content: "Drew 1 image.", createdAt: "c",
                    metadata: HubMessageMetadata(toolCallID: call.id), images: [drawn]),
                HubMessage(id: 53, conversationID: 12, role: "assistant", content: "Here is a fox.", createdAt: "d"),
            ])
    }

    /// The chat open behind a Mac that says `drawing` of itself, its
    /// picture read into memory.
    static func opened(
        _ drawing: Drawing = can, asked: DraftImage? = nil, store: any Store = InMemoryStore()
    ) async throws -> Scene {
        let picture = try picture()
        let hub = FakeChatsHub()
        hub.with { state in
            state.chats[12] = chat(picture.ref, asked: asked?.ref)
            state.images[picture.id] = picture.data
            if let asked { state.images[asked.id] = asked.data }
        }
        hub.runs.with { $0.drawing = .success(drawing) }
        let (model, config) = try await HubChatContinueTests.opened(hub, store: store)
        try await AppModelRunTests.until("the ask") {
            hub.runs.with(\.drawingAsked) > 0 && model.opening[config.id] == nil
        }
        await model.catchUp(config.id, quietly: true)
        await model.fetchHubImage(picture.ref)
        return Scene(model: model, hub: hub, config: config, picture: picture)
    }

    /// The editor's state for the chat's picture.
    static func editing(_ model: AppModel, _ picture: DraftImage) throws -> PictureEditing {
        try XCTUnwrap(model.pictureEditing(of: picture.ref, in: nil, fromHub: true))
    }

    /// One pass of the brush across the picture's top left.
    static func brush(_ editing: PictureEditing) {
        editing.begin(at: CGPoint(x: 8, y: 8))
        editing.extend(to: CGPoint(x: 24, y: 8))
    }
}
