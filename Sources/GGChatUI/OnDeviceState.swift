import GGChatCore
import Observation

/// What the app keeps about running models on this device, beside the engine
/// itself: the model browser open, if one is, shown from the root, and where
/// each download chosen in it last said it was; see `AppModel+Library`.
///
/// One holder on `AppModel`, observed property by property, so a download's
/// steps redraw its row and not the root that shows the browser.
@Observable
public final class OnDeviceState {
    public internal(set) var modelBrowser: ModelBrowser?
    public internal(set) var downloads: [QuantChoice: DownloadState] = [:]
}
