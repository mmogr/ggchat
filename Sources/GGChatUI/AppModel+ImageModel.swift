import Foundation
import GGChatCore

// Which image model draws, for each kind of chat (ADR 0011). A hub whose
// answer about drawing lists its image models can be told which to draw
// with, beside `draw`. The choice is the chat's and is said with every
// message that draws: gglib keeps no such choice. A conversation kept here
// stores it; a Mac's chat holds it in memory with the chat open. A hub from
// before the list is never told, since it refuses a key it does not know.

/// Why a message cannot be drawn now.
enum DrawVerdict: Equatable {
    /// The hub cannot draw whatever is chosen, or has not said.
    case hub(String)
    /// The hub cannot draw with the image model the chat chose. It is never
    /// drawn with another in its place: another is picked on the line over
    /// the field, which says so.
    case choice(String)
    /// The hub cannot draw until an image model is chosen, and none is: it
    /// lists several that can draw and no default
    /// (`Drawing.awaitsImageChoice`). The line over the field then asks.
    case undecided(String)

    var sentence: String {
        switch self {
        case .hub(let why), .choice(let why), .undecided(let why): why
        }
    }
}

extension AppModel {
    /// The codes gglib refuses a named image model with: it is gone, it is
    /// no image model, or it lacks a file.
    static let choiceRefusals: Set<String> = [
        ProviderError.Code.modelNotFound.rawValue, ProviderError.Code.notAnImageModel.rawValue,
        ProviderError.Code.imageModelIncomplete.rawValue,
    ]

    /// The image model a message to `config`'s hub names: the chat's
    /// choice, for a hub whose answer about drawing listed its image
    /// models, and none for any other. The choice goes as it is, even one
    /// the list no longer has: the hub then refuses with its reason.
    func imageModelToSend(_ chosen: UInt64?, to config: ProviderConfig) -> UInt64? {
        guard drawings[config.id]?.takesImageModel == true else { return nil }
        return chosen
    }

    /// Why a message that names `chosen` cannot be drawn on `config`'s
    /// machine now, or nil when it can. With none chosen, or a hub that
    /// lists no image models, it is what the hub said of itself
    /// (`drawRefusal(on:)`). With one chosen it is what the hub said of a
    /// message naming it, once asked, and until then what its list says of
    /// that model: one listed with all its files can draw where the hub
    /// refused only for want of a choice.
    func drawVerdict(on config: ProviderConfig, choosing chosen: UInt64?) -> DrawVerdict? {
        guard let listed = drawings[config.id], let chosen, listed.takesImageModel else {
            let undecided = chosen == nil && drawings[config.id]?.awaitsImageChoice == true
            return drawRefusal(on: config).map(undecided ? DrawVerdict.undecided : DrawVerdict.hub)
        }
        if let judged = imageChoiceAnswers[config.id]?[chosen] {
            if judged.available { return nil }
            let reason = judged.reason ?? "it gave no reason"
            guard Self.choiceRefusals.contains(judged.code ?? "") else {
                return .hub("\(config.name) cannot draw: \(reason)")
            }
            let name = listed.imageModel(chosen)?.name ?? "the image model this chat chose"
            return .choice("\(config.name) cannot draw with \(name): \(reason)")
        }
        switch listed.fault(ofChoice: chosen) {
        case .gone:
            return .choice(
                "\(config.name) no longer has the image model this chat draws with. Pick another image model.")
        case .incomplete(let row):
            let lacks = row.missingLabels.isEmpty ? "a file it needs" : row.missingLabels.formatted(.list(type: .and))
            return .choice("\(row.name) is missing \(lacks) on \(config.name). Pick another image model.")
        case nil:
            // The hub's own refusal was for want of a choice, and this is
            // one its list has with all its files.
            if listed.awaitsImageChoice { return nil }
            return drawRefusal(on: config).map(DrawVerdict.hub)
        }
    }

    /// Whether the conversation's hub cannot draw at all, whatever image
    /// model is chosen: then a question stops asking for its picture.
    func hubCannotDraw(for conversation: Conversation) -> Bool {
        guard let config = provider(for: conversation), config.isPipe else { return true }
        if case .choice = drawVerdict(on: config, choosing: conversation.imageModelID) { return false }
        return drawRefusal(for: conversation) != nil
    }

    /// Whether `chosen` can be picked on `config`'s hub: no model, which is
    /// the hub's own pick, or one its list has with all its files.
    func admitsImageChoice(_ chosen: UInt64?, on config: ProviderConfig) -> Bool {
        guard let chosen else { return true }
        return drawings[config.id]?.imageModel(chosen)?.complete == true
    }

    /// The name of the image model a message to `config`'s hub is drawn
    /// with: the one chosen, where the hub takes a choice and lists it, or
    /// else the one the hub said draws. Nil when neither is known.
    func drawsWith(on config: ProviderConfig, choosing chosen: UInt64?) -> String? {
        guard let answer = drawings[config.id] else { return nil }
        guard let chosen, answer.takesImageModel else { return answer.available ? answer.model : nil }
        return answer.imageModel(chosen)?.name
    }

    // MARK: - A conversation kept here

    /// Whether the line over the conversation's field asks for an image
    /// model, there being nothing to draw with until one is chosen.
    public func drawAwaitsChoice(for conversation: Conversation) -> Bool {
        guard let config = provider(for: conversation), config.isPipe else { return false }
        if case .undecided = drawVerdict(on: config, choosing: conversation.imageModelID) { return true }
        return false
    }

    /// Whether the conversation's choice of image model is one its Mac
    /// cannot draw with, so that the line over the field says so and
    /// offers another.
    public func drawChoiceRefused(for conversation: Conversation) -> Bool {
        guard let config = provider(for: conversation), config.isPipe else { return false }
        if case .choice = drawVerdict(on: config, choosing: conversation.imageModelID) { return true }
        return false
    }

    /// The image model the conversation's next picture is drawn with.
    public func drawsWith(for conversation: Conversation) -> String? {
        guard let config = provider(for: conversation), config.isPipe else { return nil }
        return drawsWith(on: config, choosing: conversation.imageModelID)
    }

    /// The image-model menu over the field for the conversation: none unless its
    /// provider is a paired Mac that lists its image models.
    public func drawMenu(for conversation: Conversation) -> DrawMenu {
        guard let config = provider(for: conversation), config.isPipe else { return .none }
        return DrawMenu(drawings[config.id], chosen: conversation.imageModelID)
    }

    /// Sets the image model the conversation's pictures are drawn with,
    /// from its next message that draws on; nil is the hub's own pick. One
    /// the hub's list does not have complete is not taken. The hub is then
    /// asked about a message that names it. Fetched again by id and
    /// `updatedAt` left alone, for `setSystemPrompt`'s reasons.
    @discardableResult
    public func setImageModel(_ chosen: UInt64?, for conversationID: UUID) -> Task<Void, Never>? {
        guard var conversation = conversations.first(where: { $0.id == conversationID }),
            let config = provider(for: conversation), admitsImageChoice(chosen, on: config)
        else { return nil }
        if conversation.imageModelID != chosen {
            conversation.imageModelID = chosen
            update(conversation)
        }
        return judge(chosen, on: config)
    }

    // MARK: - A Mac's chat

    /// The image-model menu over the field for the chat open.
    public var hubDrawMenu: DrawMenu {
        guard let open = openedHubChat else { return .none }
        return DrawMenu(drawings[open.providerID], chosen: open.imageModel)
    }

    /// Whether the line over the open chat's field asks for an image
    /// model, as `drawAwaitsChoice(for:)`.
    public var hubDrawAwaitsChoice: Bool {
        guard let open = openedHubChat, let config = providers.first(where: { $0.id == open.providerID }) else {
            return false
        }
        if case .undecided = drawVerdict(on: config, choosing: open.imageModel) { return true }
        return false
    }

    /// Whether the open chat's choice of image model is one its Mac cannot
    /// draw with, as `drawChoiceRefused(for:)`.
    public var hubDrawChoiceRefused: Bool {
        guard let open = openedHubChat, let config = providers.first(where: { $0.id == open.providerID }) else {
            return false
        }
        if case .choice = drawVerdict(on: config, choosing: open.imageModel) { return true }
        return false
    }

    /// The image model the open chat's next picture is drawn with.
    public var hubDrawsWith: String? {
        guard let open = openedHubChat, let config = providers.first(where: { $0.id == open.providerID }) else {
            return nil
        }
        return drawsWith(on: config, choosing: open.imageModel)
    }

    /// Sets the image model of the chat open. It is held with the chat and
    /// nowhere else, and said with each of its messages that draws.
    @discardableResult
    public func setHubImageModel(_ chosen: UInt64?) -> Task<Void, Never>? {
        guard let open = openedHubChat, let config = providers.first(where: { $0.id == open.providerID }),
            admitsImageChoice(chosen, on: config)
        else { return nil }
        openedHubChat?.imageModel = chosen
        return judge(chosen, on: config)
    }

    // MARK: - Asking the hub

    /// Asks `config`'s hub whether a message that names `chosen` can be
    /// drawn, and keeps what it says. Not asked of a pipe that is not up,
    /// nor of a hub that lists no image models, which does not know the
    /// word.
    private func judge(_ chosen: UInt64?, on config: ProviderConfig) -> Task<Void, Never>? {
        guard let chosen, drawings[config.id]?.takesImageModel == true, config.isPipe,
            pipeSessions[config.id] != nil, pipeStatuses[config.id]?.isConnected == true,
            let hub = makeProvider(for: config) as? any DrawingProvider
        else { return nil }
        return Task { [weak self] in
            guard let answer = try? await hub.drawing(judging: chosen), let self,
                providers.first(where: { $0.id == config.id })?.kind == config.kind
            else { return }
            imageChoiceAnswers[config.id, default: [:]][chosen] = answer
        }
    }

    /// Asks the hub again about each image model a chat on screen chose,
    /// when it has just answered about drawing with `listed`. What it said
    /// before is forgotten, as its list was.
    func judgeImageChoices(on config: ProviderConfig, by hub: any DrawingProvider, listed: Drawing) async {
        var answers: [UInt64: Drawing] = [:]
        if listed.takesImageModel {
            let conversation = selectedConversation.flatMap { $0.providerID == config.id ? $0.imageModelID : nil }
            let chat = openedHubChat.flatMap { $0.providerID == config.id ? $0.imageModel : nil }
            for chosen in Set([conversation, chat].compactMap(\.self)).sorted() {
                answers[chosen] = try? await hub.drawing(judging: chosen)
            }
        }
        guard providers.first(where: { $0.id == config.id })?.kind == config.kind else { return }
        imageChoiceAnswers[config.id] = answers
    }

    /// Forgets every image model chosen on a provider, when it is moved to
    /// another machine: an id names a model on the old one alone.
    func forgetImageModels(on providerID: UUID) {
        imageChoiceAnswers[providerID] = nil
        for var conversation in conversations where conversation.providerID == providerID {
            guard conversation.imageModelID != nil else { continue }
            conversation.imageModelID = nil
            update(conversation)
        }
        if openedHubChat?.providerID == providerID { openedHubChat?.imageModel = nil }
    }
}
