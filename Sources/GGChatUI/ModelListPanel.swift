import GGChatCore
import SwiftUI

/// The open model pill's list: a search once there are enough models to
/// need one, a chip per provider once there are two, and a section per
/// provider with its models. Drawn inside the pill's glass, which the
/// composer keeps; nothing here draws glass of its own. What it shows is
/// `AppModel.modelList(for:filter:query:locale:calendar:)`'s.
struct ModelListPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The provider the list is filtered to, by id, or empty for All. A
    /// preference of this device's, kept as one, so the list opens filtered
    /// as it was left.
    @AppStorage("ggchat-model-list-filter") private var filter = ""
    @State private var query = ""
    let conversation: Conversation
    /// The chat's height free of its top bar and the keyboard; see
    /// `ModelList.panelHeight(room:)`.
    let room: CGFloat
    /// Closes the list, after a pick or Find a model….
    let close: () -> Void

    var body: some View {
        let list = model.modelList(
            for: conversation, filter: UUID(uuidString: filter), query: query, locale: locale, calendar: calendar)
        let canMove = model.canChangeProvider(of: conversation)
        let accessible = typeSize.isAccessibilitySize
        let height = ModelList.panelHeight(room: room, accessible: accessible)
        let pinned = ModelList.pinsItsTop(height: height, accessible: accessible)
        VStack(alignment: .leading, spacing: 0) {
            if pinned { top(list, canMove: canMove, chips: true) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !pinned { top(list, canMove: canMove, chips: false) }
                    if list.foundNothing {
                        Text("No models match \u{201C}\(list.query)\u{201D}.")
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                    ForEach(list.sections) { section in
                        sectionView(section, canMove: canMove)
                    }
                }
                .padding(.bottom, 6)
            }
            // About six two-line rows under two headings; see
            // `ModelList.searchThreshold`.
            .frame(maxHeight: ModelList.scrollHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: height, alignment: .top)
        .clipped()
        .onAppear { model.relistModels() }
    }

    /// The search, the chips and the caption, above the rows or scrolling
    /// with them (`ModelList.pinsItsTop(height:accessible:)`).
    @ViewBuilder
    private func top(_ list: ModelList, canMove: Bool, chips showsChips: Bool) -> some View {
        if list.offersSearch { searchField }
        if showsChips, !list.chips.isEmpty { chips(list) }
        if !canMove, list.sections.contains(where: \.moves) {
            Text(ModelList.waitsForTheReply)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search models", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .accessibilityIdentifier("model-search")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func chips(_ list: ModelList) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip("All", for: nil, chosen: list.filter == nil, id: "model-filter-all")
                ForEach(list.chips) { provider in
                    chip(
                        provider.name, for: provider.id, chosen: list.filter == provider.id,
                        id: "model-filter-\(provider.name)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func chip(_ title: String, for providerID: UUID?, chosen: Bool, id: String) -> some View {
        let choose = { filter = providerID?.uuidString ?? "" }
        Group {
            if chosen {
                Button(title, action: choose).buttonStyle(.borderedProminent)
            } else {
                Button(title, action: choose).buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func sectionView(_ section: ModelListSection, canMove: Bool) -> some View {
        let name = section.provider.name
        Label(section.state.map { "\(name) · \($0)" } ?? name, systemImage: section.provider.symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("model-section-\(name)")
        if section.offersConnect {
            Button("Connect") { model.connect(fromTheList: section.id) }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .accessibilityHint("Dials \(name) to list its models")
                .accessibilityIdentifier("model-connect-\(name)")
        } else if !section.isListed {
            ModelListNote(text: "Not listed yet")
        } else if section.rows.isEmpty, query.isEmpty {
            ModelListNote(
                text: section.provider.kind == .onDevice ? "No models on this iPhone yet." : "No models listed.")
        }
        ForEach(section.rows) { row in
            let held = section.moves && !canMove
            Button {
                model.pick(model: row.modelID, on: section.id, for: conversation.id)
                close()
            } label: {
                ModelListRowLabel(row: row, dimmed: section.isStale || held)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(held)
            .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
            .accessibilityHint(section.moves ? "Moves this conversation to \(name)" : "")
            .accessibilityIdentifier("model-row-\(name)/\(row.modelID)")
        }
        // The models found there run on this iPhone, so only its section
        // offers them.
        if section.provider.kind == .onDevice, model.runsModelsHere {
            Button("Find a model…") {
                close()
                model.openModelBrowser()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }
}

/// One model's name and its one line, dimmed when its provider's list is
/// one it gave last or the pick waits for a reply, and ticked when it is
/// the conversation's. The composer's list and the chat's panel both draw
/// it.
struct ModelListRowLabel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let row: ModelListRow
    let dimmed: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                // A long id cut to one line at an accessibility size is
                // a few letters of it, so it wraps there.
                Text(row.modelID)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(dimmed ? .tertiary : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if row.isCurrent {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
    }
}

/// A dim line where a provider has no models to show.
struct ModelListNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
    }
}
