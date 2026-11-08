import Foundation
import GGChatCore

// A conversation and a provider's default name a model by its key
// (`ModelInfo.key`): a gglib model's catalogue id, which a rename on the Mac
// keeps, and any other server's name for it. Every lookup in a provider's
// list goes by key, and the name shown is the one the list gives it now.
extension AppModel {
    /// The entry that `key` names in the provider's list, or nil when the
    /// list does not name it or has not been read.
    func listed(_ key: String?, on providerID: UUID?) -> ModelInfo? {
        guard let key, let providerID else { return nil }
        return models(for: providerID).first { $0.key == key }
    }

    /// The name the provider's list gives the model that `key` names. The
    /// key itself where the list does not name it, as before the list is
    /// read: for any server but gglib the two are the same.
    public func name(of key: String?, on providerID: UUID?) -> String? {
        guard let key else { return nil }
        return listed(key, on: providerID)?.id ?? key
    }

    /// The key a send in `conversation` names its model by: the
    /// conversation's own, or the provider's default where it has none. On
    /// a list keyed by gglib's ids (`keysByID`), a model the list does not
    /// name gives way to the default too, which `refreshModels` keeps on a
    /// model the list names. So a gglib chat whose model was deleted, or
    /// that was saved by a name before chats were keyed, runs on the default
    /// and is not refused for a model that is not there. Any other server's
    /// chat, This iPhone's included, is sent its own model as it was saved.
    public func model(for conversation: Conversation) -> String? {
        let config = provider(for: conversation)
        guard let chosen = conversation.model else { return config?.defaultModel }
        guard let config, keysByID(config.id), listed(chosen, on: config.id) == nil else { return chosen }
        return config.defaultModel
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

    /// A provider's list as it is kept. This iPhone's is keyed by name: its
    /// library lists what is installed by name, its engine loads a model by
    /// name, and nothing renames a model on this device from elsewhere, so
    /// the id its own gglib lists is dropped.
    func kept(_ models: [ModelInfo], from config: ProviderConfig) -> [ModelInfo] {
        guard config.kind == .onDevice else { return models }
        return models.map { model in
            var byName = model
            byName.gglibID = nil
            byName.profile = nil
            return byName
        }
    }

    /// Whether the provider's list names its models by gglib's catalogue
    /// ids, each of which names a model on one machine alone. This iPhone's
    /// does not (`kept`), nor does any other server's, nor a list not read.
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
