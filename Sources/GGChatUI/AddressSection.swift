import GGChatCore
import SwiftUI

/// A server's address and key: the section Add provider's Server form and
/// `EditProviderView` both show. Where requests will go is shown under it,
/// as ``Redaction/describe(_:)`` writes it.
///
/// The key is a `SecureField` for `AddPipeForm`'s reason.
struct AddressSection: View {
    let mode: ProviderFormMode
    /// What the fields' accessibility identifiers start with: `provider` when
    /// adding, `edit` when editing.
    let idPrefix: String
    @Binding var address: String
    @Binding var apiKey: String

    var body: some View {
        Section {
            TextField("http://127.0.0.1:8080/v1", text: $address)
                .accessibilityIdentifier("\(idPrefix)-address")
                .autocorrectionDisabled()
                #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                #endif
            SecureField(keyPlaceholder, text: $apiKey)
                .accessibilityIdentifier("\(idPrefix)-key")
        } header: {
            Text("Address")
        } footer: {
            Text(addressFooter)
        }
    }

    private var keyPlaceholder: LocalizedStringKey {
        switch mode {
        case .adding: "API key (optional on loopback)"
        case .editing: "New API key"
        }
    }

    /// Adding, an empty field is one nobody has filled in yet. Editing, the
    /// field starts with the stored address, so an empty one is an address
    /// taken away, and is refused like any other that is not one.
    private var addressFooter: String {
        if mode == .adding, address.isEmpty { return "Any OpenAI-compatible server. A bare host gets /v1 appended." }
        guard let url = ProviderConfig.normalizedBaseURL(from: address) else {
            return "That is not an http or https address."
        }
        switch mode {
        case .adding: return "Requests go to \(Redaction.describe(url))."
        case .editing: return "Requests go to \(Redaction.describe(url)). Leave the key blank to keep the one stored."
        }
    }
}
