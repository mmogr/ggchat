import GGChatCore
import SwiftUI

/// Add provider's Server: a name, and the address of any OpenAI-compatible
/// server and its key (`AddressSection`).
struct AddServerForm<Top: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The fields, kept by the sheet, so a change of kind loses nothing.
    @Binding var draft: ProviderDraft
    let top: Top

    init(draft: Binding<ProviderDraft>, @ViewBuilder top: () -> Top) {
        _draft = draft
        self.top = top()
    }

    var body: some View {
        Form {
            top
            AddProviderNameSection(name: $draft.name)
            AddressSection(mode: .adding, idPrefix: "provider", address: $draft.address, apiKey: $draft.apiKey)
        }
        .addProviderChrome(failure: draft.failure, canAdd: normalizedURL != nil, add: add)
    }

    private var normalizedURL: URL? {
        ProviderConfig.normalizedBaseURL(from: draft.address)
    }

    /// Adds, and only dismisses if that worked. A sheet that closes on a
    /// failure takes the reason with it.
    private func add() {
        guard let url = normalizedURL else { return }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespaces)
        draft.failure = nil
        do {
            let config = ProviderConfig(
                name: trimmedName.isEmpty ? (url.host() ?? "Server") : trimmedName,
                kind: .openAICompatible(baseURL: url))
            try model.addProvider(config, credentials: [.apiKey: draft.apiKey])
        } catch {
            draft.failure = error.localizedDescription
            return
        }
        dismiss()
    }
}
