import GGChatCore
import SwiftUI

/// URL and key, or the pairing string a machine printed. Its shape is
/// checked as it is typed and the reason it fails is shown as a sentence.
///
/// A pairing string is `ticket-code` the first time and a bare ticket after
/// that, so the token field is asked for only when there is no code to
/// redeem for one — a code is a token this device has not been given yet.
///
/// The key and token are `SecureField`s, which is what they are. iOS may
/// offer to save them to the password manager afterwards; there is no
/// content type that means "secret, never offer to save", and the
/// alternatives all show the secret in the clear.
struct AddProviderView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case server = "Server"
        case pipe = "Pipe"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.server
    @State private var name = ""
    @State private var address = ""
    @State private var apiKey = ""
    @State private var pairing = ""
    @State private var token = ""
    @State private var failure: String?
    /// True from the moment a code goes out until the key comes back.
    @State private var redeeming = false
    #if os(iOS)
        @State private var scanning = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) {
                    ForEach(Kind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                Section("Name") {
                    TextField("gglib on the Mac", text: $name)
                        .accessibilityIdentifier("provider-name")
                }

                switch kind {
                case .server:
                    Section {
                        TextField("http://127.0.0.1:8080/v1", text: $address)
                            .accessibilityIdentifier("provider-address")
                            .autocorrectionDisabled()
                            #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                            #endif
                        SecureField("API key (optional on loopback)", text: $apiKey)
                            .accessibilityIdentifier("provider-key")
                    } header: {
                        Text("Address")
                    } footer: {
                        Text(addressFooter)
                    }
                case .pipe:
                    Section {
                        TextField("pipe…-483920", text: $pairing, axis: .vertical)
                            .accessibilityIdentifier("provider-ticket")
                            .lineLimit(3...6)
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            #if os(iOS)
                                .textInputAutocapitalization(.never)
                            #endif
                        // A code is redeemed for the token, so asking for
                        // one as well would be asking for the thing the
                        // code exists to fetch.
                        if parsedPairing?.code == nil {
                            SecureField("Token", text: $token)
                                .accessibilityIdentifier("provider-token")
                        }
                        #if os(iOS)
                            if ScanTicketView.isSupported {
                                Button("Scan ticket", systemImage: "qrcode.viewfinder") { scanning = true }
                            }
                        #endif
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
            .navigationTitle("Add provider")
            #if os(iOS)
                .sheet(isPresented: $scanning) {
                    ScanTicketView { scanned in
                        pairing = scanned
                        scanning = false
                    }
                }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if redeeming {
                        ProgressView()
                    } else {
                        Button("Add") { add() }
                            .disabled(!canAdd)
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 380)
        #endif
    }

    private var normalizedURL: URL? {
        ProviderConfig.normalizedBaseURL(from: address)
    }

    private var addressFooter: String {
        if address.isEmpty { return "Any OpenAI-compatible server. A bare host gets /v1 appended." }
        if let url = normalizedURL { return "Requests go to \(Redaction.describe(url))." }
        return "That is not an http or https address."
    }

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
            Text("Paste what `gglib remote enable` printed, or scan it. A bare ticket works once the key is stored.")
        case .success(let parsed) where parsed.code != nil:
            Label(
                "A ticket and a code. The code is redeemed once, for that machine's key.",
                systemImage: "checkmark.circle")
        case .success:
            Label("Looks like a ticket. The token is separate.", systemImage: "checkmark.circle")
        case .failure(let error):
            Label(error.errorDescription ?? "", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var canAdd: Bool {
        switch kind {
        case .server:
            normalizedURL != nil
        case .pipe:
            if let parsed = parsedPairing { parsed.code != nil || !token.isEmpty } else { false }
        }
    }

    /// Adds, and only dismisses if that worked. A sheet that closes on a
    /// failure takes the reason with it.
    private func add() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        failure = nil
        do {
            switch kind {
            case .server:
                guard let url = normalizedURL else { return }
                let config = ProviderConfig(
                    name: trimmedName.isEmpty ? (url.host() ?? "Server") : trimmedName,
                    kind: .openAICompatible(baseURL: url))
                try model.addProvider(config, credentials: [.apiKey: apiKey])
            case .pipe:
                guard let parsed = parsedPairing else { return }
                let config = ProviderConfig(
                    name: trimmedName.isEmpty ? "Pipe" : trimmedName,
                    kind: .pipe(ticketDigest: Ticket.digest(parsed.ticket)))
                if let code = parsed.code {
                    pair(config, ticket: parsed.ticket, code: code)
                    return
                }
                try model.addProvider(config, credentials: [.ticket: parsed.ticket, .token: token])
                Task { await model.connectPipe(for: config) }
            }
        } catch {
            failure = error.localizedDescription
            return
        }
        dismiss()
    }

    /// Redeeming is a round trip through the pipe, so the sheet stays up
    /// with the Add button replaced by a spinner and dismisses only when the
    /// key is in the Keychain. A sheet that dismissed first would take the
    /// reason a code was refused away with it, and a refused code is the
    /// failure this form most has to explain: it is spent either way, so the
    /// next attempt starts on the other machine.
    private func pair(_ config: ProviderConfig, ticket: String, code: String) {
        redeeming = true
        Task {
            do {
                try await model.addPairedProvider(config, ticket: ticket, code: code)
                dismiss()
            } catch {
                failure = error.localizedDescription
                redeeming = false
            }
        }
    }
}

#Preview {
    AddProviderView()
        .environment(AppModel.preview)
}
