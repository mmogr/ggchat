import GGChatCore

extension Drawing {
    /// A paired Mac's answer that it can draw and opens one MCP server to
    /// this device: tavily, its id 3 on the Mac.
    static let offersTavily = Drawing(
        available: true, model: "flux-dev", mcpServers: [OfferedServer(id: 3, name: "tavily")])
}
