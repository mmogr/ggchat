import CoreGraphics
import GGChatCore
import SwiftUI

/// The Draw switch beside a composer's field: pressed, the next message
/// asks its hub for a picture, and it is off again once that message is
/// sent, since it is the draft's and no setting of the chat. One view for
/// both kinds of chat.
///
/// A hub that cannot draw dims it and keeps it off, and a press then says
/// why, in the hub's own words: a phone has no pointer to hover for the
/// reason. The state is never colour alone: the brush is filled while on
/// and an outline while off, and VoiceOver hears "On", "Off" or
/// "Unavailable" and the reason.
///
/// Where the hub lists image models to choose from (`DrawMenu`), holding
/// the switch opens them, and a press still turns it over. Picking one sets
/// the chat's choice and presses Draw for the message being written, since
/// that is what was just asked for; nothing is sent. VoiceOver then also
/// hears which model draws.
struct DrawToggle: View {
    /// Whether Draw is pressed for the draft.
    let isOn: Bool
    /// Why a picture cannot be asked for now, when it cannot.
    let refusal: String?
    /// Off while a reply is being written.
    let disabled: Bool
    /// The image models to choose from, when there are any.
    var menu = DrawMenu.none
    /// Called with the new state when the switch is pressed.
    let set: (Bool) -> Void
    /// Called with the reason when it is pressed and cannot draw.
    let say: (String) -> Void
    /// Called with the model picked from the menu, nil for the hub's own.
    var pick: (UInt64?) -> Void = { _ in }

    /// What a press does.
    enum Press: Equatable {
        case set(Bool)
        case say(String)
    }

    var body: some View {
        let shown = Self.shows(on: isOn, refusal: refusal)
        control
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(shown ? .accentColor : .gray)
            .opacity(refusal == nil ? 1 : 0.5)
            .disabled(disabled)
            .help(refusal ?? "Draw a picture for this message")
            .accessibilityLabel("Draw")
            .accessibilityValue(Self.value(isOn: isOn, refusal: refusal, drawsWith: menu.drawsWith))
            .accessibilityHint(Self.hint(refusal: refusal, hasMenu: menu.isOffered))
            .accessibilityIdentifier("draw")
    }

    /// The switch alone, or with its menu where there is a choice to make.
    @ViewBuilder
    private var control: some View {
        if menu.isOffered {
            Menu {
                DrawMenuRows(menu: menu) { model in
                    pick(model)
                    set(true)
                }
            } label: {
                brush
            } primaryAction: {
                press()
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
        } else {
            Button(action: press) { brush }
        }
    }

    private var brush: some View {
        Image(systemName: Self.symbol(isOn: Self.shows(on: isOn, refusal: refusal)))
            .font(.body)
            .frame(minWidth: 28, minHeight: 28)
    }

    private func press() {
        switch Self.press(isOn: isOn, refusal: refusal) {
        case .set(let on):
            set(on)
        case .say(let why):
            // One left on for a hub that has since stopped drawing.
            set(false)
            say(why)
        }
    }

    /// Whether the switch shows on: pressed, for a hub that can draw.
    static func shows(on isOn: Bool, refusal: String?) -> Bool {
        isOn && refusal == nil
    }

    /// A press turns the switch over, or says why it cannot be turned on.
    static func press(isOn: Bool, refusal: String?) -> Press {
        refusal.map(Press.say) ?? .set(!isOn)
    }

    /// The brush filled while on, and its outline while off.
    static func symbol(isOn: Bool) -> String {
        isOn ? "paintbrush.pointed.fill" : "paintbrush.pointed"
    }

    /// What VoiceOver says after the label: the state, and the image
    /// model that draws where the hub lists some to choose from.
    static func value(isOn: Bool, refusal: String?, drawsWith: String? = nil) -> String {
        let state = refusal != nil ? "Unavailable" : isOn ? "On" : "Off"
        return drawsWith.map { "\(state), draws with \($0)" } ?? state
    }

    /// What VoiceOver says the control does: the reason while it cannot
    /// draw, and where there is a menu, that there is one.
    static func hint(refusal: String?, hasMenu: Bool) -> String {
        let does = refusal ?? "Asks for a picture with this message"
        guard hasMenu else { return does }
        return "\(does.hasSuffix(".") ? String(does.dropLast()) : does). Hold to choose the image model."
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
