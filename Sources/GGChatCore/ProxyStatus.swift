/// A tolerant subset of gglib's `GET /v1/proxy/status`. Every field is
/// optional so a field gglib renames does not blank the pane.
public struct ProxyStatus: Decodable, Sendable, Equatable {
    public var activeConnectionCount: Int
    public var slotsAvailable: Bool?
    public var slots: [Slot]
    public var recentRequests: [RecentRequest]

    public struct Slot: Decodable, Sendable, Equatable {
        public var id: Int?
        public var contextSize: Int?
        public var isProcessing: Bool?
        public var promptTokens: Int?
        public var promptTokensCached: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case contextSize = "n_ctx"
            case isProcessing = "is_processing"
            case promptTokens = "n_prompt_tokens"
            case promptTokensCached = "n_prompt_tokens_cache"
        }
    }

    public struct RecentRequest: Decodable, Sendable, Equatable {
        public var modelName: String?
        public var recordedAtSeconds: Int?
        public var messagesTruncated: Int?
        /// Whether the loop guard acted on this request, or nil when the
        /// hub did not say.
        public var loopGuardTripped: Bool?
        public var toolRepaired: Bool?

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case recordedAtSeconds = "recorded_at_secs"
            case messagesTruncated = "messages_truncated"
            case loopGuardTrip = "loop_guard_trip"
            case loopGuardTripped = "loop_guard_tripped"
            case toolRepaired = "tool_repaired"
        }

        /// gglib sends `loop_guard_trip`, the detector that acted (`"loop"`,
        /// `"stagnation"`) or `null` for none. An older hub sent the Bool
        /// `loop_guard_tripped`, which is still read when the newer key is
        /// absent. A detector this build does not know still counts as a trip.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
            recordedAtSeconds = try container.decodeIfPresent(Int.self, forKey: .recordedAtSeconds)
            messagesTruncated = try container.decodeIfPresent(Int.self, forKey: .messagesTruncated)
            toolRepaired = try container.decodeIfPresent(Bool.self, forKey: .toolRepaired)
            if container.contains(.loopGuardTrip) {
                loopGuardTripped = try !container.decodeNil(forKey: .loopGuardTrip)
            } else {
                loopGuardTripped = try container.decodeIfPresent(Bool.self, forKey: .loopGuardTripped)
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case activeConnections = "active_connections"
        case slotsAvailable = "slots_available"
        case slots
        case recentRequests = "recent_requests"
    }

    private struct Opaque: Decodable {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeConnectionCount = try container.decodeIfPresent([Opaque].self, forKey: .activeConnections)?.count ?? 0
        slotsAvailable = try container.decodeIfPresent(Bool.self, forKey: .slotsAvailable)
        slots = try container.decodeIfPresent([Slot].self, forKey: .slots) ?? []
        recentRequests = try container.decodeIfPresent([RecentRequest].self, forKey: .recentRequests) ?? []
    }
}

extension ProxyStatus.Slot {
    /// Prompt tokens over context size, 0…1, or nil when either is unknown.
    public var contextUsage: Double? {
        guard let promptTokens, let contextSize, contextSize > 0 else { return nil }
        return min(1, max(0, Double(promptTokens) / Double(contextSize)))
    }
}

extension ProxyStatus.RecentRequest {
    /// The flags gglib raised on this request, as short words for a badge row.
    public var flags: [String] {
        var flags: [String] = []
        if loopGuardTripped == true { flags.append("loop guard") }
        if toolRepaired == true { flags.append("tool repaired") }
        if let truncated = messagesTruncated, truncated > 0 { flags.append("\(truncated) truncated") }
        return flags
    }
}
