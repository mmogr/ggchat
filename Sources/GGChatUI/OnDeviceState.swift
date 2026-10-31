import GGChatCore
import Observation

/// What the app keeps about running models on this device, beside the engine
/// itself: the model browser open, if one is, shown from the root; each
/// download chosen in it, as its last step said; the models installed; and
/// the models the engine refused as too big; see `AppModel+Library`,
/// `AppModel+Downloads` and `AppModel+Engine+Lifecycle`.
///
/// One holder on `AppModel`, observed property by property, so a download's
/// steps redraw its row and not the root that shows the browser.
@Observable
public final class OnDeviceState {
    public internal(set) var modelBrowser: ModelBrowser?
    /// Each download chosen, whole: its bytes and total for the bar, and its
    /// state. Forgotten when it is called off.
    public internal(set) var downloads: [QuantChoice: DownloadProgress] = [:]
    /// What the library last said is installed, nil until it has been asked,
    /// and why it could not say or remove one.
    public internal(set) var installed: [InstalledModel]?
    public internal(set) var installedFailure: String?
    /// The task following each download under way, which Cancel calls off.
    @ObservationIgnored var following: [QuantChoice: Task<Void, Never>] = [:]
    /// The library's last pause or resume, which the next one waits for.
    @ObservationIgnored var turning: Task<Void, Never>?
    /// Where the models are kept, or nil on the Mac, which keeps none.
    @ObservationIgnored var modelsDirectory = EngineFactory.makeModelsDirectory()
    /// The models the engine refused as too big for this device since it was
    /// last served, by id, which the status pill says. A serve reads the
    /// memory afresh, so it starts with none.
    public internal(set) var tooBig: Set<String> = []
    /// The names of the models being removed, one entry per removal under
    /// way, which a send naming one is refused for (`AppModel+Removal`).
    @ObservationIgnored var removing: [String] = []
    /// Moved on by every shutdown of the engine, so a serve that lands after
    /// one takes itself down: nothing else would.
    @ObservationIgnored var engineGeneration = 0
}

extension DownloadState {
    /// Whether the download is still going, paused included: its row shows
    /// the bar and Cancel.
    var isUnderWay: Bool {
        switch self {
        case .queued, .running, .paused, .verifying: true
        case .done, .failed: false
        }
    }
}
