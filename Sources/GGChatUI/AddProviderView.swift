import GGChatCore
import SwiftUI

/// URL and key, or ticket and token. The ticket's shape is checked as it is
/// typed and the reason it fails is shown as a sentence.
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
    @State private var ticket = ""
    @State private var token = ""
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
                }

                switch kind {
                case .server:
                    Section {
                        TextField("http://127.0.0.1:8080/v1", text: $address)
                            .autocorrectionDisabled()
                            #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                            #endif
                        SecureField("API key (optional on loopback)", text: $apiKey)
                    } header: {
                        Text("Address")
                    } footer: {
                        Text(addressFooter)
                    }
                case .pipe:
                    Section {
                        TextField("pipe…", text: $ticket, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            #if os(iOS)
                                .textInputAutocapitalization(.never)
                            #endif
                        SecureField("Token", text: $token)
                        #if os(iOS)
                            if ScanTicketView.isSupported {
                                Button("Scan ticket", systemImage: "qrcode.viewfinder") { scanning = true }
                            }
                        #endif
                    } header: {
                        Text("Ticket and token")
                    } footer: {
                        ticketFooter
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add provider")
            #if os(iOS)
                .sheet(isPresented: $scanning) {
                    ScanTicketView { scanned in
                        ticket = scanned
                        scanning = false
                    }
                }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(!canAdd)
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

    private var ticketShape: Result<Void, TicketShapeError>? {
        ticket.isEmpty ? nil : Ticket.validateShape(ticket.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @ViewBuilder
    private var ticketFooter: some View {
        switch ticketShape {
        case nil:
            Text("Paste the ticket from `modelpipe serve`. The token is separate.")
        case .success:
            Label("Looks like a ticket.", systemImage: "checkmark.circle")
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
            if case .success? = ticketShape { !token.isEmpty } else { false }
        }
    }

    private func add() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .server:
            guard let url = normalizedURL else { return }
            let config = ProviderConfig(
                name: trimmedName.isEmpty ? (url.host() ?? "Server") : trimmedName,
                kind: .openAICompatible(baseURL: url))
            model.addProvider(config, credentials: [.apiKey: apiKey])
        case .pipe:
            let cleaned = Ticket.normalized(ticket.trimmingCharacters(in: .whitespacesAndNewlines))
            let config = ProviderConfig(
                name: trimmedName.isEmpty ? "Pipe" : trimmedName,
                kind: .pipe(ticketDigest: Ticket.digest(cleaned)))
            model.addProvider(config, credentials: [.ticket: cleaned, .token: token])
            Task { await model.connectPipe(for: config) }
        }
        dismiss()
    }
}

#Preview {
    AddProviderView()
        .environment(AppModel.preview)
}
