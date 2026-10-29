import GGChatCore
import GGLib

// gglib's records said in the app's own words. Every translation from the
// binding lives in this module, as modelpipe's live in GGChatPipe, so a
// gglib release that changed one is caught here, in one place, and nothing
// above this module names a binding type.
extension GGLibBuild {
    /// What the gglib framework this app links says it is.
    ///
    /// The first call into the framework is also where uniffi checks the
    /// vendored binding against it, its contract version and every API
    /// checksum, and traps on a mismatch; so whatever calls this first proves
    /// the pair on the device it runs on.
    public static func linked() -> GGLibBuild {
        GGLibBuild(buildInfo())
    }

    /// The binding's record, field for field.
    init(_ info: BuildInfo) {
        self.init(gglibVersion: info.gglibVersion, uniffiVersion: info.uniffiVersion, llamaPin: info.llamaPin)
    }
}
