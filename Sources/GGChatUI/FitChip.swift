import GGChatCore
import SwiftUI

/// Whether a quantization fits this iPhone, in a few words, as gglib judged
/// it: "Fits · 16K", "Short context · 4K", "Too big for this iPhone" or
/// "Can't tell yet". The figure is the context gglib found room for; nothing
/// here judges anything.
///
/// Plain drawing on a plain fill, as the picture editor's hint is: not
/// glass, and not translucent.
struct FitChip: View {
    let verdict: FitVerdict

    var body: some View {
        Text("\(Image(systemName: Self.symbol(for: verdict))) \(Self.words(for: verdict))")
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: .capsule)
            .accessibilityLabel(Self.words(for: verdict))
    }

    /// The chip's words for `verdict`.
    nonisolated static func words(for verdict: FitVerdict) -> String {
        switch verdict {
        case .fits(let ctx): "Fits · \(context(ctx))"
        case .tight(let ctx): "Short context · \(context(ctx))"
        case .tooBig: "Too big for this iPhone"
        case .unknown: "Can't tell yet"
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
