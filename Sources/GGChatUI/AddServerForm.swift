import GGChatCore
import SwiftUI

/// Add provider's Server: a name, the address of any OpenAI-compatible
/// server and its key. The key is a `SecureField` for `AddPipeForm`'s
/// reason.
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
            Section {
                TextField("http://127.0.0.1:8080/v1", text: $draft.address)
                    .accessibilityIdentifier("provider-address")
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
                SecureField("API key (optional on loopback)", text: $draft.apiKey)
                    .accessibilityIdentifier("provider-key")
            } header: {
                Text("Address")
            } footer: {
                Text(addressFooter)
            }
        }
        .addProviderChrome(failure: draft.failure, canAdd: normalizedURL != nil, add: add)
    }

    private var normalizedURL: URL? {
        ProviderConfig.normalizedBaseURL(from: draft.address)
    }

    private var addressFooter: String {
        if draft.address.isEmpty { return "Any OpenAI-compatible server. A bare host gets /v1 appended." }
        if let url = normalizedURL { return "Requests go to \(Redaction.describe(url))." }
        return "That is not an http or https address."
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
