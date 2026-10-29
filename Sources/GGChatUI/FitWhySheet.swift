import GGChatCore
import SwiftUI

/// How gglib judged a model for this iPhone, in plain words, from the
/// figures it reached its verdict with (`FitWhy`): the weights, what each
/// token of context adds, what this iPhone gives a model, and the context
/// the model was trained on; and, for a suggestion, gglib's sentence on why
/// that one. A figure gglib did not have is said to be unknown, never zero.
/// Nothing here is added up: the verdict is gglib's. A chip opens it
/// (`FitChipButton`).
struct FitWhySheet: View {
    @Environment(\.dismiss) private var dismiss
    let explanation: FitExplanation
    /// When this device's memory was read for the verdict, said under the
    /// figures, which only a verdict asked with that reading comes with.
    let checked: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FitChip(verdict: explanation.verdict)
                    Text(Self.verdictLine(explanation.verdict))
                } header: {
                    if let repo = explanation.repo { Text(repo) }
                }
                if let rationale = explanation.rationale {
                    Section("gglib suggests it") {
                        Text(rationale)
                    }
                }
                if let why = explanation.why {
                    Section {
                        ForEach(Self.lines(why, verdict: explanation.verdict), id: \.self) { Text($0) }
                    } header: {
                        Text("From")
                    } footer: {
                        Text(checked)
                    }
                }
            }
            .navigationTitle(explanation.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The verdict as a sentence.
    nonisolated static func verdictLine(_ verdict: FitVerdict) -> String {
        switch verdict {
        case .fits(let ctx):
            "It fits, with room for \(tokens(ctx)) tokens of context."
        case .tight(let ctx):
            "It fits only with a short context, \(tokens(ctx)) tokens, so a long chat soon fills it."
        case .tooBig(let need, let have):
            "Even with the shortest context it needs \(Sizes.memory(need)), "
                + "and this iPhone gives a model \(Sizes.memory(have))."
        case .unknown(.budget, _):
            "gglib cannot tell until it knows \(words(for: .budget))."
        case .unknown(let missing, true):
            "gglib cannot tell until it knows \(words(for: missing)). The first bytes of the model's file "
                + "ended before they said; once the model is downloaded, gglib reads it from the whole file."
        case .unknown(let missing, false):
            "gglib cannot tell without knowing \(words(for: missing)), and nothing it read about the model says."
        }
    }

    /// One sentence for each figure the verdict was reached from, in order:
    /// the weights, each token of context, this iPhone's budget, and the
    /// trained context. A figure read from the file's header is "not known
    /// yet" only when that header was cut off, the one case a download
    /// reads it from the whole file; otherwise nothing later says it.
    nonisolated static func lines(_ why: FitWhy, verdict: FitVerdict) -> [String] {
        let later = if case .unknown(_, cutOff: true) = verdict { " yet" } else { "" }
        return [
            why.weightsBytes.map { "The weights take \(Sizes.memory($0)) of memory." }
                ?? "How much memory the weights take is not known.",
            why.kvBytesPerToken.map { "Each token of context takes \(Sizes.memory($0)) more." }
                ?? "How much memory each token of context takes is not known\(later).",
            why.budgetBytes.map { "This iPhone gives a model \(Sizes.memory($0)) of its memory." }
                ?? "How much memory this iPhone gives a model is not known.",
            why.trainedCtx.map { "The model was trained on up to \(tokens($0)) tokens of context." }
                ?? "The context the model was trained on is not known\(later).",
        ]
    }

    nonisolated private static func words(for missing: MissingInput) -> String {
        switch missing {
        case .trainedContext: "the context the model was trained on"
        case .kvShape: "how the model keeps its context: its layers and attention heads"
        case .weights: "how large the weights are"
        case .budget: "how much memory this iPhone gives a model"
        }
    }

    nonisolated private static func tokens(_ count: UInt64) -> String {
        count.formatted()
    }
}
