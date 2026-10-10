/// When a change to a saved chat is made in place and when it branches the
/// chat, and the options a chat's family holds along it (ADR 0010).
///
/// The rules are gglib's, `gglib_core::domain::branching`, kept to the cases
/// gglib records: `BranchingContractTests` replays them. A saved reply is
/// never discarded or altered. A change that would do either copies the
/// chat, as far as the point it changes, into a new chat of the same family
/// and makes the change there. The one change made in place is an edit of
/// the chat's last question while nothing answers it, nor is being written.
public enum BranchRules {
    /// A turn of a chat: one question, or the rows of a reply.
    struct Unit: Equatable {
        var isQuestion: Bool
        var rows: Range<Int>
    }

    /// A chat's rows as turns. A system row belongs to none.
    static func units(_ roles: [BranchRole]) -> [Unit] {
        var units: [Unit] = []
        for (at, role) in roles.enumerated() {
            switch role {
            case .system:
                continue
            case .user:
                units.append(Unit(isQuestion: true, rows: at..<at + 1))
            case .assistant, .tool:
                if let last = units.last, !last.isQuestion {
                    units[units.count - 1].rows = last.rows.lowerBound..<at + 1
                } else {
                    units.append(Unit(isQuestion: false, rows: at..<at + 1))
                }
            }
        }
        return units
    }

    /// What `change` writes to a chat whose messages are `path`, `busy`
    /// saying whether a reply to it is being written.
    public static func plan<ID>(
        _ path: [BranchRow<ID>], _ change: ChatChange<ID>, busy: Bool
    ) throws(BranchRefusal) -> BranchPlan<ID> {
        guard let at = path.firstIndex(where: { $0.id == change.messageID }) else { throw .messageNotFound }
        let turns = units(path.map(\.role))
        guard let held = turns.firstIndex(where: { $0.rows.contains(at) }) else { throw .messageNotFound }
        let unit = turns[held]
        let before = { (start: Int) -> ID? in start > 0 ? path[start - 1].id : nil }
        switch change {
        case .branch:
            return .fork(through: path[unit.rows.upperBound - 1].id, then: .nothing, answer: false)
        case .regenerate:
            if unit.isQuestion { throw .notAReply }
            guard held > 0, turns[held - 1].isQuestion else { throw .nothingToAnswer }
            return .fork(through: before(unit.rows.lowerBound), then: .nothing, answer: true)
        case .edit(_, let content, let images):
            if !unit.isQuestion {
                if !images.isEmpty { throw .imagesOnReply }
                if content == path[at].content { throw .unchanged }
                return .fork(through: before(unit.rows.lowerBound), then: .editedReply, answer: false)
            }
            if content == path[at].content, images == path[at].images { throw .unchanged }
            if held == turns.count - 1, !busy { return .replace(question: change.messageID) }
            return .fork(through: before(unit.rows.lowerBound), then: .question, answer: true)
        }
    }

    /// Whether a chat whose messages are `path` ends in a question with no
    /// reply, which Retry answers.
    public static func answerable<ID>(_ path: [BranchRow<ID>]) -> Bool {
        units(path.map(\.role)).last?.isQuestion ?? false
    }
}
