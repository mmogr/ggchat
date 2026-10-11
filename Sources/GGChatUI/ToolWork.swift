import Foundation
import GGChatCore

/// What a reply being written shows of work that takes a while: how far a
/// tool it called has got, which today is a picture being drawn, the latest
/// look at that picture, and what the reply is waiting for when something
/// else has the machine. It is read from the run's events into memory,
/// shown, and never kept: a reply that is read again from its cursor is
/// told again, and sent the current look once.
struct ToolWork: Equatable {
    /// The latest word from a tool still at work.
    private(set) var progress: ToolProgress?
    /// What the reply is waiting for, until anything else arrives.
    private(set) var waiting: RunWait?
    /// The latest look at the picture being drawn, and only the latest.
    private(set) var preview: PreviewFrame?

    /// Whether there is anything to show.
    var isEmpty: Bool {
        progress == nil && waiting == nil && preview == nil
    }

    /// Takes a look at the picture, over the one before.
    mutating func show(_ frame: PreviewFrame) {
        preview = frame
    }

    /// Takes one event of the run. A tool's progress is the latest one, and
    /// goes with the look at its picture when that tool's call ends, not
    /// another's. A wait lasts until
    /// the next event that is not a wait: nothing says a wait is over but
    /// the reply going on.
    mutating func apply(_ event: ChatEvent) {
        switch event {
        case .waiting(let wait):
            waiting = wait
        case .toolProgress(let latest):
            progress = latest
            waiting = nil
        case .toolEnded(let callID):
            if progress?.callID == callID { progress = nil }
            if preview?.callID == callID { preview = nil }
            waiting = nil
        case .delta, .reasoning, .progress, .tool, .images, .usage, .finished, .error:
            waiting = nil
        }
    }

    /// The run ended, or the reply was given up: nothing is at work.
    mutating func end() {
        self = ToolWork()
    }

    /// One line for what is going on, in `locale`'s digits, or nil for
    /// nothing: the picture's stage and step while one is drawn, else what
    /// the reply waits for.
    func line(in locale: Locale) -> String? {
        if let progress { return Self.line(for: progress, in: locale) }
        if let waiting { return Self.line(for: waiting, in: locale) }
        return nil
    }

    /// How far the steps have got, from 0 to 1, while the tool reports
    /// both counts, as a picture being stepped through does; nil otherwise,
    /// and there is then no bar to fill.
    var fraction: Double? {
        guard let progress, let done = progress.done, let total = progress.total, total > 0 else { return nil }
        return min(max(Double(done) / Double(total), 0), 1)
    }

    static func line(for progress: ToolProgress, in locale: Locale) -> String {
        func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
        switch progress.stage {
        case .queued:
            guard let position = progress.position, position > 1 else { return "Drawing: waiting in line" }
            return "Drawing: waiting in line, place \(number(position))"
        case .loading:
            return "Drawing: loading the image model"
        case .sampling:
            guard let done = progress.done, let total = progress.total else { return "Drawing" }
            let steps = "step \(number(done)) of \(number(total))"
            guard let pass = progress.pass, pass > 1 else { return "Drawing: \(steps)" }
            return "Drawing picture \(number(pass)): \(steps)"
        case .decoding:
            return "Drawing: finishing the picture"
        case .finishing:
            return "Drawing: saving the picture"
        }
    }

    static func line(for wait: RunWait, in locale: Locale) -> String {
        func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
        var line: String
        switch wait.reason {
        case .imageRender:
            line = "Waiting for a picture to be drawn"
            if wait.total > 0 { line += ", at step \(number(wait.step)) of \(number(wait.total))" }
        case .modelLoad:
            line = "Waiting for the model to load"
        }
        if wait.position > 1 { line += ", place \(number(wait.position)) in line" }
        return line
    }
}
