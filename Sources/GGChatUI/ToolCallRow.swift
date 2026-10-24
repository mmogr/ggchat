import GGChatCore
import SwiftUI

/// One tool a finished reply called, under the reply: collapsed to its
/// heading, which says the tool and whose it is, with a warning mark when
/// the tool said it failed. Opened, it shows what the model sent the tool
/// and what came back, cut short when long, both selectable. Drawn from
/// what the reply kept and nothing else, for any tool.
struct ToolCallRow: View {
    @Environment(\.locale) private var locale
    let exchange: ToolExchange
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sent")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(exchange.prettyArguments)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Text("Received")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(exchange.shownResult(in: locale) ?? ToolExchange.noAnswer)
                    .font(.callout.monospaced())
                    .foregroundStyle(exchange.result == nil ? .secondary : .primary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Label(exchange.heading, systemImage: Self.symbol)
                if exchange.failed == true {
                    Image(systemName: Self.failedSymbol)
                        .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.label(for: exchange, expanded: expanded))
        }
        .accessibilityIdentifier("tool-call")
    }

    /// Every row's symbol: a tool, whichever tool it is.
    static let symbol = "wrench.and.screwdriver"
    /// The mark beside a tool that said it failed. Never the colour alone:
    /// VoiceOver hears "failed" in the row's name.
    static let failedSymbol = "exclamationmark.triangle.fill"

    /// What VoiceOver hears: "Tool call, tavily_search on Tavily Web Search,
    /// failed, collapsed", with whose and whether it failed said only when
    /// known.
    static func label(for exchange: ToolExchange, expanded: Bool) -> String {
        var label = "Tool call, \(exchange.title)"
        if let origin = exchange.origin { label += " on \(origin)" }
        if exchange.failed == true { label += ", failed" }
        return label + (expanded ? ", expanded" : ", collapsed")
    }
}

/// The tools a stored reply called, one row each, in the order it called
/// them. A question has none, and nor has a reply a hub is still writing:
/// its rows come once it has finished.
struct ToolCallRows: View {
    let message: Message

    var body: some View {
        if message.role == .assistant, !message.isBeingWritten {
            ForEach(message.exchanges, id: \.callID) { exchange in
                ToolCallRow(exchange: exchange)
            }
        }
    }
}

#Preview("Tool calls") {
    let reply = Message(
        role: .assistant, content: "Pin the version.", createdAt: .now,
        exchanges: [
            ToolExchange(
                callID: "c1", name: "3:tavily_search", arguments: #"{"query":"cargo lock v4"}"#,
                result: "Cargo.lock v4 is the default from 1.83.", server: "Tavily Web Search", failed: false),
            ToolExchange(
                callID: "c2", name: "3:tavily_search", arguments: #"{"query":"cargo lock v5"}"#,
                result: "usage limit reached", server: "Tavily Web Search", failed: true),
            ToolExchange(callID: "c3", name: "builtin:generate_image", arguments: #"{"prompt":"a fox"}"#),
        ])
    VStack(alignment: .leading) { ToolCallRows(message: reply) }
        .padding()
}
