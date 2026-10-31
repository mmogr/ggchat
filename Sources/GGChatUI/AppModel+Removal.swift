import Foundation
import GGChatCore

// Removing a model from this iPhone: the engine put down first when it may
// hold the model, the files and row deleted by the library, and the chats
// and the default that had the model left with none. A send naming the model
// while it goes is refused. `OnDeviceState` keeps what is installed and what
// is being removed.
extension AppModel {
    /// Deletes an installed model's files and its row, then reads what is
    /// installed again and lists This iPhone's models again. One no longer
    /// listed as installed is refused before anything is touched.
    ///
    /// The engine is put down first when it may hold the model: while its
    /// status says a model is loading or ready, while a reply goes through
    /// it or waits for it, whose request may name the model before any
    /// status says so, and while a shutdown is already under way, which is
    /// joined, so a removal right after another waits for the engine to be
    /// down too. gglib unlinks the files whatever the engine holds, so a
    /// model left loaded would go on answering from a deleted file, and its
    /// room would not come back until it was let go. A reply through it is
    /// put down as Stop puts it down, and waited for, so what had arrived is
    /// kept. The engine names its model only by name, which two models can
    /// share, so it is put down whichever it holds. The next request serves
    /// it again; an engine that may hold nothing is left serving. While the
    /// removal is under way a send naming the model is refused
    /// (`refusesForARemoval(_:on:)`), so nothing loads it again.
    ///
    /// Any removal also forgets which downloads finished: an installed model
    /// does not say which repository and quantization it came from, so the
    /// browser offers each of them again rather than calling one downloaded
    /// that may be gone. The model leaves This iPhone's list too, which an
    /// engine put down cannot list again.
    ///
    /// Then every conversation on This iPhone that had the model, and This
    /// iPhone's default if it was the model, has none; they are cleared
    /// after the listing, which would otherwise give This iPhone the first
    /// model left as its default. They are matched by name, as the engine
    /// lists them. A removal the library refuses leaves the files, the
    /// list, the chats and the default as they were, and says why under the
    /// section; the engine may have been put down by then.
    public func removeInstalled(_ installed: InstalledModel) async {
        guard onDevice.installed?.contains(where: { $0.id == installed.id }) == true else {
            onDevice.installedFailure = OnDeviceError.notFound.localizedDescription
            return
        }
        onDevice.removing.append(installed.name)
        defer {
            if let index = onDevice.removing.firstIndex(of: installed.name) { onDevice.removing.remove(at: index) }
        }
        if engineMayHoldAModel { await putEngineDownForARemoval() }
        do {
            try await library.remove(id: installed.id)
        } catch {
            onDevice.installedFailure = error.localizedDescription
            return
        }
        onDevice.downloads = onDevice.downloads.filter { $0.value.state != .done }
        if let id = thisIPhoneID { modelsByProvider[id]?.removeAll { $0.id == installed.name } }
        await refreshInstalled()
        await relistThisIPhone()
        forget(model: installed.name)
    }

    /// What a send naming a model being removed says.
    static func beingRemoved(_ model: String) -> String {
        "\(model) is being removed from this iPhone. Pick another model."
    }

    /// Refuses a send on `config` naming `model` while it is being removed,
    /// with a sentence, and answers whether it did: the engine would load it
    /// again from files on their way out.
    func refusesForARemoval(_ model: String, on config: ProviderConfig) -> Bool {
        guard config.kind == .onDevice, onDevice.removing.contains(model) else { return false }
        lastError = Self.beingRemoved(model)
        return true
    }

    /// Whether the engine may hold a model a removal must put it down for:
    /// its status says one is loading or ready, a reply goes through it or
    /// waits for it, or a shutdown is already under way.
    private var engineMayHoldAModel: Bool {
        if engineShuttingDown != nil { return true }
        if let id = thisIPhoneID, !liveReplies(through: id).isEmpty { return true }
        switch engineStatus {
        case .loading?, .ready?: return true
        case .idle?, .failed?, .stopped?, nil: return false
        }
    }

    /// Puts down the replies going through This iPhone, waits for them, and
    /// takes the engine down, for ``removeInstalled(_:)``.
    private func putEngineDownForARemoval() async {
        if let id = thisIPhoneID {
            let replies = liveReplies(through: id).compactMap(\.task)
            for reply in replies { reply.cancel() }
            for reply in replies { await reply.value }
        }
        log.log(.info, "engine put down for a model's removal")
        await shutDownEngine()
    }

    /// Clears `name` from every conversation on This iPhone that has it and
    /// from This iPhone's default, each saved as any other change of model
    /// is.
    private func forget(model name: String) {
        guard var config = providers.first(where: { $0.kind == .onDevice }) else { return }
        for conversation in conversations where conversation.providerID == config.id && conversation.model == name {
            var cleared = conversation
            cleared.model = nil
            update(cleared)
        }
        if config.defaultModel == name {
            config.defaultModel = nil
            updateProvider(config)
        }
    }
}
