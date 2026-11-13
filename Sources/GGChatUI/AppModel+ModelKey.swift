import Foundation
import GGChatCore

// A conversation and a provider's default name a model by its key
// (`ModelInfo.key`): a gglib model's catalogue id, which a rename on the Mac
// keeps and which tells two quantizations of one model apart, and any other
// server's name for it. Every lookup in a provider's list goes by key, and
// the name shown is the one the list gives it now. This iPhone's models are
// keyed by gglib's id too, and its list of record is what its library has
// installed (`onDevice.installed`), which is read without serving the
// engine.
extension AppModel {
    /// The entry that `key` names in the provider's list, or nil when the
    /// list does not name it or has not been read.
    func listed(_ key: String?, on providerID: UUID?) -> ModelInfo? {
        guard let key, let providerID else { return nil }
        return models(for: providerID).first { $0.key == key }
    }

    /// The model installed on this device that `key` names by its id, or
    /// nil when none does or what is installed has not been read.
    func installedModel(_ key: String?) -> InstalledModel? {
        guard let id = key.flatMap({ Int64($0) }) else { return nil }
        return onDevice.installed?.first { $0.id == id }
    }

    /// The name the provider's list gives the model that `key` names: on
    /// This iPhone the model installed under that id, with its quantization
    /// (`InstalledModel.shownName`). The key
    /// itself where nothing names it, as before the list is read: for any
    /// server but gglib the two are the same.
    public func name(of key: String?, on providerID: UUID?) -> String? {
        guard let key else { return nil }
        if isThisIPhone(providerID), let installed = installedModel(key) { return installed.shownName }
        return listed(key, on: providerID)?.id ?? key
    }

    /// Whether `providerID` is This iPhone's.
    func isThisIPhone(_ providerID: UUID?) -> Bool {
        guard let providerID else { return false }
        return providers.first { $0.id == providerID }?.kind == .onDevice
    }

    /// Whether a chat on the provider may send `key`: any key on a list not
    /// keyed by gglib's ids or not read yet, and otherwise one the list
    /// names. On This iPhone, an id, of a model its library has installed
    /// once that has been read; never a name, as one saved before the phone
    /// was keyed by id.
    private func names(_ key: String, on config: ProviderConfig) -> Bool {
        if config.kind == .onDevice {
            guard engineID(of: key) != nil else { return false }
            guard onDevice.installed != nil else { return true }
            return installedModel(key) != nil
        }
        return !keysByID(config.id) || listed(key, on: config.id) != nil
    }

    /// The library id of the model that `key` names on This iPhone, as the
    /// engine's status names it: the listed entry's, else what comes before
    /// a profile's colon (`<id>:<profile>`), read as an id. Nil for a name.
    func engineID(of key: String) -> Int64? {
        listed(key, on: thisIPhoneID)?.gglibID ?? key.split(separator: ":").first.flatMap { Int64($0) }
    }

    /// The key a send in `conversation` names its model by: the
    /// conversation's own, or the provider's default where it has none. On
    /// a list keyed by gglib's ids (`keysByID`), a model the list does not
    /// name gives way to the default too, which `refreshModels` keeps on a
    /// model the list names. So a gglib chat whose model was deleted, or
    /// that was saved by a name before chats were keyed, runs on the default
    /// and is not refused for a model that is not there. Any other server's
    /// chat is sent its own model as it was saved.
    ///
    /// On This iPhone the default must be installed too, or there is no
    /// model: a removal clears the chats and the default that had the
    /// model, and a chat or a default saved by a name, before the phone was
    /// keyed by id, asks for a model rather than running on another.
    public func model(for conversation: Conversation) -> String? {
        guard let config = provider(for: conversation) else { return conversation.model }
        if let chosen = conversation.model, names(chosen, on: config) { return chosen }
        guard config.kind == .onDevice else { return config.defaultModel }
        return config.defaultModel.flatMap { names($0, on: config) ? $0 : nil }
    }

    /// The name of the model a send in `conversation` asks for, which the
    /// model pill and the chat's panel show.
    public func shownModelName(for conversation: Conversation) -> String? {
        name(of: model(for: conversation), on: conversation.providerID)
    }

    /// The key of the model a run's report names. gglib reports the string
    /// the run was sent, which is a key; a report that names a model by the
    /// name its list gives is taken as that entry's key, and one the list
    /// does not name is kept as it came.
    func key(naming model: String, on providerID: UUID?) -> String {
        if listed(model, on: providerID) != nil { return model }
        guard let providerID else { return model }
        return models(for: providerID).first { $0.id == model }?.key ?? model
    }

    /// Whether the provider's list names its models by gglib's catalogue
    /// ids, each of which names a model on one machine alone: a gglib
    /// machine's and This iPhone's, once read; no other server's.
    func keysByID(_ providerID: UUID?) -> Bool {
        guard let providerID else { return false }
        return models(for: providerID).contains { $0.gglibID != nil }
    }

    /// The key a reply's reading is left under, from the model a run's
    /// report names and the key the reply was `sent`. gglib reports the
    /// catalogue name the run went to: a profile variant's base name, and the
    /// bare name of models that share one, which no entry of the list is.
    /// So on a list keyed by id, a report that names the model `sent` names,
    /// or that names no entry, keeps `sent`. One that names another model, as
    /// a reply read on after its chat moved to another model does, is that
    /// model's key, and so is any report on another list.
    func key(reported report: String?, sent: String?, on providerID: UUID?) -> String? {
        guard let report else { return sent }
        guard let sent, let providerID, keysByID(providerID) else { return key(naming: report, on: providerID) }
        let named = models(for: providerID).filter { $0.key == report || $0.id == report }
        if named.isEmpty { return sent }
        if let id = listed(sent, on: providerID)?.gglibID, named.contains(where: { $0.gglibID == id }) { return sent }
        return key(naming: report, on: providerID)
    }
}

extension InstalledModel {
    /// How the app names a model on this device: "Qwen3 4B · Q4_K_M", its
    /// name and the quantization gglib labels it with, which tells two
    /// quantizations of one model apart; the name alone where gglib knows
    /// no label.
    public var shownName: String {
        guard let quantization else { return name }
        return "\(name) · \(quantization)"
    }

    /// The label the browser offers this model's variant by: the one its
    /// download asked for, or its shown type where gglib kept no label.
    var offeredLabel: String? { variantLabel ?? quantization }

    /// Whether this is the variant `label` of `repo` as the browser offers
    /// it.
    func isDownload(of repo: String, _ label: String) -> Bool {
        self.repo == repo && offeredLabel == label
    }
}
