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
            PairingSection(
                mode: .adding, idPrefix: "provider", pairing: $draft.pairing, token: $draft.token,
                deviceName: $draft.deviceName, shape: pairingShape, scan: scan)
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

    /// ``PairingReader/readField(_:)`` of the field, which `PairingSection`
    /// shows and Add goes by.
    private var pairingShape: Result<ReadPairing, PairingReadError>? {
        model.pairingReader.readField(draft.pairing)
    }

    private var readPairing: ReadPairing? {
        try? pairingShape?.get()
    }

    /// Scan ticket's action, on a device that can scan, and nil elsewhere.
    private var scan: (() -> Void)? {
        #if os(iOS)
            guard ScanTicketView.isSupported else { return nil }
            return { scanning = true }
        #else
            return nil
        #endif
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
