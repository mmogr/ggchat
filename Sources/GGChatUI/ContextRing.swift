import GGChatCore
import SwiftUI

/// How much of the model's context the conversation uses: a small ring that
/// fills as the context does, and a button that opens the counts. One view
/// for both kinds of chat, shown only while there is a reading to draw.
///
/// From 70 percent the figure stands beside the ring, and from 90 a mark sits
/// in it, so the colour is never the only thing that says it is filling;
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
                if reading.showsFigure {
                    Text(reading.percentText(in: locale))
                        .font(.callout)
                        .monospacedDigit()
                }
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
        .sheet(isPresented: $showingCounts) {
            ContextSheet(reading: reading)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: diameter / 6)
            Circle()
                .trim(from: 0, to: reading.fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: diameter / 6, lineCap: .round))
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

    /// The flag colours the app uses elsewhere: orange for a warning, red
    /// for what is about to fail.
    private var tint: Color {
        switch reading.severity {
        case .normal: .primary
        case .warning: .orange
        case .danger: .red
        }
    }
}

/// The counts behind the ring, as the sentences `ContextReading.lines(in:)`
/// gives: a sheet whose one way out is Done.
private struct ContextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let reading: ContextReading

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(reading.lines(in: locale).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .monospacedDigit()
                }
            }
            .navigationTitle("Context")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 260)
        #endif
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
