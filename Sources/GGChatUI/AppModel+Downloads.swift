import Foundation
import GGChatCore

// Downloading a model chosen in the browser and what follows: room for it,
// each step kept for its row, Cancel, and a finished one marked out of the
// backup and joined to This iPhone's models; the models installed, which
// `AppModel+Removal` removes one of; and the downloads paused while the app
// is away. The library does the downloading; `OnDeviceState` keeps what
// these leave. A failure is said under the row or the section it belongs
// to, for `AppModel+Library`'s reason.
extension AppModel {
    /// Downloads one quantization of `repo`, adding This iPhone first if it
    /// is not there: choosing a model is how a device gets its one such
    /// provider. One gglib found too big for this device is never
    /// downloaded, one already under way or done is not started again, and
    /// one there is no room for is refused under its row.
    ///
    /// The download is followed to its end whether or not the browser stays
    /// open, and each step it reports is kept in `onDevice.downloads`. One
    /// whose steps end short of done or failed is kept as failed, so it can
    /// be chosen again; one called off is forgotten (``cancelDownload(_:)``).
    public func download(_ offer: QuantOffer, of repo: String) {
        let choice = QuantChoice(repo: repo, quantization: offer.name)
        guard runsModelsHere, offer.verdict.allowsDownload else { return }
        switch onDevice.downloads[choice]?.state {
        case nil, .failed?: break
        default: return
        }
        if let reason = whyRefused(offer) {
            fail(choice, reason)
            return
        }
        do {
            try addThisIPhone(defaultModel: nil)
        } catch {
            fail(choice, error.localizedDescription)
            return
        }
        onDevice.downloads[choice] = DownloadProgress(id: "", bytes: 0, total: offer.totalBytes, state: .queued)
        onDevice.following[choice] = Task { await follow(choice) }
    }

    /// What a download whose steps ended before done or failed says.
    static let stoppedShort = "The download stopped before it finished."

    /// What a download says when the models directory could not be made
    /// private and out of the backup.
    static let directoryNotKept =
        "This iPhone could not keep a place for models out of its backups, so nothing was downloaded."

    /// Why `offer` cannot be downloaded to this device, or nil when it can:
    /// the models directory could not be made and marked, or the volume has
    /// less room than the download takes. A volume that will not say leaves
    /// the library to find out. Nothing is checked where no directory is
    /// named, which is only a test's model, since no other runs a model.
    private func whyRefused(_ offer: QuantOffer) -> String? {
        guard let directory = onDevice.modelsDirectory else { return nil }
        guard prepareModelsDirectory() else { return Self.directoryNotKept }
        guard let room = directory.room(), room < offer.totalBytes else { return nil }
        return "There is no room for \(offer.name) on this iPhone: it takes \(Sizes.download(offer.totalBytes)) "
            + "and \(Sizes.download(room)) is free."
    }

    /// Follows one download to its end. Called off, it writes nothing more:
    /// a step the library had already sent would otherwise put a cancelled
    /// row back.
    private func follow(_ choice: QuantChoice) async {
        do {
            let steps = try await library.download(repo: choice.repo, quantization: choice.quantization)
            for await step in steps {
                guard !Task.isCancelled else { return }
                onDevice.downloads[choice] = step
            }
        } catch {
            guard !Task.isCancelled else { return }
            onDevice.following[choice] = nil
            fail(choice, error.localizedDescription)
            return
        }
        guard !Task.isCancelled else { return }
        onDevice.following[choice] = nil
        switch onDevice.downloads[choice]?.state {
        case .done?: await finished()
        case .failed?: break
        default: fail(choice, Self.stoppedShort)
        }
    }

    /// Keeps `choice` as failed with `reason`, at the bytes it had.
    private func fail(_ choice: QuantChoice, _ reason: String) {
        var row = onDevice.downloads[choice] ?? DownloadProgress(id: "", bytes: 0, total: nil, state: .queued)
        row.state = .failed(reason: reason)
        onDevice.downloads[choice] = row
    }

    /// Calls off a download under way. Its row goes, and ending its steps
    /// tells the library to stop it, so Download is offered again. gglib
    /// keeps the bytes it fetched, and the next download of it carries on
    /// from them; the mock deletes its partial file.
    public func cancelDownload(_ choice: QuantChoice) {
        onDevice.following.removeValue(forKey: choice)?.cancel()
        onDevice.downloads[choice] = nil
    }

    /// What a finished download changes: the models directory is marked
    /// again, what is installed is read again, and This iPhone's models are
    /// listed again, so the model joins the list a conversation picks from.
    /// An engine not serving is not started for it: its list is read when a
    /// conversation on it next opens.
    private func finished() async {
        prepareModelsDirectory()
        await refreshInstalled()
        await relistThisIPhone()
    }

    /// Makes the models directory, private and out of the backup, or marks
    /// it again: at launch, before each download and after each finished
    /// one. Answers whether it could; a failure is logged, and refuses the
    /// download it was made for. Where this build runs no model there is
    /// nothing to make.
    @discardableResult
    func prepareModelsDirectory() -> Bool {
        guard runsModelsHere, let directory = onDevice.modelsDirectory else { return true }
        do {
            try directory.prepare()
            return true
        } catch {
            log.log(.error, "could not keep the models directory (\(StoreDirectory.describe(error)))")
            return false
        }
    }

    /// Lists This iPhone's models again, if its engine is serving; see
    /// `catchUp`, which asks nothing of one that is not.
    func relistThisIPhone() async {
        guard let config = providers.first(where: { $0.kind == .onDevice }) else { return }
        await catchUp(config.id, quietly: true, relisting: true)
    }

    /// Reads what is installed, for the browser's "On this iPhone" and the
    /// Settings row. A failure is said in the section.
    public func refreshInstalled() async {
        guard runsModelsHere else { return }
        do {
            onDevice.installed = try await library.installed()
            onDevice.installedFailure = nil
        } catch {
            guard !Task.isCancelled else { return }
            onDevice.installedFailure = error.localizedDescription
        }
    }

    /// What the Settings row says the models on this device take: "2.15 GB",
    /// "None", or that it is not known.
    public var installedSize: String {
        guard let installed = onDevice.installed else {
            return onDevice.installedFailure == nil ? "Reading…" : "Not known"
        }
        guard !installed.isEmpty else { return "None" }
        return Sizes.download(installed.reduce(0) { $0 + $1.bytes })
    }

    /// Pauses every download as the app goes away, or resumes them as it
    /// comes back, once the library has answered the last such call, so it
    /// hears them in the order the scenes came. A turn that a later scene
    /// has made wrong by the time it comes, a resume while the app is away
    /// again or a pause once it is back, is skipped.
    @discardableResult
    func turnDownloads(_ passage: ScenePassage) -> Task<Void, Never> {
        let previous = onDevice.turning
        let turn = Task {
            await previous?.value
            switch passage {
            case .background where isAway: await library.pauseAll()
            case .foreground where !isAway: await library.resumeAll()
            default: break
            }
        }
        onDevice.turning = turn
        return turn
    }
}
