// The words gglib says its states in, worded once there in
// `contracts/vocabulary/words.json` and shown the same way by its GUI, its
// CLI and this app. `VocabularyContractTests` holds every word here to a
// byte-for-byte copy of that file, so a word is changed in gglib first.
//
// Only the two groups this app shows are mirrored: a model's residency (the
// engine pill) and a machine's reach (the away line). gglib's endpoint, key
// and choice words name nothing this app draws.
//
// Words this app says that gglib's vocabulary has none for, kept here:
// - "Loading 40%": gglib's word is "Loading"; the engine on this device
//   reports how far it has got, and the pill says so after the word.
// - "Too big": this device's engine refused the model as too big for it,
//   which gglib, whose engine runs on a Mac, has no state for.
// - "Load it again": not a state but gglib's button for a model that is no
//   longer loaded (`ModelGoneLine` in its GUI), which the pill offers once
//   the model could not be loaded.
// - "<name> is away. Your message will wait.": gglib's away line with no
//   time, for a machine this device has never heard from, as gglib drops
//   "since" when it does not know since when.
// - The pill's pipe words, "Connecting", "Direct", "Relayed" and
//   "Reconnect": how this device's own pipe to a machine is, which gglib
//   says as a reach and a path and not as one word.

/// The words gglib says its states in.
public enum GGLibWords {
    /// How a model is with the engine that would run it.
    public enum Residency: String, CaseIterable, Sendable {
        case loaded
        case loading
        case working
        case reading
        case waiting
        case notLoaded = "not_loaded"

        /// The word gglib shows for it.
        public var word: String {
            switch self {
            case .loaded: "Loaded"
            case .loading: "Loading"
            case .working: "Working"
            case .reading: "Reading"
            case .waiting: "Waiting"
            case .notLoaded: "Not loaded"
            }
        }
    }

    /// Whether a machine can be reached.
    public enum Reach: String, CaseIterable, Sendable {
        case connected
        case away
        case disconnected

        /// The word gglib shows for it.
        public var word: String {
            switch self {
            case .connected: "Connected"
            case .away: "Away"
            case .disconnected: "Disconnected"
            }
        }
    }

    /// gglib's button for a model that is no longer loaded, which loads it
    /// again (`ModelGoneLine` in its GUI). Not in the vocabulary, which
    /// words states and not what a button does.
    public static let loadItAgain = "Load it again"

    /// The line a message to an away machine shows: gglib's "desk is away
    /// since 14:02. Your message will wait." (`ComposerFooter` in its GUI),
    /// and without "since" when nobody knows since when.
    public static func awayLine(_ name: String, since: String?) -> String {
        let away = "\(name) is \(Reach.away.word.lowercased())"
        return "\(since.map { "\(away) since \($0)" } ?? away). Your message will wait."
    }
}
