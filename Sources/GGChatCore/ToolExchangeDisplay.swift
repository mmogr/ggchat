import Foundation

/// What a tool call kept with a reply shows under it: a heading that says
/// which tool and whose it is, what the model sent it, laid out to read,
/// and what it answered, cut short when long. Worked out here from what is
/// kept, so the row under a reply is drawn from nothing else.
extension ToolExchange {
    /// The tool's own name: what follows the first `:` of the name gglib
    /// gives it, `3:tavily_search` and `builtin:generate_image` alike, or
    /// the whole name when it has no `:` or nothing after one.
    public var title: String {
        guard let colon = name.firstIndex(of: ":") else { return name }
        let tool = name[name.index(after: colon)...]
        return tool.isEmpty ? name : String(tool)
    }

    /// Whose tool it is: the MCP server the call named, else "gglib" for one
    /// of gglib's own, `builtin:…`, else nil, which is a tool this build
    /// cannot place.
    public var origin: String? {
        if let server, !server.isEmpty { return server }
        return name.hasPrefix("builtin:") ? "gglib" : nil
    }

    /// The tool and whose it is, "tavily_search · Tavily Web Search", or
    /// the tool alone when whose is not known.
    public var heading: String {
        origin.map { "\(title) · \($0)" } ?? title
    }

    /// What the model sent the tool: a JSON object or array laid out over
    /// lines with its keys sorted, an empty one as `{}` or `[]`, and any
    /// other text as it was written.
    public var prettyArguments: String {
        let given = try? JSONSerialization.jsonObject(with: Data(arguments.utf8), options: [.fragmentsAllowed])
        if let object = given as? [String: Any], object.isEmpty { return "{}" }
        if let array = given as? [Any], array.isEmpty { return "[]" }
        guard let given, given is [String: Any] || given is [Any],
            let data = try? JSONSerialization.data(
                withJSONObject: given, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return arguments }
        return String(decoding: data, as: UTF8.self)
    }

    /// What the tool answered, its first `limit` characters when it is
    /// longer, then a line that says how many more there are, in `locale`'s
    /// digits. A character is what is seen as one, so an emoji or an accent
    /// is never cut in two. Nil for a call that was never answered.
    public func shownResult(limit: Int = 2_000, in locale: Locale) -> String? {
        guard let result else { return nil }
        let more = result.count - limit
        guard more > 0 else { return result }
        let count = more.formatted(.number.locale(locale))
        return "\(result.prefix(limit))\n… \(count) more \(more == 1 ? "character" : "characters")"
    }

    /// What is shown for a call that was never answered: the reply ended,
    /// or was stopped, before the tool said anything.
    public static let noAnswer = "No answer: the reply ended before the tool answered."
}
