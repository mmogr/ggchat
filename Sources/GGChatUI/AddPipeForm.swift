import GGChatCore
import SwiftUI

/// Add provider's Pipe: a name and the pairing string a machine printed.
/// modelpipe reads the pairing string as it is typed and the reason it will
/// not read is shown as a sentence.
///
/// A pairing string is `ticket-code` the first time and a bare ticket after
/// that, so the token field is asked for only when there is no code to
/// redeem for one — a code is a token this device has not been given yet.
///
/// The token is a `SecureField`, which is what it is. iOS may offer to save
/// it to the password manager afterwards; there is no content type that
/// means "secret, never offer to save", and the alternatives all show the
/// secret in the clear.
struct AddPipeForm<Top: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The fields, kept by the sheet, so a change of kind loses nothing,
    /// and a redeem's outcome is written where the sheet still shows it.
    /// What the other machine will list this device as is
    /// `draft.deviceName`, not `draft.name`, which is what this app calls
    /// that machine.
    @Binding var draft: ProviderDraft
    let top: Top
    #if os(iOS)
        @State private var scanning = false
    #endif

    init(draft: Binding<ProviderDraft>, @ViewBuilder top: () -> Top) {
        _draft = draft
        self.top = top()
    }

    var body: some View {
        Form {
            top
            AddProviderNameSection(name: $draft.name)
            Section {
                TextField("pipe…-483920", text: $draft.pairing, axis: .vertical)
                    .accessibilityIdentifier("provider-ticket")
                    .lineLimit(3...6)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                // A code is redeemed for the token, so asking for one as
                // well would be asking for the thing the code exists to
                // fetch.
                if readPairing?.hasCode != true {
                    SecureField("Token", text: $draft.token)
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
            // Asked for only alongside a code: the name goes out with the
            // redeem, and a bare ticket redeems nothing.
            if readPairing?.hasCode == true {
                Section {
                    TextField("Optional", text: $draft.deviceName)
                        .accessibilityIdentifier("provider-device")
                        .autocorrectionDisabled()
                } header: {
                    Text("This device")
                } footer: {
                    Text(deviceFooter)
                }
            }
        }
        .addProviderChrome(failure: draft.failure, busy: draft.redeeming, canAdd: canAdd, add: add)
        #if os(iOS)
            .sheet(isPresented: $scanning) {
                ScanTicketView(reader: model.pairingReader) { scannedPairing in
                    draft.pairing = scannedPairing
                    scanning = false
                }
            }
        #endif
    }

    /// The field's text once there is something in it, or nil while there is
    /// not — a field nobody has filled in yet, which is not a mistake and
    /// gets the guidance below rather than a refusal.
    ///
    /// ``PairingField/isBlank(_:)`` decides that, over modelpipe's own
    /// whitespace and no other set, so this view holds no opinion about which
    /// spaces count. And it decides only that: what goes to the reader is the
    /// text exactly as typed, with the trimming left to modelpipe.
    private var typedPairing: String? {
        PairingField.isBlank(draft.pairing) ? nil : draft.pairing
    }

    /// What modelpipe makes of the field, or nil while nothing is typed. The
    /// same read `mpPair` will make of it when Add is pressed, so nothing
    /// the form accepts is refused a moment later by the pairing.
    private var pairingShape: Result<ReadPairing, PairingReadError>? {
        typedPairing.map(model.pairingReader.read)
    }

    private var readPairing: ReadPairing? {
        guard case .success(let readPairing)? = pairingShape else { return nil }
        return readPairing
    }

    @ViewBuilder
    private var pairingFooter: some View {
        switch pairingShape {
        case nil:
            Text("Paste or scan what `gglib remote enable --invite` shows. A bare ticket works once the key is stored.")
        case .success(let readPairing) where readPairing.hasCode:
            Label(
                "A ticket and a code. The code is redeemed once, for a key of this device's own.",
                systemImage: "checkmark.circle")
        case .success:
            Label("Looks like a ticket. The token is separate.", systemImage: "checkmark.circle")
        case .failure(let error):
            Label(error.errorDescription ?? "", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    /// The same sentence as `EditProviderView`'s, because it is the same field.
    private var deviceFooter: String {
        "What the other machine calls this one in its list of devices, if it keeps one. "
            + "The name above is what this app calls that machine. Leave blank to send none."
    }

    private var canAdd: Bool {
        if let readPairing { readPairing.hasCode || !draft.token.isEmpty } else { false }
    }

    /// Adds, and only dismisses if that worked. A sheet that closes on a
    /// failure takes the reason with it.
    private func add() {
        guard let readPairing else { return }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespaces)
        draft.failure = nil
        let config = ProviderConfig(
            name: trimmedName.isEmpty ? "Pipe" : trimmedName,
            kind: .pipe(ticketDigest: Ticket.digest(readPairing.ticket)))
        if readPairing.hasCode {
            // The field's text as typed, not a string rebuilt from the
            // ticket and a code this never saw: `mpPair` reads it the same
            // way the reader just did, and rebuilding it here would be a
            // second place that knows the format.
            pair(config, pairing: draft.pairing, ticket: readPairing.ticket)
            return
        }
        do {
            try model.addProvider(config, credentials: [.ticket: readPairing.ticket, .token: draft.token])
        } catch {
            draft.failure = error.localizedDescription
            return
        }
        Task { await model.connectPipe(for: config) }
        dismiss()
    }

    /// Redeeming is a round trip through the pipe, so the sheet stays up
    /// with the Add button replaced by a spinner and dismisses only when the
    /// key is in the Keychain. A sheet that dismissed first would take the
    /// reason a code was refused away with it, and a refused code is the
    /// failure this form most has to explain: it may be dead for good, and
    /// then the next attempt starts on the other machine.
    private func pair(_ config: ProviderConfig, pairing: String, ticket: String) {
        draft.redeeming = true
        Task {
            do {
                try await model.addPairedProvider(
                    config, pairing: pairing, ticket: ticket, deviceName: draft.deviceName)
                dismiss()
            } catch {
                draft.failure = error.localizedDescription
                draft.redeeming = false
            }
        }
    }
}
