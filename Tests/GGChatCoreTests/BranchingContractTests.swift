import XCTest

@testable import GGChatCore

/// Replays the branching cases gglib records (`contracts/chats/branching.json`
/// there, copied here byte for byte as `gglib-chats-branching.json` from the
/// gglib pull request #1375, the one that adds the rules) against
/// ``BranchRules``: every change's plan or refusal, whether its chat ends in a
/// question, and every family's branch points. A rule this build holds and
/// gglib does not fails here.
final class BranchingContractTests: XCTestCase {
    private struct Recorded: Decodable {
        let plans: [PlanCase]
        let points: [PointsCase]
    }

    private struct Row: Decodable {
        let id: Int64
        let role: BranchRole
        let content: String
        let images: [String]?
    }

    private struct Change: Decodable {
        let kind: String
        let messageID: Int64
        let content: String?
        let images: [String]?

        enum CodingKeys: String, CodingKey {
            case kind, content, images
            case messageID = "message_id"
        }

        /// The change, or a failure for a kind this build does not know, so a
        /// fixture copied again with a new shape fails rather than misreads.
        var change: ChatChange<Int64> {
            get throws {
                switch kind {
                case "edit": .edit(messageID: messageID, content: content ?? "", images: images ?? [])
                case "regenerate": .regenerate(messageID: messageID)
                case "branch": .branch(messageID: messageID)
                default: throw Unknown(what: "kind \(kind)")
                }
            }
        }
    }

    private struct Fork: Decodable {
        let through: Int64?
        let then: String
        let answer: Bool
    }

    private struct PlanWire: Decodable {
        struct Replace: Decodable { let question: Int64 }
        let replace: Replace?
        let fork: Fork?
    }

    private struct Answer: Decodable {
        let plan: PlanWire?
        let refused: String?
    }

    private struct PlanCase: Decodable {
        let name: String
        let path: [Row]
        let busy: Bool
        let change: Change
        let answer: Answer
        let answerable: Bool
    }

    private struct LineRowWire: Decodable {
        let id: Int64
        let key: Int64
        let role: BranchRole
        let text: String
        let images: Int
    }

    private struct LineChatWire: Decodable {
        let conversationID: Int64
        let updatedAt: String
        let rows: [LineRowWire]

        enum CodingKeys: String, CodingKey {
            case rows
            case conversationID = "conversation_id"
            case updatedAt = "updated_at"
        }
    }

    private struct OptionWire: Decodable, Equatable {
        let conversationID: Int64
        let messageID: Int64?
        let role: BranchRole?
        let preview: String

        enum CodingKeys: String, CodingKey {
            case role, preview
            case conversationID = "conversation_id"
            case messageID = "message_id"
        }
    }

    private struct PointWire: Decodable, Equatable {
        let messageID: Int64?
        let index: Int
        let options: [OptionWire]

        enum CodingKeys: String, CodingKey {
            case index, options
            case messageID = "message_id"
        }
    }

    private struct PointsCase: Decodable {
        let name: String
        let me: Int64
        let family: [LineChatWire]
        let points: [PointWire]
    }

    private func recorded() throws -> Recorded {
        try JSONDecoder().decode(Recorded.self, from: try Fixtures.data("gglib-chats-branching.json"))
    }

    /// A change's plan, or the code it is refused with.
    private enum Outcome: Equatable {
        case plan(BranchPlan<Int64>)
        case refused(String)
    }

    /// A shape in the fixture this build does not know, named in the
    /// failure.
    private struct Unknown: LocalizedError {
        let what: String

        var errorDescription: String? {
            "the fixture has \(what), which this build does not know"
        }
    }

    /// What gglib answers a case with: a refusal, or exactly one plan, each
    /// in a shape this build knows.
    private func expected(_ answer: Answer) throws -> Outcome {
        switch (answer.refused, answer.plan?.replace, answer.plan?.fork) {
        case (let code?, nil, nil):
            return .refused(code)
        case (nil, let replace?, nil):
            return .plan(.replace(question: replace.question))
        case (nil, nil, let fork?):
            guard let then = BranchThen(rawValue: fork.then) else { throw Unknown(what: "then \(fork.then)") }
            return .plan(.fork(through: fork.through, then: then, answer: fork.answer))
        default:
            throw Unknown(what: "an answer with no one outcome")
        }
    }

    func testThereAreCasesToReplay() throws {
        let recorded = try recorded()
        XCTAssertFalse(recorded.plans.isEmpty)
        XCTAssertFalse(recorded.points.isEmpty)
    }

    func testEveryChangeIsPlannedOrRefusedAsGglibDoes() throws {
        for recorded in try recorded().plans {
            let path = recorded.path.map {
                BranchRow(id: $0.id, role: $0.role, content: $0.content, images: $0.images ?? [])
            }
            let change = try recorded.change.change
            let got: Outcome
            do {
                got = .plan(try BranchRules.plan(path, change, busy: recorded.busy))
            } catch {
                got = .refused(error.code)
            }
            XCTAssertEqual(got, try expected(recorded.answer), recorded.name)
            XCTAssertEqual(BranchRules.answerable(path), recorded.answerable, recorded.name)
        }
    }

    func testEveryFamilysBranchPointsAreTheOnesGglibFinds() throws {
        for recorded in try recorded().points {
            let family = recorded.family.map { chat in
                LineChat(
                    chatID: chat.conversationID, updatedAt: chat.updatedAt,
                    rows: chat.rows.map {
                        LineRow(id: $0.id, key: $0.key, role: $0.role, text: $0.text, images: $0.images)
                    })
            }
            let got = BranchRules.points(recorded.me, family: family).map { point in
                PointWire(
                    messageID: point.messageID, index: point.index,
                    options: point.options.map {
                        OptionWire(
                            conversationID: $0.chatID, messageID: $0.messageID, role: $0.role, preview: $0.preview)
                    })
            }
            XCTAssertEqual(got, recorded.points, recorded.name)
        }
    }
}
