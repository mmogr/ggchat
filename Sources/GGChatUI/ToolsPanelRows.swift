#if os(iOS)
    import GGChatCore
    import SwiftUI

    /// A switch whose name carries its state, for the reason
    /// `ThinkingToggle` gives, under the identifier the top bar's control
    /// has: a row of the panel beside a chat on an open iPhone Duo on its
    /// side.
    struct PanelSwitchRow: View {
        let label: String
        let symbol: String
        let isOn: Bool
        let id: String
        let set: (Bool) -> Void

        var body: some View {
            Toggle(isOn: Binding(get: { isOn }, set: { set($0) })) {
                Label(label, systemImage: symbol)
            }
            .accessibilityIdentifier(id)
        }
    }

    /// The chat's tools in the panel beside it, a Section of their own: the
    /// master switch, then a switch for each server the paired Mac offers,
    /// which cannot be turned while the master is off. The wrench is not in
    /// the top bar while the panel holds the chat's controls, so this is
    /// where its servers are picked.
    ///
    /// The rows coming on screen shows the servers, which clears the chat's
    /// badge, and again when the Mac's offer changes. A server new when they
    /// came says "New" for as long as they stay, though it is shown by then.
    struct ToolsPanelRows: View {
        let conversationID: UUID
        let menu: ToolsMenu
        let setOn: (Bool) -> Void
        let pick: (Int64, Bool) -> Void
        /// Called when the rows come on screen, or the offer changes.
        let seen: () -> Void
        /// The servers that were new when the rows came.
        @State private var shownNew: Set<Int64> = []

        var body: some View {
            let titles = ToolsMenu.panelRowTitles(menu)
            Section("Tools") {
                PanelSwitchRow(label: titles[0], symbol: menu.symbol, isOn: menu.isOn, id: "tools", set: setOn)
                    .task(id: Showing(conversationID: conversationID, offered: menu.rows.map(\.id))) {
                        shownNew = Set(menu.rows.filter(\.isNew).map(\.id))
                        seen()
                    }
                ForEach(Array(zip(menu.rows, titles.dropFirst())), id: \.0.id) { row, title in
                    Toggle(title, isOn: Binding(get: { row.picked }, set: { pick(row.id, $0) }))
                        .badge(row.isNew || shownNew.contains(row.id) ? Text("New") : nil)
                        .badgeProminence(.decreased)
                        .accessibilityIdentifier("tools-server-\(row.id)")
                        .disabled(!menu.isOn)
                }
            }
        }

        /// What the rows' showing is for: one chat and the servers offered.
        private struct Showing: Equatable {
            let conversationID: UUID
            let offered: [Int64]
        }
    }

    #Preview("Tools in the panel") {
        let offered = [OfferedServer(id: 3, name: "tavily"), OfferedServer(id: 9, name: "fs")]
        Form {
            ForEach([ToolChoice(picked: [3]), ToolChoice(off: true, seen: [3, 9])], id: \.self) { choice in
                ToolsPanelRows(
                    conversationID: UUID(), menu: ToolsMenu(choice: choice, offered: offered), setOn: { _ in },
                    pick: { _, _ in }, seen: {})
            }
        }
    }
#endif
