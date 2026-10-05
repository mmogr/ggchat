import SwiftUI

/// The Thinking switch in a chat's top bar: on while the model thinks before
/// it answers, off while the conversation asks it not to. One view for both
/// kinds of chat, shown only for a model gglib lists as one that thinks.
///
/// The state is never colour alone: the symbol is filled while on and an
/// outline while off, beside whatever the system draws for a pressed toggle,
/// and VoiceOver hears "On" or "Off". It sits in the toolbar, so its glass
/// is the system's and not one of the composer's three.
struct ThinkingToggle: View {
    /// Whether the model thinks.
    let isOn: Bool
    /// Called with the new state when the switch is pressed.
    let set: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { set($0) })) {
            Label("Thinking", systemImage: Self.symbol(isOn: isOn))
        }
        .toggleStyle(.button)
        .accessibilityValue(Self.value(isOn: isOn))
        .accessibilityHint("Turns the model's thinking on or off for this conversation")
    }

    /// The brain filled while the model thinks, and its outline while not.
    static func symbol(isOn: Bool) -> String {
        isOn ? "brain.fill" : "brain"
    }

    /// What VoiceOver says after the label.
    static func value(isOn: Bool) -> String {
        isOn ? "On" : "Off"
    }
}

#Preview("Thinking") {
    NavigationStack {
        Text("A conversation")
            .toolbar {
                ToolbarItem(placement: .automatic) { ThinkingToggle(isOn: true) { _ in } }
                ToolbarItem(placement: .automatic) { ThinkingToggle(isOn: false) { _ in } }
            }
    }
}
