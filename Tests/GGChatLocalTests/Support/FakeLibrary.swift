import GGLib
import Synchronization

/// gglib's library with no folder, no database and no network behind it:
/// canned answers, or one error every call that can throw throws, a serve
/// that answers what a test hands it, and a count of what it was asked.
///
/// Conforms to the protocol uniffi generates beside the class, as
/// `GglibLibrary` holds the library by it.
final class FakeLibrary: LibraryProtocol {
    struct Asked {
        var readings: [GGLib.DeviceReading] = []
        var searches: [String] = []
        var removed: [Int64] = []
        var pauses = 0
        var resumes = 0
    }

    /// What every call that can throw throws, or nil to answer.
    let failure: GglibError?
    let suggestions: [GGLib.Suggestion]
    let page: GGLib.SearchPage
    let offers: [GGLib.QuantOffer]
    let models: [GGLib.InstalledModel]
    /// What a download hands back, or nil for none.
    let watch: FakeWatch?
    /// What every serve answers: a server, or a thrown error.
    let serving: @Sendable () throws -> Server
    private let asked = Mutex(Asked())

    init(
        failure: GglibError? = nil, suggestions: [GGLib.Suggestion] = [],
        page: GGLib.SearchPage = GGLib.SearchPage(hits: [], nextCursor: nil), offers: [GGLib.QuantOffer] = [],
        models: [GGLib.InstalledModel] = [], watch: FakeWatch? = nil,
        serving: @escaping @Sendable () throws -> Server = { throw GglibError.EngineUnavailable }
    ) {
        self.failure = failure
        self.suggestions = suggestions
        self.page = page
        self.offers = offers
        self.models = models
        self.watch = watch
        self.serving = serving
    }

    /// What the library has been asked so far.
    var said: Asked { asked.withLock { $0 } }

    private func answer() throws {
        if let failure { throw failure }
    }

    /// Throws its failure, or else hands back its watch, or says it has no
    /// download to give when it was made with none.
    func download(repo: String, quantization: String) async throws -> DownloadWatch {
        try answer()
        guard let watch else { throw GglibError.Internal(message: "the fake library downloads nothing") }
        return watch
    }

    func installed() async throws -> [GGLib.InstalledModel] {
        try answer()
        return models
    }

    func pauseAll() async {
        asked.withLock { $0.pauses += 1 }
    }

    func quantizations(repo: String, reading: GGLib.DeviceReading) async throws -> [GGLib.QuantOffer] {
        asked.withLock { $0.readings.append(reading) }
        try answer()
        return offers
    }

    func remove(id: Int64) async throws {
        try answer()
        asked.withLock { $0.removed.append(id) }
    }

    func resumeAll() async {
        asked.withLock { $0.resumes += 1 }
    }

    func search(query: String, cursor: String?) async throws -> GGLib.SearchPage {
        asked.withLock { $0.searches.append(query) }
        try answer()
        return page
    }

    func serve(reading: GGLib.DeviceReading) async throws -> Server {
        asked.withLock { $0.readings.append(reading) }
        return try serving()
    }

    func suggested(reading: GGLib.DeviceReading) -> [GGLib.Suggestion] {
        asked.withLock { $0.readings.append(reading) }
        return suggestions
    }
}

/// Counts the opens of a library, each answering the next of `answers`: a
/// library, or an error the open throws.
final class Opener: Sendable {
    private let answers: Mutex<[Result<FakeLibrary, GglibError>]>
    private let count = Mutex(0)

    init(_ answers: [Result<FakeLibrary, GglibError>]) {
        self.answers = Mutex(answers)
    }

    var opens: Int { count.withLock { $0 } }

    func open() throws -> any LibraryProtocol {
        count.withLock { $0 += 1 }
        return try answers.withLock { $0.removeFirst() }.get()
    }
}
