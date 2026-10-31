import GGChatCore
import SwiftUI

/// Re-credentials a provider that is already there, keeping its id and so
/// its conversations.
///
/// For a pipe this is the repair path. gglib's ticket lasts across restarts,
/// but a machine that has stopped admitting this device, or whose endpoint
/// identity was deleted, has to invite it again, and what that invite shows
/// is pasted here. The alternative was deleting the provider and adding it
/// back — which takes every conversation with it.
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
    /// What the other machine will list this device as, if it keeps a list.
    /// Not `name`, which is what this app calls that machine.
    @State private var deviceName = ""
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
                AddressSection(mode: .editing, idPrefix: "edit", address: $address, apiKey: $apiKey)
            case .pipe:
                PairingSection(
                    mode: .editing, idPrefix: "edit", pairing: $pairing, token: $token,
                    deviceName: $deviceName, shape: pairingShape)
            case .onDevice:
                Section {
                    Text("Models run on this iPhone's own engine, and nothing leaves it.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("On this iPhone")
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

    /// ``PairingReader/readField(_:)`` of the field, which `PairingSection`
    /// shows and Save goes by.
    private var pairingShape: Result<ReadPairing, PairingReadError>? {
        model.pairingReader.readField(pairing)
    }

    private var readPairing: ReadPairing? {
        try? pairingShape?.get()
    }

    private var canSave: Bool {
        switch provider.kind {
        case .openAICompatible: normalizedURL != nil
        case .pipe: pairingShape == nil || readPairing != nil
        case .onDevice: true
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
                guard let readPairing else {
                    // Nothing new pasted: the name, and the token if one was
                    // typed. A token takes effect on the next request, so
                    // there is nothing to redial for.
                    try model.updateProvider(updated, credentials: [.token: token])
                    break
                }
                updated.kind = .pipe(ticketDigest: Ticket.digest(readPairing.ticket))
                if readPairing.hasCode {
                    // The field's text as typed; `mpPair` reads it the same
                    // way, and rebuilding `ticket-code` here would be a
                    // second place that knows the format.
                    pair(updated, pairing: pairing, ticket: readPairing.ticket)
                    return
                }
                try model.updateProvider(updated, credentials: [.ticket: readPairing.ticket, .token: token])
                Task { await model.reconnectPipe(for: updated) }
            case .onDevice:
                // The name is all there is to change: the engine's address
                // and key are its session's.
                try model.updateProvider(updated, credentials: [:])
            }
        } catch {
            failure = error.localizedDescription
            return
        }
        dismiss()
    }

    /// Redeeming is a round trip through the pipe, so the form stays up with
    /// Save replaced by a spinner and leaves only once the key is stored.
    /// A refused code may be dead for good, and this is where that has to be
    /// said — see ``AddPipeForm``, which does the same on the way in.
    private func pair(_ config: ProviderConfig, pairing: String, ticket: String) {
        redeeming = true
        Task {
            do {
                try await model.updatePairedProvider(
                    config, pairing: pairing, ticket: ticket, deviceName: deviceName)
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
