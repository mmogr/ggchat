/// One server-sent event, per the WHATWG spec's dispatch rules.
public struct SSEEvent: Equatable, Sendable {
    public var event: String?
    public var data: String
    public var id: String?

    public init(event: String? = nil, data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

public enum SSEItem: Equatable, Sendable {
    case event(SSEEvent)
    /// The OpenAI sentinel `data: [DONE]`.
    case done
}

/// Pure: bytes in, events out. Feed it whatever slices arrive; a line or a
/// multi-byte character may be split across calls.
public struct SSEParser: Sendable {
    private var pending: [UInt8] = []
    private var dataLines: [String] = []
    private var eventName: String?
    private var lastEventID: String?

    public init() {}

    public mutating func feed(_ bytes: some Sequence<UInt8>) -> [SSEItem] {
        var items: [SSEItem] = []
        for byte in bytes {
            if byte == UInt8(ascii: "\n") {
                if pending.last == UInt8(ascii: "\r") { pending.removeLast() }
                if let item = consumeLine(pending) { items.append(item) }
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.append(byte)
            }
        }
        return items
    }

    /// Flushes an event that had no trailing blank line, at end of stream.
    public mutating func finish() -> [SSEItem] {
        var items: [SSEItem] = []
        if !pending.isEmpty {
            if pending.last == UInt8(ascii: "\r") { pending.removeLast() }
            if let item = consumeLine(pending) { items.append(item) }
            pending.removeAll()
        }
        if let item = dispatch() { items.append(item) }
        return items
    }

    private mutating func consumeLine(_ line: [UInt8]) -> SSEItem? {
        if line.isEmpty { return dispatch() }
        if line.first == UInt8(ascii: ":") { return nil }
        let field: String
        let value: String
        if let colon = line.firstIndex(of: UInt8(ascii: ":")) {
            field = String(decoding: line[..<colon], as: UTF8.self)
            var rest = line[(colon + 1)...]
            if rest.first == UInt8(ascii: " ") { rest = rest.dropFirst() }
            value = String(decoding: rest, as: UTF8.self)
        } else {
            field = String(decoding: line, as: UTF8.self)
            value = ""
        }
        switch field {
        case "data": dataLines.append(value)
        case "event": eventName = value
        case "id" where !value.utf8.contains(0): lastEventID = value
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> SSEItem? {
        defer {
            dataLines.removeAll(keepingCapacity: true)
            eventName = nil
        }
        guard !dataLines.isEmpty else { return nil }
        let data = dataLines.joined(separator: "\n")
        if data == "[DONE]" { return .done }
        return .event(SSEEvent(event: eventName, data: data, id: lastEventID))
    }
}
