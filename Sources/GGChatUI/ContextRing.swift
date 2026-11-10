import GGChatCore
import SwiftUI

/// How much of the model's context the conversation uses: a small ring that
/// fills as the context does, and a button that opens the counts in a bubble
/// over it. One view for both kinds of chat, shown only while there is a
/// reading to draw.
///
/// The figure always stands beside the ring: a ring a few percent full,
/// alone, read as a spinner still turning. From 90 percent a mark sits in
/// it, so the colour is never the only thing that says it is filling;
/// VoiceOver hears the figure and the word at every level. Plain drawing on
/// the row it sits in: the app's glass is the local composer's three elements
/// and this is not a fourth.
struct ContextRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .callout) private var diameter = 18.0
    @State private var showingCounts = false
    let reading: ContextReading

    var body: some View {
        Button {
            showingCounts = true
        } label: {
            HStack(spacing: 6) {
                ring
                Text(reading.percentText(in: locale))
                    .font(.callout)
                    .monospacedDigit()
            }
            .padding(.vertical, 7)
            .frame(minWidth: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Its own width whatever the row holds: a long model name beside it
        // is the one that gives way.
        .fixedSize()
        .accessibilityLabel("Context")
        .accessibilityValue(reading.spokenValue(in: locale))
        .accessibilityHint("Shows the token counts")
        // A bubble on every screen, the narrowest included, where a popover
        // would otherwise be a sheet: the counts are four lines at most, and
        // a sheet half the screen high for them hid the chat they are about.
        .popover(isPresented: $showingCounts) {
            ContextBubble(reading: reading)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: diameter / 6)
            Circle()
                .trim(from: 0, to: reading.fraction)
                .stroke(reading.severity.tint, style: StrokeStyle(lineWidth: diameter / 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .snappy, value: reading.fraction)
            if reading.showsMark {
                Image(systemName: "exclamationmark")
                    .font(.system(size: diameter / 2, weight: .bold))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

extension ContextReading.Severity {
    /// The flag colours the app uses elsewhere: orange for a warning, red
    /// for what is about to fail.
    fileprivate var tint: Color {
        switch self {
        case .normal: .primary
        case .warning: .orange
        case .danger: .red
        }
    }
}

/// The counts behind the ring, in a bubble pointing at it: the figure large,
/// a bar filled as far as the ring, and the sentences
/// `ContextReading.lines(in:)` gives, word for word (ADR 0008). A tap
/// anywhere outside closes it. The bar says nothing the figure does not, so
/// VoiceOver is left the figure and the sentences.
private struct ContextBubble: View {
    @Environment(\.locale) private var locale
    let reading: ContextReading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            Text(reading.percentText(in: locale))
                .font(.largeTitle.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(reading.severity.tint)
            ProgressView(value: reading.fraction)
                .tint(reading.severity == .normal ? Color.accentColor : reading.severity.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                ContextLines(reading: reading)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }
}

/// The counts as lines, for the ring's bubble or a section of a list: the
/// panel beside the chat on an open iPhone Duo.
struct ContextLines: View {
    @Environment(\.locale) private var locale
    let reading: ContextReading

    var body: some View {
        ForEach(Array(reading.lines(in: locale).enumerated()), id: \.offset) { _, line in
            Text(line)
                .monospacedDigit()
        }
    }
}

#Preview("Ring") {
    VStack(alignment: .trailing, spacing: 12) {
        ForEach([8_200, 23_600, 30_000], id: \.self) { used in
            if let reading = ContextReading(promptTokens: used, completionTokens: 0, contextSize: 32_768) {
                ContextRing(reading: reading)
            }
        }
    }
    .padding()
}
