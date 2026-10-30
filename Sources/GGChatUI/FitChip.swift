import GGChatCore
import SwiftUI

/// Whether a quantization fits this iPhone, in a few words, as gglib judged
/// it: "Fits · 16K", "Short context · 4K", "Too big for this iPhone" or
/// "Can't tell yet", or "Can't tell" when nothing gglib could read later would
/// say. The figure is the context gglib found room for; nothing here judges
/// anything.
///
/// Plain drawing on a plain fill, as the picture editor's hint is: not
/// glass, and not translucent. One that explains itself (`FitChipButton`)
/// ends in a small info glyph inside the capsule.
struct FitChip: View {
    let verdict: FitVerdict
    var explains = false

    var body: some View {
        label
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: .capsule)
            .accessibilityLabel(Self.words(for: verdict))
    }

    private var label: Text {
        let words = Text("\(Image(systemName: Self.symbol(for: verdict))) \(Self.words(for: verdict))")
        guard explains else { return words }
        return Text("\(words) \(Image(systemName: "info.circle"))")
    }

    /// What VoiceOver adds to a chip that explains itself.
    nonisolated static let hint = "Shows how gglib judged it."

    /// The chip's words for `verdict`.
    nonisolated static func words(for verdict: FitVerdict) -> String {
        switch verdict {
        case .fits(let ctx): "Fits · \(context(ctx))"
        case .tight(let ctx): "Short context · \(context(ctx))"
        case .tooBig: "Too big for this iPhone"
        case .unknown(let missing, let cutOff): cutOff || missing == .budget ? "Can't tell yet" : "Can't tell"
        }
    }

    /// A context as llama.cpp's sizes are spoken, 1,024 tokens to the K:
    /// 16,384 tokens is "16K". Under 1,024 it is the tokens themselves.
    nonisolated static func context(_ tokens: UInt64) -> String {
        tokens >= 1_024 ? "\(tokens / 1_024)K" : "\(tokens)"
    }

    private static func symbol(for verdict: FitVerdict) -> String {
        switch verdict {
        case .fits: "checkmark.circle"
        case .tight: "exclamationmark.circle"
        case .tooBig: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var tint: AnyShapeStyle {
        switch verdict {
        case .fits: AnyShapeStyle(.green)
        case .tight: AnyShapeStyle(.orange)
        case .tooBig: AnyShapeStyle(.red)
        case .unknown: AnyShapeStyle(.secondary)
        }
    }
}

/// A chip that explains itself: pressed, it opens the sheet saying how
/// gglib judged the model (`FitWhySheet`). Its own button in a row with
/// others, so it takes its own taps rather than the row taking them all.
struct FitChipButton: View {
    let explanation: FitExplanation
    /// What a walk finds it by: `fit-<quantization>` on a repository's page,
    /// where the repository goes without saying, and `fit-<repo>/<quant>`
    /// on a suggestion.
    var identifier: String?
    let open: (FitExplanation) -> Void

    var body: some View {
        Button {
            open(explanation)
        } label: {
            FitChip(verdict: explanation.verdict, explains: true)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(FitChip.words(for: explanation.verdict))
        .accessibilityHint(FitChip.hint)
        .accessibilityIdentifier(identifier ?? "fit-\(explanation.name)")
    }
}

/// What the sheet behind a chip says of one model: whose it is, its verdict,
/// the figures gglib reached it from and, for a suggestion, gglib's
/// sentence on why that one. An installed model comes with its verdict
/// alone, judged with no reading the browser took, so its sheet says that
/// verdict and neither figures nor when the device was read.
struct FitExplanation: Identifiable, Equatable {
    /// The repository, or nil for an installed model, which does not say.
    let repo: String?
    /// The quantization, or the installed model's name.
    let name: String
    let verdict: FitVerdict
    let why: FitWhy?
    let rationale: String?

    var id: String { "\(repo ?? "")/\(name)" }

    init(repo: String, offer: QuantOffer) {
        self.repo = repo
        name = offer.name
        verdict = offer.verdict
        why = offer.why
        rationale = nil
    }

    init(suggestion: Suggestion) {
        repo = suggestion.repo
        name = suggestion.quantization
        verdict = suggestion.verdict
        why = suggestion.why
        rationale = suggestion.rationale.isEmpty ? nil : suggestion.rationale
    }

    init(installed: InstalledModel) {
        repo = nil
        name = installed.name
        verdict = installed.verdict
        why = nil
        rationale = nil
    }
}

/// Sizes as the browser says them: a download's as a file's, a memory
/// figure as memory's. Formatting only; every figure is the library's.
enum Sizes {
    nonisolated static func download(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    nonisolated static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
}
