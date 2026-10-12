import Foundation
import GGChatCore

#if os(iOS)
    import UIKit
#endif

/// Why a drawn picture could not be kept, in words to show.
struct PictureKeepFailure: Error, Equatable {
    let words: String
}

/// What fixing or redoing a picture needs of the chat it is in: the
/// picture's bytes, the Mac that draws, and how a result is kept there.
struct PictureWork {
    /// The picture's own bytes, or nil when they are not to hand.
    var bytes: () -> Data?
    /// Draws it again on the chat's Mac.
    var render: (PictureRedraw) -> AsyncStream<RedrawEvent>
    /// Stores a drawn picture where the chat's pictures are stored, and
    /// answers how it is named there.
    var store: (Data) async throws(PictureKeepFailure) -> ImageRef
    /// Puts the stored picture in the chat, after the one it was made from.
    var join: (ImageRef, Data) async throws(PictureKeepFailure) -> Void
    /// Told true when a render starts and false when it ends, so the device
    /// does not lock under it.
    var stayAwake: @MainActor (Bool) -> Void = { _ in }
}

/// The device's own lock for want of a touch. A render takes minutes with
/// nothing to press, and a phone that locks under one sends the app to the
/// background, which hangs up the pipe the render is read through. A Mac
/// has no such timer for an app to hold, so this does nothing there.
enum IdleTimer {
    /// Holds the lock off while `on`, and gives it back otherwise.
    static func hold(_ on: Bool) {
        #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}
