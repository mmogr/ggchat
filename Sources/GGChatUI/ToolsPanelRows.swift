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
    struct ToolsPanelRows: View {
        let menu: ToolsMenu
        let setOn: (Bool) -> Void
        let pick: (Int64, Bool) -> Void

        var body: some View {
            let titles = ToolsMenu.panelRowTitles(menu)
            Section("Tools") {
                PanelSwitchRow(label: titles[0], symbol: menu.symbol, isOn: menu.isOn, id: "tools", set: setOn)
                ForEach(Array(zip(menu.rows, titles.dropFirst())), id: \.0.id) { row, title in
                    Toggle(title, isOn: Binding(get: { row.picked }, set: { pick(row.id, $0) }))
                        .accessibilityIdentifier("tools-server-\(row.id)")
                        .disabled(!menu.isOn)
                }
            }
        }
    }

    #Preview("Tools in the panel") {
        let offered = [OfferedServer(id: 3, name: "tavily"), OfferedServer(id: 9, name: "fs")]
        Form {
            ForEach([ToolChoice(picked: [3]), ToolChoice(off: true)], id: \.self) { choice in
                ToolsPanelRows(menu: ToolsMenu(choice: choice, offered: offered), setOn: { _ in }, pick: { _, _ in })
            }
        }
    }
#endif
