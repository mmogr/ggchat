import GGChatCore
import SwiftUI

/// Why a quantization fits this iPhone or does not, in plain words, from the
/// figures gglib reached its verdict with (`FitWhy`): the weights, what each
/// token of context adds, what this iPhone gives a model, and the context
/// the model was trained on. A figure gglib did not have is said to be
/// unknown, never zero. Nothing here is added up: the verdict is gglib's.
struct FitWhySheet: View {
    @Environment(\.dismiss) private var dismiss
    let repo: String
    let offer: QuantOffer
    /// When this device's memory was read for the verdict.
    let checked: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FitChip(verdict: offer.verdict)
                    Text(Self.verdictLine(offer.verdict))
                } header: {
                    Text(repo)
                }
                Section {
                    ForEach(Self.lines(offer.why), id: \.self) { Text($0) }
                } header: {
                    Text("From")
                } footer: {
                    Text(checked)
                }
            }
            .navigationTitle(offer.name)
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
        case .unknown(let missing):
            "gglib cannot tell until it knows \(words(for: missing)). "
                + "Once the model is downloaded, gglib reads that from its file."
        }
    }

    /// One sentence for each figure the verdict was reached from, in order:
    /// the weights, each token of context, this iPhone's budget, and the
    /// trained context.
    nonisolated static func lines(_ why: FitWhy) -> [String] {
        [
            why.weightsBytes.map { "The weights take \(Sizes.memory($0)) of memory." }
                ?? "How much memory the weights take is not known yet.",
            why.kvBytesPerToken.map { "Each token of context takes \(Sizes.memory($0)) more." }
                ?? "How much memory each token of context takes is not known yet.",
            why.budgetBytes.map { "This iPhone gives a model \(Sizes.memory($0)) of its memory." }
                ?? "How much memory this iPhone gives a model is not known.",
            why.trainedCtx.map { "The model was trained on up to \(tokens($0)) tokens of context." }
                ?? "The context the model was trained on is not known yet.",
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
