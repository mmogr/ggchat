import GGChatCore
import SwiftUI

/// Re-credentials a provider that is already there, keeping its id and so
/// its conversations.
///
/// For a pipe this is the ordinary path rather than a repair: `gglib remote
/// enable` mints a fresh ticket every session, so a machine that has been
/// re-enabled has to be re-pasted here, and the alternative was deleting the
/// provider and adding it back — which takes every conversation with it.
///
/// A credential field left blank keeps what is stored. Nothing is read back
/// into the form: a token that is already in the Keychain has no business
/// appearing on a settings screen, even behind a `SecureField`.
struct EditProviderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var apiKey = ""
    @State private var pairing = ""
    @State private var token = ""
    @State private var failure: String?
    /// True from the moment a code goes out until the key comes back.
    @State private var redeeming = false
    private let provider: ProviderConfig

    init(provider: ProviderConfig) {
        self.provider = provider
        _name = State(initialValue: provider.name)
        if case .openAICompatible(let baseURL) = provider.kind {
            _address = State(initialValue: baseURL.absoluteString)
        } else {
            _address = State(initialValue: "")
        }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("gglib on the Mac", text: $name)
                    .accessibilityIdentifier("edit-name")
            }
            switch provider.kind {
            case .openAICompatible:
                Section {
                    TextField("http://127.0.0.1:8080/v1", text: $address)
                        .accessibilityIdentifier("edit-address")
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                        #endif
                    SecureField("New API key", text: $apiKey)
                        .accessibilityIdentifier("edit-key")
                } header: {
                    Text("Address")
                } footer: {
                    Text(addressFooter)
                }
            case .pipe:
                Section {
                    TextField("pipe…-483920", text: $pairing, axis: .vertical)
                        .accessibilityIdentifier("edit-ticket")
                        .lineLimit(3...6)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                    // A code is redeemed for the token, so asking for one as
                    // well would be asking for the thing the code fetches.
                    if parsedPairing?.code == nil {
                        SecureField("New token", text: $token)
                            .accessibilityIdentifier("edit-token")
                    }
                } header: {
                    Text("Pairing string")
                } footer: {
                    pairingFooter
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(provider.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if redeeming {
                    ProgressView()
                } else {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var normalizedURL: URL? {
        ProviderConfig.normalizedBaseURL(from: address)
    }

    private var addressFooter: String {
        guard let url = normalizedURL else { return "That is not an http or https address." }
        return "Requests go to \(Redaction.describe(url)). Leave the key blank to keep the one stored."
    }

    /// Nil while the field is empty, which here means "keep what is stored"
    /// rather than "not typed yet".
    private var pairingShape: Result<PairingString, PairingStringError>? {
        pairing.isEmpty ? nil : PairingString.parse(pairing)
    }

    private var parsedPairing: PairingString? {
        guard case .success(let parsed)? = pairingShape else { return nil }
        return parsed
    }

    @ViewBuilder
    private var pairingFooter: some View {
        switch pairingShape {
        case nil:
            Text("Blank keeps the ticket and token already stored. Paste what `gglib remote enable` printed last.")
        case .success(let parsed) where parsed.code != nil:
            Label(
                "A ticket and a code. The code is redeemed once, for that machine's key.",
                systemImage: "checkmark.circle")
        case .success:
            Label("Looks like a ticket. Leave the token blank to keep the one stored.", systemImage: "checkmark.circle")
        case .failure(let error):
            Label(error.errorDescription ?? "", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var canSave: Bool {
        switch provider.kind {
        case .openAICompatible: normalizedURL != nil
        case .pipe: pairing.isEmpty || parsedPairing != nil
        }
    }

    /// Saves, and only leaves if that worked. A form that closes on a
    /// failure takes the reason with it.
    private func save() {
        failure = nil
        var updated = provider
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        updated.name = trimmed.isEmpty ? provider.name : trimmed
        do {
            switch provider.kind {
            case .openAICompatible:
                guard let url = normalizedURL else { return }
                updated.kind = .openAICompatible(baseURL: url)
                try model.updateProvider(updated, credentials: [.apiKey: apiKey])
            case .pipe:
                guard let parsed = parsedPairing else {
                    // Nothing new pasted: the name, and the token if one was
                    // typed. A token takes effect on the next request, so
                    // there is nothing to redial for.
                    try model.updateProvider(updated, credentials: [.token: token])
                    break
                }
                updated.kind = .pipe(ticketDigest: Ticket.digest(parsed.ticket))
                if let code = parsed.code {
                    pair(updated, ticket: parsed.ticket, code: code)
                    return
                }
                try model.updateProvider(updated, credentials: [.ticket: parsed.ticket, .token: token])
                Task { await model.reconnectPipe(for: updated) }
            }
        } catch {
            failure = error.localizedDescription
            return
        }
        dismiss()
    }

    /// Redeeming is a round trip through the pipe, so the form stays up with
    /// Save replaced by a spinner and leaves only once the key is stored.
    /// A refused code is spent either way, and this is where that has to be
    /// said — see ``AddProviderView``, which does the same on the way in.
    private func pair(_ config: ProviderConfig, ticket: String, code: String) {
        redeeming = true
        Task {
            do {
                try await model.updatePairedProvider(config, ticket: ticket, code: code)
                dismiss()
            } catch {
                failure = error.localizedDescription
                redeeming = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        EditProviderView(provider: AppModel.preview.providers[1])
            .environment(AppModel.preview)
    }
}
