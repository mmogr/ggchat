import SwiftUI

/// The Tools switch in a chat's top bar: on while a question may call the
/// tools of the MCP servers the paired Mac offers, off while the
/// conversation asks for none. Shown only for a conversation kept here
/// whose paired Mac offers tools; which servers it offers is chosen on the
/// Mac, never here.
///
/// The state is never colour alone: the symbol is filled while on and an
/// outline while off, beside whatever the system draws for a pressed
/// toggle, and VoiceOver hears "on" or "off" in its name, for the reason
/// `ThinkingToggle` gives.
struct ToolsToggle: View {
    /// Whether a question may call the Mac's tools.
    let isOn: Bool
    /// Called with the new state when the switch is pressed.
    let set: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { set($0) })) {
            Label(Self.label(isOn: isOn), systemImage: Self.symbol(isOn: isOn))
        }
        .toggleStyle(.button)
        .accessibilityIdentifier("tools")
        .accessibilityHint("Turns the paired Mac's tools on or off for this conversation")
    }

    /// The tools filled while on, and their outline while off.
    static func symbol(isOn: Bool) -> String {
        isOn ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver"
    }

    /// The switch's name, with its state.
    static func label(isOn: Bool) -> String {
        isOn ? "Tools, on" : "Tools, off"
    }
}

#Preview("Tools") {
    NavigationStack {
        Text("A conversation")
            .toolbar {
                ToolbarItem(placement: .automatic) { ToolsToggle(isOn: true) { _ in } }
                ToolbarItem(placement: .automatic) { ToolsToggle(isOn: false) { _ in } }
            }
    }
}
