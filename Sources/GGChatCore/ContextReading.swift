import Foundation

/// How much of a model's context a conversation uses, as gglib counted it for
/// the last finished reply's last model call. Drawn as a ring, with the
/// counts one tap away.
///
/// The numbers are gglib's and nothing here estimates one: there is a reading
/// only when the prompt tokens, the completion tokens and a context size above
/// zero were all reported, and the size is never the one the model list gives
/// (ADR 0008). The arithmetic and the words follow the worked examples in
/// `contracts/context/readings.json`. That file is gglib's, added by the
/// gglib change that draws the same ring on its chat page, and this repo
/// holds a copy of it.
public struct ContextReading: Codable, Sendable, Equatable, Hashable {
    /// The prompt tokens plus the completion tokens of that one call. Never a
    /// sum across calls or replies.
    public let used: Int
    /// The context the server that answered was started with.
    public let size: Int
    /// How many earlier messages were shortened or left out so the request
    /// fit; zero for none.
    public let trimmed: Int
    /// Whether that call ended at its length limit, before the model was done.
    public let cutOff: Bool
    /// The model that was asked, for a conversation kept here: the reading is
    /// not drawn under another model. Nil for a Mac's chat.
    public let model: String?

    /// The finish reason of a call cut off before the model was done.
    static let lengthReason = "length"
    /// The largest count taken for one. No context holds a million million
    /// tokens, and with every count at or under this the arithmetic below
    /// cannot overflow whatever a server sends.
    static let largestCount = 1 << 40
    /// The least of the ring that is drawn, so a reading under a hundredth
    /// is still an arc to see and not a bare track.
    static let leastDrawn = 0.03

    /// Nil unless both counts and a size above zero are given: a count that
    /// is absent is unknown, not zero. A count below zero or beyond
    /// `largestCount` is no count either.
    public init?(
        promptTokens: Int?, completionTokens: Int?, contextSize: Int?, trimmedMessages: Int? = nil,
        finishReason: String? = nil, model: String? = nil
    ) {
        let counts = 0...Self.largestCount
        guard let promptTokens, let completionTokens, let contextSize, contextSize > 0,
            counts.contains(promptTokens), counts.contains(completionTokens), counts.contains(contextSize)
        else { return nil }
        used = promptTokens + completionTokens
        size = contextSize
        trimmed = trimmedMessages ?? 0
        cutOff = finishReason == Self.lengthReason
        self.model = model
    }

    /// A stored reading is read through the same checks as a server's
    /// counts, so bytes with a size of zero, or a count no context holds,
    /// are refused here and never reach the arithmetic.
    public init(from decoder: any Decoder) throws {
        let stored = try decoder.container(keyedBy: CodingKeys.self)
        let used = try stored.decode(Int.self, forKey: .used)
        // `used` is two counts added, so it is handed back as two.
        let prompt = min(used, Self.largestCount)
        let checked = ContextReading(
            promptTokens: prompt, completionTokens: used - prompt,
            contextSize: try stored.decode(Int.self, forKey: .size),
            trimmedMessages: try stored.decode(Int.self, forKey: .trimmed),
            finishReason: try stored.decode(Bool.self, forKey: .cutOff) ? Self.lengthReason : nil,
            model: try stored.decodeIfPresent(String.self, forKey: .model))
        guard let checked else {
            throw DecodingError.dataCorruptedError(
                forKey: .used, in: stored, debugDescription: "not a reading's counts")
        }
        self = checked
    }

    /// The reading of one finished call, from the usage it reported and why
    /// it ended: a chat stream's last frames, or an agent run's `turn_usage`.
    public init?(_ usage: Usage?, reason: String?, model: String? = nil) {
        self.init(
            promptTokens: usage?.promptTokens, completionTokens: usage?.completionTokens,
            contextSize: usage?.contextSize, trimmedMessages: usage?.trimmedMessages, finishReason: reason,
            model: model)
    }

    /// The reading a saved reply's row carries.
    public init?(_ metadata: HubMessageMetadata?) {
        self.init(
            promptTokens: metadata?.promptTokens, completionTokens: metadata?.completionTokens,
            contextSize: metadata?.contextSize, trimmedMessages: metadata?.trimmedMessages,
            finishReason: metadata?.finishReason)
    }

    /// The share used as a whole number, a half rounded up, and never past a
    /// hundred however far past full the counts are.
    public var percent: Int {
        min(100, (200 * used + size) / (2 * size))
    }

    /// How full that is. Each step past plain has a word, so the colour is
    /// never the only thing that says it.
    public enum Severity: String, Sendable, Equatable {
        case normal
        case warning
        case danger

        /// "filling up" or "almost full"; nothing while there is room.
        public var word: String? {
            switch self {
            case .normal: nil
            case .warning: "filling up"
            case .danger: "almost full"
            }
        }
    }

    /// Plain under 70 percent, a warning from 70 and danger from 90, by the
    /// whole-number percent.
    public var severity: Severity {
        switch percent {
        case ..<70: .normal
        case ..<90: .warning
        default: .danger
        }
    }

    /// Whether the figure stands beside the ring: from a warning on, so the
    /// colour is never the only thing that says the context is filling.
    public var showsFigure: Bool {
        severity != .normal
    }

    /// Whether a mark sits inside the ring: at danger.
    public var showsMark: Bool {
        severity == .danger
    }

    /// How much of the ring is drawn: the share used, the whole ring at most
    /// and `leastDrawn` at least.
    public var fraction: Double {
        min(1, max(Self.leastDrawn, Double(used) / Double(size)))
    }

    /// "25%" in `locale`'s digits, and "<1%" for a share that rounds to none:
    /// a conversation that has used something never reads as nothing.
    public func percentText(in locale: Locale) -> String {
        percent == 0 ? "<\(Self.digits(1, locale))%" : "\(Self.digits(percent, locale))%"
    }

    /// What VoiceOver says for the ring: "72 percent of context used, filling
    /// up".
    public func spokenValue(in locale: Locale) -> String {
        let share = percent == 0 ? "less than \(Self.digits(1, locale))" : Self.digits(percent, locale)
        let said = "\(share) percent of context used"
        return severity.word.map { "\(said), \($0)" } ?? said
    }

    /// The sheet's sentences, in order: the counts, how full it is from 70
    /// percent, the messages trimmed to fit, and a reply that was cut off.
    /// The numbers are in `locale`'s digits; the words are not translated.
    public func lines(in locale: Locale) -> [String] {
        let counts = "\(Self.digits(used, locale)) of \(Self.digits(size, locale)) tokens"
        var lines = ["\(counts) (\(percentText(in: locale))) after the last finished reply."]
        if let word = severity.word { lines.append("Context is \(word).") }
        if trimmed == 1 {
            lines.append("\(Self.digits(1, locale)) earlier message was shortened or left out to fit.")
        } else if trimmed > 1 {
            lines.append("\(Self.digits(trimmed, locale)) earlier messages were shortened or left out to fit.")
        }
        if cutOff { lines.append("The last reply was cut off before it finished.") }
        return lines
    }

    private static func digits(_ number: Int, _ locale: Locale) -> String {
        number.formatted(.number.locale(locale))
    }
}

// Which of a chat's saved replies its reading comes from.
extension ContextReading {
    /// Which reply decides the reading, of a chat's replies oldest first: the
    /// newest, passing over one gglib marked incomplete that carries neither
    /// count. Nil when none is left. The one that decides may carry no
    /// reading at all, and then there is none: an older reply's is never
    /// shown in its place.
    public static func deciding(among replies: [HubMessageMetadata?]) -> Int? {
        replies.lastIndex { reply in
            guard let reply, reply.incomplete == true else { return true }
            return reply.promptTokens != nil || reply.completionTokens != nil
        }
    }

    /// The reading of a Mac's chat, from its rows oldest first: the reply
    /// that decides it, read as that row's metadata gives it.
    public static func last(in rows: [HubMessage]) -> ContextReading? {
        let replies = rows.filter { $0.role == Role.assistant.rawValue }.map(\.metadata)
        return deciding(among: replies).flatMap { ContextReading(replies[$0]) }
    }
}
