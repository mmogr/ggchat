import SwiftUI

extension StoreNotice {
    /// One line of the notice.
    public enum Line: Hashable, Sendable {
        /// Red, with no button to close it.
        case keptInMemory
        /// The line about an older store, which a button closes.
        case olderStore

        /// The words on screen, and the line's accessibility label.
        public var sentence: String {
            switch self {
            case .keptInMemory:
                "ggchat could not open your saved conversations. They have not been deleted. "
                    + "Conversations and providers you add now will not be saved."
            case .olderStore:
                "An older version of ggchat was run on this device and kept saved conversations of its own, "
                    + "if it made any. They are not shown here. Nothing has been deleted."
            }
        }
    }

    /// The label of the button that closes the older store's line, on screen
    /// and as its accessibility label.
    public static let closeOlderStoreLine = "Hide this message for now"
}

/// The lines of the store's notice the window shows. It saves nothing, so
/// nothing carries a closed line past this launch.
@Observable
public final class ShownStoreNotice {
    private let notice: StoreNotice?
    private var olderStoreLineClosed = false

    public init(_ notice: StoreNotice?) {
        self.notice = notice
    }

    /// The red line first, then the older store's line until it is closed.
    public var lines: [StoreNotice.Line] {
        var lines: [StoreNotice.Line] = []
        if notice?.keptInMemory == true {
            lines.append(.keptInMemory)
        }
        if notice?.olderStoreLeftBehind == true && !olderStoreLineClosed {
            lines.append(.olderStore)
        }
        return lines
    }

    /// Closes the older store's line. The red line has no way to close.
    public func closeOlderStoreLine() {
        olderStoreLineClosed = true
    }
}

/// What opening the store had to tell the person, which `RootView` lays out
/// below the split view, so what is above it is shortened rather than
/// covered. Seen, not tested, on iOS 27 simulators (an iPhone 16 and an
/// 11-inch iPad Pro): it covered none of the model pill, the composer or
/// Send, with the keyboard down or up. With both lines up at the largest
/// accessibility text size, the iPhone cut each sentence short. Not an alert:
/// the red line has no button to close it, and the line about an older store
/// has one. Plain text in the system's styles, with no glass of its own.
struct StoreNoticeView: View {
    let notice: ShownStoreNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(notice.lines, id: \.self) { line in
                switch line {
                case .keptInMemory:
                    sentence(line, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                case .olderStore:
                    sentence(line, systemImage: "info.circle")
                    Button(StoreNotice.closeOlderStoreLine, action: notice.closeOlderStoreLine)
                        .accessibilityLabel(StoreNotice.closeOlderStoreLine)
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    /// The sentence is given as the accessibility label, with the symbol's
    /// ignored. What VoiceOver then reads is not checked.
    private func sentence(_ line: StoreNotice.Line, systemImage: String) -> some View {
        Label(line.sentence, systemImage: systemImage)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.sentence)
    }
}
