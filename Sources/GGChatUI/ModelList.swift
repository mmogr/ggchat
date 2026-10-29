import Foundation
import GGChatCore

/// One model in the model list: its id, which is the name it is shown and
/// sent by, the one short line under it, and whether it is the
/// conversation's.
nonisolated public struct ModelListRow: Identifiable, Equatable, Sendable {
    public let modelID: String
    public let detail: String?
    public let isCurrent: Bool
    public var id: String { modelID }

    public init(modelID: String, detail: String?, isCurrent: Bool) {
        self.modelID = modelID
        self.detail = detail
        self.isCurrent = isCurrent
    }
}

/// One provider's part of the model list: the models it can chat with,
/// what its session is doing, and whether a pick there moves the
/// conversation. Built by `AppModel.modelListSections(for:locale:calendar:)`.
nonisolated public struct ModelListSection: Identifiable, Equatable, Sendable {
    public let provider: ProviderConfig
    /// A few words on its session: the engine's for This iPhone, a pipe's
    /// connection or when its machine was last heard. Nil for a server by
    /// address, which has no session.
    public let state: String?
    public let rows: [ModelListRow]
    /// Whether it has listed its models at all. One that has not shows
    /// "Not listed yet" rather than an empty list.
    public let isListed: Bool
    /// Its rows are the ones it listed last, and its pipe is not up to say
    /// whether they still are: drawn dimmed, and still picked.
    public let isStale: Bool
    /// Whether picking here moves the conversation to this provider, which
    /// waits for a reply in flight (`AppModel.canChangeProvider(of:)`).
    public let moves: Bool
    /// A pipe that is down and has listed nothing offers Connect in place
    /// of "Not listed yet" (`AppModel.connect(fromTheList:)`).
    public let offersConnect: Bool
    public var id: UUID { provider.id }

    public init(
        provider: ProviderConfig, state: String?, rows: [ModelListRow], isListed: Bool, isStale: Bool, moves: Bool,
        offersConnect: Bool = false
    ) {
        self.provider = provider
        self.state = state
        self.rows = rows
        self.isListed = isListed
        self.isStale = isStale
        self.moves = moves
        self.offersConnect = offersConnect
    }
}

/// The model list as the panel shows it: the sections left by the filter
/// and the search, the chips to filter by, and whether a search is
/// offered. Pure, so the filtering and searching are tested without a view.
nonisolated public struct ModelList: Equatable, Sendable {
    /// More models than this, across every provider, and the list offers a
    /// search. The composer's list scrolls within 340 points, about six of
    /// its two-line rows under two provider headings, so past eight it
    /// scrolls even on one provider, and finding a model by eye stops being
    /// quicker than typing a few letters of it.
    public static let searchThreshold = 8

    /// The most the list's rows scroll within: about six two-line rows
    /// under two headings, under the search and the chips.
    public static let scrollHeight: CGFloat = 340

    /// The most of the chat the whole open list takes, search, chips and
    /// rows: 460 points at most, so a tall window still shows the chat; no
    /// more than six tenths of `room`, the chat's height free of its top bar
    /// and the keyboard; and no more than leaves 190 points under and
    /// around it, the pill's row, the composer and a strip of the chat, or
    /// 320 at an accessibility text size, where the pills stack and the
    /// composer is taller. The room shrinks while the keyboard is up, and so
    /// does the list. Never under 96, a search and a row; 460 until the room
    /// has been measured.
    public static func panelHeight(room: CGFloat, accessible: Bool = false) -> CGFloat {
        guard room > 0 else { return 460 }
        return max(96, min(460, room * 0.6, room - (accessible ? 320 : 190)))
    }

    /// Below this height the search, the chips and the caption could not sit
    /// above the rows and leave them room.
    public static let pinnedTopNeeds: CGFloat = 200

    /// Whether the search, the chips and the caption stay above the rows
    /// while they scroll: from 200 points of list, and never at an
    /// accessibility text size, where they would take the whole of it.
    /// Otherwise there are no chips, and the search and the caption scroll
    /// with the rows, so nothing runs past the list's height.
    public static func pinsItsTop(height: CGFloat, accessible: Bool) -> Bool {
        !accessible && height >= pinnedTopNeeds
    }

    /// What the list says while a reply is written and another provider's
    /// models wait for it.
    public static let waitsForTheReply = "Another provider's models can be picked once this reply is written."

    public let sections: [ModelListSection]
    /// The providers a chip filters to, after All; none with fewer than two
    /// providers, where a filter would hide nothing.
    public let chips: [ProviderConfig]
    /// The provider filtered to, or nil for All. A filter naming a provider
    /// no longer there reads as All.
    public let filter: UUID?
    public let offersSearch: Bool
    /// The search as typed, trimmed; empty for none.
    public let query: String

    /// Whether a search found nothing at all, which the list says in words.
    public var foundNothing: Bool {
        !query.isEmpty && sections.allSatisfy(\.rows.isEmpty)
    }

    /// Filters `all` to the provider `filter` names, when it names one of
    /// them and there are chips to choose it by, and to the models whose
    /// id or detail line holds `query`, ignoring case. A section with no
    /// model that matches a search is left out; without a search, every
    /// section of the filter stays, listed or not.
    public static func make(_ all: [ModelListSection], filter: UUID?, query: String) -> ModelList {
        let chips = all.count >= 2 ? all.map(\.provider) : []
        let filter = chips.contains { $0.id == filter } ? filter : nil
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections = all.filter { filter == nil || $0.id == filter }
        if !query.isEmpty {
            sections = sections.compactMap { section in
                let rows = section.rows.filter { row in
                    row.modelID.localizedCaseInsensitiveContains(query)
                        || row.detail?.localizedCaseInsensitiveContains(query) == true
                }
                guard !rows.isEmpty else { return nil }
                return ModelListSection(
                    provider: section.provider, state: section.state, rows: rows, isListed: section.isListed,
                    isStale: section.isStale, moves: section.moves, offersConnect: section.offersConnect)
            }
        }
        let total = all.reduce(0) { $0 + $1.rows.count }
        return ModelList(
            sections: sections, chips: chips, filter: filter, offersSearch: total > searchThreshold, query: query)
    }
}

extension ProviderConfig {
    /// The symbol a provider is drawn with wherever it is listed: a rack for
    /// a server by address, a pipe's links, a phone for this device.
    nonisolated public var symbol: String {
        switch kind {
        case .openAICompatible: "server.rack"
        case .pipe: "point.3.connected.trianglepath.dotted"
        case .onDevice: "iphone"
        }
    }
}
