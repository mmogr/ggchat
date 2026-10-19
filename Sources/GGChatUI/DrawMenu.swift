import GGChatCore
import SwiftUI

/// What the image-model menu over a composer's field lists: the image
/// models of the chat's hub, as its answer about drawing gave them, with
/// the chat's choice marked. It has rows only where there is a choice to
/// make or one to undo: a hub that lists two image models or more, or a
/// chat that has already chosen. Any other hub, one from before the list
/// among them, has none, and the line is then plain.
public struct DrawMenu: Equatable, Sendable {
    /// One row: the hub's own pick, or one image model.
    public struct Row: Equatable, Sendable, Identifiable {
        /// The image model's id on the hub, or nil for the hub's own pick.
        public let model: UInt64?
        public let title: String
        /// The family, "loaded" for one loaded now, and what a model that
        /// cannot draw is missing.
        public let detail: String?
        /// Whether it can be picked: a model without all its files cannot.
        public let enabled: Bool
        /// Whether it is the chat's choice.
        public let checked: Bool

        public var id: String {
            model.map(String.init) ?? "default"
        }
    }

    public let rows: [Row]
    /// The name of the image model a message would be drawn with: the one
    /// chosen, or else the hub's default. Nil when the list names neither.
    public let drawsWith: String?

    /// A control with no menu.
    public static let none = DrawMenu(rows: [], drawsWith: nil)

    init(rows: [Row], drawsWith: String?) {
        self.rows = rows
        self.drawsWith = drawsWith
    }

    /// The menu for a hub that answered `drawing`, for a chat that chose
    /// `chosen`. "Default", naming the model the hub's own rule picks, is
    /// first, where the hub has one or the chat a choice to undo; then
    /// each model in the order the hub gave.
    init(_ drawing: Drawing?, chosen: UInt64?) {
        guard let models = drawing?.models, models.count >= 2 || chosen != nil else {
            self = .none
            return
        }
        let byDefault = models.first(where: \.isDefault)
        let first = Row(
            model: nil, title: byDefault.map { "Default (\($0.name))" } ?? "Default", detail: nil, enabled: true,
            checked: chosen == nil)
        // With no default and nothing chosen, "Default" would name nothing
        // and undo nothing.
        rows =
            (byDefault == nil && chosen == nil ? [] : [first])
            + models.map { model in
                Row(
                    model: model.id, title: model.name, detail: Self.detail(of: model), enabled: model.complete,
                    checked: model.id == chosen)
            }
        drawsWith = chosen.map { id in models.first { $0.id == id }?.name } ?? byDefault?.name
    }

    /// Whether the control has a menu at all.
    public var isOffered: Bool {
        !rows.isEmpty
    }

    /// The line under a model's name.
    static func detail(of model: ImageModelRow) -> String? {
        var parts: [String] = []
        if !model.familyLabel.isEmpty { parts.append(model.familyLabel) }
        if model.resident { parts.append("loaded") }
        if !model.complete {
            let lacks = model.missingLabels
            parts.append(lacks.isEmpty ? "missing a file" : "missing \(lacks.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{B7} ")
    }
}

/// The rows of the image-model menu, as buttons: the name, the line under
/// it, and a tick on the chat's choice. A model that cannot draw is dimmed
/// and cannot be picked.
struct DrawMenuRows: View {
    let menu: DrawMenu
    /// Called with the row's model when one is picked.
    let pick: (UInt64?) -> Void

    var body: some View {
        ForEach(menu.rows) { row in
            Button {
                pick(row.model)
            } label: {
                Text(row.title)
                if let detail = row.detail { Text(detail) }
                if row.checked { Image(systemName: "checkmark") }
            }
            .disabled(!row.enabled)
            .accessibilityAddTraits(row.checked ? .isSelected : [])
        }
    }
}
