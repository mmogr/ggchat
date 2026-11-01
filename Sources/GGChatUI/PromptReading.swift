import GGChatCore
import SwiftUI

/// A prompt being read before the reply's first word: a bar filled by the
/// tokens read of the prompt's, those from the cache among them, so a chat
/// gglib still holds starts partway, and the count under it. Every figure
/// is gglib's; this only draws them.
struct PromptReading: View {
    @Environment(\.locale) private var locale
    let progress: PromptProgress

    var body: some View {
        let count = Self.count(for: progress, in: locale)
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(min(progress.processed, progress.total)), total: Double(max(progress.total, 1)))
                .frame(maxWidth: 280)
                .accessibilityLabel("Reading the prompt")
                .accessibilityValue(count)
            // The bar's label and value already say it to VoiceOver.
            Text("Reading \(count)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
    }

    /// "8,200 of 11,000 tokens", in `locale`'s digits: the bar's value, and
    /// the line under it after "Reading".
    static func count(for progress: PromptProgress, in locale: Locale) -> String {
        let processed = progress.processed.formatted(.number.locale(locale))
        let total = progress.total.formatted(.number.locale(locale))
        return "\(processed) of \(total) tokens"
    }
}
