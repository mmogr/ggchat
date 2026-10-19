import CoreGraphics
import GGChatCore
import SwiftUI

/// The Draw switch in the toolbar under a composer's field: pressed, the
/// next message asks its hub for a picture, and it is off again once that
/// message is sent, since it is the draft's and no setting of the chat. One
/// view for both kinds of chat. It is the switch and nothing more: which
/// image model draws is chosen on the line over the field
/// (`DrawsWithLine`).
///
/// A hub that cannot draw dims it and keeps it off, and a press then says
/// why, in the hub's own words: a phone has no pointer to hover for the
/// reason. The state is never colour alone: the brush is filled while on
/// and an outline while off, and VoiceOver hears "On", "Off" or
/// "Unavailable" and the reason.
///
/// A hub that lists several image models and no default draws nothing
/// until one is chosen (`choosing`). The switch is then not dimmed and
/// turns over as it always does, and the line over the field asks for the
/// choice while it is on.
struct DrawToggle: View {
    /// Whether Draw is pressed for the draft.
    let isOn: Bool
    /// Why a picture cannot be asked for now, when it cannot.
    let refusal: String?
    /// Off while a reply is being written.
    let disabled: Bool
    /// Whether the refusal is only that no image model is chosen.
    var choosing = false
    /// Called with the new state when the switch is pressed.
    let set: (Bool) -> Void
    /// Called with the reason when it is pressed and cannot draw.
    let say: (String) -> Void

    /// What a press does.
    enum Press: Equatable {
        case set(Bool)
        case say(String)
    }

    var body: some View {
        let shown = Self.shows(on: isOn, refusal: refusal, choosing: choosing)
        Button(action: press) {
            Image(systemName: Self.symbol(isOn: shown))
                .font(.body)
                .frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(shown ? .accentColor : .gray)
        .opacity(refusal == nil || choosing ? 1 : 0.5)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel("Draw")
        .accessibilityValue(Self.value(isOn: isOn, refusal: refusal, choosing: choosing))
        .accessibilityHint(Self.hint(refusal: refusal, choosing: choosing))
        .accessibilityIdentifier("draw")
    }

    /// What a pointer hovering the switch is told: the reason while it
    /// cannot draw, and while an image model is to be chosen, where.
    private var help: String {
        if choosing { return "Draw a picture for this message, with the image model chosen over the field" }
        return refusal ?? "Draw a picture for this message"
    }

    private func press() {
        switch Self.press(isOn: isOn, refusal: refusal, choosing: choosing) {
        case .set(let on):
            set(on)
        case .say(let why):
            // One left on for a hub that has since stopped drawing.
            set(false)
            say(why)
        }
    }

    /// Whether the switch shows on: pressed, for a hub that can draw or
    /// that only waits for an image model to be chosen.
    static func shows(on isOn: Bool, refusal: String?, choosing: Bool = false) -> Bool {
        isOn && (refusal == nil || choosing)
    }

    /// A press turns the switch over, or says why it cannot be turned on.
    /// One that waits for a choice turns over, and the line over the field
    /// asks for the choice.
    static func press(isOn: Bool, refusal: String?, choosing: Bool = false) -> Press {
        guard let refusal, !choosing else { return .set(!isOn) }
        return .say(refusal)
    }

    /// The brush filled while on, and its outline while off.
    static func symbol(isOn: Bool) -> String {
        isOn ? "paintbrush.pointed.fill" : "paintbrush.pointed"
    }

    /// What VoiceOver says after the label: the state, and while an image
    /// model is to be chosen, that none is. One that waits for a choice is
    /// on or off, not unavailable.
    static func value(isOn: Bool, refusal: String?, choosing: Bool = false) -> String {
        if choosing { return "\(isOn ? "On" : "Off"), no image model chosen" }
        return refusal != nil ? "Unavailable" : isOn ? "On" : "Off"
    }

    /// What VoiceOver says the control does: the reason while it cannot
    /// draw, and while an image model is to be chosen, where.
    static func hint(refusal: String?, choosing: Bool = false) -> String {
        if choosing { return "Asks for a picture with this message. The image model is chosen over the field." }
        return refusal ?? "Asks for a picture with this message"
    }
}

/// The line over a composer's field about the image model. While Draw is
/// on it names the model the picture is drawn with, or asks for one to be
/// chosen where the hub lists several and no default; and whatever Draw
/// shows, it says so when the chat's choice is one the hub cannot draw
/// with, since that wants putting right. Nothing otherwise.
///
/// Where the hub lists image models to choose from (`DrawMenu`) the line
/// is a menu of them, with a chevron to say so, and picking one sets the
/// chat's choice; nothing is sent. A hub with no list leaves it a plain
/// line.
struct DrawsWithLine: View {
    /// Whether Draw is pressed for the draft.
    let isOn: Bool
    /// Why a picture cannot be asked for now, when it cannot.
    let refusal: String?
    /// The name of the image model that draws, where one is known.
    let model: String?
    /// The image models to choose from, when there are any.
    var menu = DrawMenu.none
    /// Whether the refusal is only that no image model is chosen.
    var choosing = false
    /// Whether the refusal is that the chat's choice cannot draw.
    var refused = false
    /// Called with the model picked from the menu, nil for the hub's own.
    var pick: (UInt64?) -> Void = { _ in }

    var body: some View {
        if let line = Self.line(on: isOn, refusal: refusal, model: model, choosing: choosing, refused: refused) {
            if menu.isOffered {
                Menu {
                    DrawMenuRows(menu: menu, pick: pick)
                } label: {
                    label(line, opens: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .accessibilityLabel("Image model")
                .accessibilityValue(model ?? (refused ? "One the Mac no longer lists" : "None chosen"))
                .accessibilityHint("Opens the image models to choose from")
                .accessibilityIdentifier("draws-with")
            } else {
                label(line, opens: false)
                    .accessibilityIdentifier("draws-with")
            }
        }
    }

    private func label(_ line: String, opens: Bool) -> some View {
        HStack(spacing: 4) {
            Label(line, systemImage: "paintbrush.pointed")
            if opens {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, ComposerLayout.inset)
    }

    /// What the line says, or nil for no line. A choice the hub cannot
    /// draw with is said whatever Draw shows; the rest only while Draw is
    /// on, and "Drawing with" only where the hub can draw and named the
    /// model.
    static func line(on isOn: Bool, refusal: String?, model: String?, choosing: Bool = false, refused: Bool = false)
        -> String?
    {
        if refused { return model.map { "Cannot draw with \($0)" } ?? "Pick another image model" }
        guard isOn else { return nil }
        if choosing { return "Choose an image model" }
        guard refusal == nil, let model, !model.isEmpty else { return nil }
        return "Drawing with \(model)"
    }
}

/// A line for a tool the reply called, in either kind of chat.
struct ToolLine: View {
    let line: String

    var body: some View {
        Label(line, systemImage: "wrench.and.screwdriver")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// What a reply shows while a picture is drawn for it, or while it waits
/// behind one: a line that says the stage and the step, a bar for the steps
/// while they are counted, and the latest look at the picture, a small frame
/// drawn larger and smoothed, so it reads as a picture coming into focus and
/// not as blocks. Nothing here is kept (`ToolWork`).
struct ToolWorkView: View {
    @Environment(\.locale) private var locale
    let work: ToolWork

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = work.line(in: locale) {
                // Plain text, which VoiceOver reads as it is shown.
                Text(line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let fraction = work.fraction {
                // The line above says the step, so the bar adds nothing to hear.
                ProgressView(value: fraction)
                    .frame(maxWidth: Self.side)
                    .accessibilityHidden(true)
            }
            if let look = work.preview, let picture = Self.picture(of: look) {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: Self.side, maxHeight: Self.side, alignment: .leading)
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityElement()
                    .accessibilityLabel(Self.label(for: look, in: locale))
            }
        }
    }

    /// How large the look is drawn, on its longer side.
    static let side: CGFloat = 240

    /// The look as a picture, or nil when its bytes are not an image.
    static func picture(of look: PreviewFrame) -> CGImage? {
        ImageDownscale.thumbnail(of: look.data, longEdge: 512)
    }

    /// What VoiceOver says of the look.
    static func label(for look: PreviewFrame, in locale: Locale) -> String {
        guard look.total > 0 else { return "The picture so far" }
        let step = look.step.formatted(.number.locale(locale))
        let total = look.total.formatted(.number.locale(locale))
        return "The picture so far, at step \(step) of \(total)"
    }
}

/// Under a reply to a conversation kept on this device, while it is read: a
/// picture being drawn, in the spinner's place or beside the words, then the
/// pictures made, read from this device's own store, where their bytes are
/// by the time the reply names them.
struct LiveReplyWork: View {
    let live: LiveReply

    var body: some View {
        if !live.work.isEmpty {
            ToolWorkView(work: live.work)
        }
        if !live.made.isEmpty {
            MessageImages(images: live.made, fromHub: false)
        }
    }
}
