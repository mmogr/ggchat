import GGChatCore
import SwiftUI

/// What a conversation's wrench shows: its master switch and a row for each
/// server the paired Mac offers, in the Mac's order, with the conversation's
/// picks ticked. Hidden where no tools are offered: by address, where the
/// Mac offers none or has not been heard from, and on a Mac's own chat,
/// which keeps its tools on the Mac.
///
/// The state is never colour alone: the label says it in words, which
/// VoiceOver reads and the bar an iPhone Duo lays toolbar items in keeps,
/// and the symbol is filled while a server would be named and an outline
/// otherwise.
public struct ToolsMenu: Equatable, Sendable {
    /// One server the Mac offers.
    public struct Row: Equatable, Identifiable, Sendable {
        /// The server's id on the Mac.
        public let id: Int64
        /// Its name, with its id after it when another server shares it.
        public let title: String
        public let picked: Bool
    }

    /// Whether the conversation's tools are on.
    public let isOn: Bool
    public let rows: [Row]
    /// The servers the next request names, by id: the picks the Mac offers,
    /// and none while off.
    public let running: [Int64]

    /// No wrench.
    public static let hidden = ToolsMenu(isOn: false, rows: [], running: [])

    private init(isOn: Bool, rows: [Row], running: [Int64]) {
        self.isOn = isOn
        self.rows = rows
        self.running = running
    }

    /// The wrench for a conversation that chose `choice` on a Mac that
    /// offers `offered`.
    public init(choice: ToolChoice, offered: [OfferedServer]) {
        let titles = Self.titles(offered)
        isOn = !choice.off
        rows = zip(offered, titles).map { server, title in
            Row(id: server.id, title: title, picked: choice.picked.contains(server.id))
        }
        running = choice.servers(offered: offered)
    }

    /// Whether there is no wrench to show.
    public var isHidden: Bool {
        rows.isEmpty
    }

    /// The wrench's name, with its state.
    public var label: String {
        guard isOn else { return "Tools, off" }
        switch running.count {
        case 0: return "Tools, none picked"
        case 1: return "Tools, 1 server"
        case let count: return "Tools, \(count) servers"
        }
    }

    /// Filled while a server would be named, an outline while none would.
    public var symbol: String {
        running.isEmpty ? "wrench.and.screwdriver" : "wrench.and.screwdriver.fill"
    }

    /// Each server's name as a row shows it: alone, or with its id after it
    /// when another server the Mac offers has the same name, `fs (3)`, so
    /// the two can be told apart. The server-status sheet lists them so too.
    static func titles(_ servers: [OfferedServer]) -> [String] {
        let counts = Dictionary(servers.map { ($0.name, 1) }, uniquingKeysWith: +)
        return servers.map { counts[$0.name, default: 0] > 1 ? "\($0.name) (\($0.id))" : $0.name }
    }

    /// The rows of the tools Section in the panel beside a chat on an open
    /// iPhone Duo on its side, as `ToolsPanelRows` titles them: the master
    /// switch, then the servers.
    static func panelRowTitles(_ menu: ToolsMenu) -> [String] {
        [menu.label] + menu.rows.map(\.title)
    }
}

/// The wrench in a chat's top bar: a menu holding the master switch and a
/// pick for each server the paired Mac offers, as a tick. On an iPhone the
/// menu stays open while picks are made; on a Mac it closes after each.
struct ToolsMenuButton: View {
    let menu: ToolsMenu
    /// Called with the master switch's new state.
    let setOn: (Bool) -> Void
    /// Called with a server's id and whether it is now picked.
    let pick: (Int64, Bool) -> Void

    var body: some View {
        Menu {
            Toggle("Use tools", isOn: Binding(get: { menu.isOn }, set: { setOn($0) }))
                .accessibilityIdentifier("tools-on")
            Section("Servers") {
                ForEach(menu.rows) { row in
                    Toggle(row.title, isOn: Binding(get: { row.picked }, set: { pick(row.id, $0) }))
                        .accessibilityIdentifier("tools-server-\(row.id)")
                }
            }
            .disabled(!menu.isOn)
        } label: {
            Label(menu.label, systemImage: menu.symbol)
        }
        .menuIndicator(.hidden)
        #if os(iOS)
            .menuActionDismissBehavior(.disabled)
        #endif
        .accessibilityIdentifier("tools")
        .accessibilityHint(
            "Turns the paired Mac's tools on or off and picks which of its servers this conversation uses")
    }
}

#Preview("Tools") {
    let offered = [OfferedServer(id: 3, name: "tavily"), OfferedServer(id: 9, name: "fs")]
    let shared = [OfferedServer(id: 3, name: "fs"), OfferedServer(id: 9, name: "fs")]
    let menus = [
        ToolsMenu(choice: ToolChoice(off: true), offered: offered), ToolsMenu(choice: ToolChoice(), offered: offered),
        ToolsMenu(choice: ToolChoice(picked: [3]), offered: offered),
        ToolsMenu(choice: ToolChoice(picked: [9]), offered: shared),
    ]
    NavigationStack {
        Text("A conversation")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    ForEach(Array(menus.enumerated()), id: \.offset) { _, menu in
                        ToolsMenuButton(menu: menu, setOn: { _ in }, pick: { _, _ in })
                    }
                }
            }
    }
}
