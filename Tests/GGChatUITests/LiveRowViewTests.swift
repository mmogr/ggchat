import XCTest

@testable import GGChatUI

/// How a row of a reply being written is drawn, read from the view it is
/// built from: one line of its mark, its text and its detail in every
/// state, and its state in words for VoiceOver.
@MainActor
final class LiveRowViewTests: XCTestCase {
    /// What a row is drawn as: what is set over the whole row, and what its
    /// stack holds, in the order it draws them.
    private struct Drawn {
        /// The line limit set over the whole row, if one is: the one
        /// environment value of `Int?` a row writes.
        var lineLimit: Int??
        /// What VoiceOver hears: the row's label, then its value.
        var label: [String] = []
        var value: [String] = []
        /// The symbols the row's stack draws.
        var marks: [String] = []
        /// The widths of the frames in the row's stack.
        var widths: [CGFloat?] = []
        /// The words the row's stack draws.
        var words: [String] = []
    }

    private static func name(of value: Any) -> String { String(describing: type(of: value)) }

    private static func children(of value: Any) -> [String: Any] {
        Dictionary(
            Mirror(reflecting: value).children.compactMap { child in child.label.map { ($0, child.value) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// The values under `value`, itself first, depth first.
    private static func all(in value: Any, depth: Int = 0) -> [Any] {
        guard depth < 40 else { return [value] }
        return [value] + Mirror(reflecting: value).children.flatMap { all(in: $0.value, depth: depth + 1) }
    }

    /// The words a Text under `value` holds, in order.
    private static func words(in value: Any) -> [String] {
        all(in: value).compactMap { value in
            guard name(of: value) == "Storage" else { return nil }
            return children(of: value)["verbatim"] as? String
        }
    }

    /// Reads the row down the modifiers set over its stack, then the stack.
    private static func drawn(_ row: LiveRow) -> Drawn {
        var drawn = Drawn()
        var value: Any = LiveRowView(row: row).body
        while !name(of: value).hasPrefix("HStack") {
            let parts = children(of: value)
            guard let content = parts["content"], let modifier = parts["modifier"] else { return drawn }
            if name(of: modifier) == "_EnvironmentKeyWritingModifier<Optional<Int>>" {
                drawn.lineLimit = children(of: modifier)["value"] as? Int?
            }
            for part in all(in: modifier) {
                if name(of: part).hasPrefix("AccessibilityLabelStorage") { drawn.label += words(in: part) }
                if name(of: part).hasPrefix("AccessibilityValueStorage") { drawn.value += words(in: part) }
            }
            value = content
        }
        for part in all(in: value) {
            if name(of: part).hasSuffix("NamedImageProvider"), let mark = children(of: part)["name"] as? String {
                drawn.marks.append(mark)
            }
            if name(of: part) == "_FrameLayout" { drawn.widths.append(children(of: part)["width"] as? CGFloat) }
        }
        drawn.words = words(in: value)
        return drawn
    }

    private static func row(_ state: LiveRow.State, _ detail: String?) -> LiveRow {
        LiveRow(id: 0, kind: .tool, text: "Read File: Cargo.lock", state: state, detail: detail, callID: "c1")
    }

    /// Every row is one line high whatever its state: one line over the
    /// whole row, its state's mark in a column of the same width, then its
    /// text, then the time gglib wrote or "failed" after it when there is
    /// one.
    func testEveryRowIsOneLineOfItsMarkItsTextAndItsDetail() {
        let rows = [
            Self.row(.running, nil), Self.row(.done, "3ms"), Self.row(.done, nil),
            Self.row(.failed, LiveRow.failedWord),
        ]
        var widths: Set<CGFloat> = []
        for row in rows {
            let drawn = Self.drawn(row)
            let state = "\(row.state) \(row.detail ?? "-")"
            XCTAssertEqual(drawn.lineLimit, .some(1), "a \(state) row may wrap")
            XCTAssertEqual(drawn.marks, [LiveRowView.mark(for: row.state)], state)
            XCTAssertEqual(drawn.words, ["Read File: Cargo.lock"] + (row.detail.map { [$0] } ?? []), state)
            XCTAssertEqual(drawn.widths.count, 1, "the mark's column, \(state)")
            widths.formUnion(drawn.widths.compactMap(\.self))
        }
        XCTAssertEqual(widths.count, 1, "the mark's column moved with its state")
        XCTAssertGreaterThan(widths.first ?? 0, 0)
    }

    /// VoiceOver hears each row's state in words, as gglib's window says
    /// them, and how long a call that is done took.
    func testVoiceOverHearsEachRowsStateInWords() {
        let heard = [
            Self.row(.running, nil), Self.row(.done, "3ms"), Self.row(.failed, LiveRow.failedWord),
        ].map { row in
            let drawn = Self.drawn(row)
            return drawn.label + drawn.value
        }
        XCTAssertEqual(
            heard,
            [
                ["Read File: Cargo.lock running.", ""], ["Read File: Cargo.lock done.", "3ms"],
                ["Read File: Cargo.lock failed.", ""],
            ])
    }
}
