import Foundation

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
        public var loopGuardTripped: Bool?
        public var toolRepaired: Bool?

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case recordedAtSeconds = "recorded_at_secs"
            case messagesTruncated = "messages_truncated"
            case loopGuardTripped = "loop_guard_tripped"
            case toolRepaired = "tool_repaired"
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
