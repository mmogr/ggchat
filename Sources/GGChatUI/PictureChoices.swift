import SwiftUI

/// What a person chooses before a picture is drawn again: the brush while
/// a part is fixed, the words, how much may change, and the image model
/// where the Mac lists more than one that can draw. Each row wraps, so
/// large type stacks the controls and clips none.
struct PictureChoices: View {
    @Bindable var editing: PictureEditing

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if editing.mode == .fix { brush }
            VStack(alignment: .leading, spacing: 4) {
                Text(editing.mode == .fix ? "What the brushed part should show" : "What the picture should show")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("What it should show", text: $editing.words, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("picture-words")
            }
            VStack(alignment: .leading, spacing: 4) {
                Slider(
                    value: $editing.strength, in: PictureEditing.strengths, step: PictureEditing.strengthStep
                ) {
                    Text("How much to change")
                } minimumValueLabel: {
                    Text("Change it a little")
                } maximumValueLabel: {
                    Text("a lot")
                }
                .font(.callout)
                .accessibilityValue(Self.spoken(strength: editing.strength))
            }
            if editing.menu.isOffered { models }
        }
    }

    private var brush: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Brush")
                    .font(.callout)
                    .accessibilityHidden(true)
                Slider(value: $editing.brush, in: editing.brushes) {
                    Text("Brush size")
                }
            }
            ViewThatFits {
                HStack(spacing: 8) { brushButtons }
                VStack(alignment: .leading, spacing: 8) { brushButtons }
            }
        }
    }

    @ViewBuilder
    private var brushButtons: some View {
        Toggle("Rub out", systemImage: "eraser", isOn: $editing.erasing)
            .toggleStyle(.button)
        Button("Undo", systemImage: "arrow.uturn.backward") { editing.undo() }
            .disabled(editing.strokes.isEmpty)
        Button("Clear", systemImage: "trash") { editing.clear() }
            .disabled(editing.strokes.isEmpty)
    }

    private var models: some View {
        Menu {
            DrawMenuRows(menu: editing.menu) { editing.model = $0 }
        } label: {
            Label(
                "Drawn with \(editing.menu.drawsWith ?? "the default image model")", systemImage: "paintbrush.pointed")
        }
        .accessibilityLabel("Image model")
        .accessibilityValue(editing.menu.drawsWith ?? "The default image model")
    }

    /// How VoiceOver says the strength: as a share of a hundred.
    static func spoken(strength: Double) -> String {
        "\(Int((strength * 100).rounded())) percent"
    }
}
