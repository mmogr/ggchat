import GGChatCore
import SwiftUI

/// Whether a provider form is adding a provider or editing one that is
/// already there. The fields are the same either way; what changes is what
/// a blank field means, and so what the placeholders and footers say.
enum ProviderFormMode {
    /// Add provider's Server and Pipe forms: a blank field is one nobody has
    /// filled in yet.
    case adding
    /// `EditProviderView`: a blank credential field keeps what is stored.
    case editing
}

extension PairingReader {
    /// What modelpipe makes of a pairing field, or nil while nothing is typed
    /// in it. The same read `mpPair` will make of the field when Add or Save
    /// is pressed, so nothing a form accepts is refused a moment later by the
    /// pairing.
    ///
    /// Nil is not a mistake. Adding, it is a field nobody has filled in yet,
    /// which gets guidance rather than a refusal; editing, it means "keep
    /// what is stored" — a stray space is not a new ticket.
    ///
    /// ``PairingField/isBlank(_:)`` decides that, over modelpipe's own
    /// whitespace and no other set, so no form holds an opinion about which
    /// spaces count. And it decides only that: what goes to the reader is the
    /// text exactly as typed, with the trimming left to modelpipe.
    func readField(_ pairing: String) -> Result<ReadPairing, PairingReadError>? {
        PairingField.isBlank(pairing) ? nil : read(pairing)
    }
}

/// A pipe's pairing string and token, and, alongside a code, the name this
/// device sends with the redeem: the sections Add provider's Pipe form and
/// `EditProviderView` both show. modelpipe's read of the string is shown
/// under it as a sentence.
///
/// The form holds the fields and makes the read, because it needs the same
/// read to decide whether Add or Save can go; this shows that read rather
/// than making a second one.
struct PairingSection: View {
    let mode: ProviderFormMode
    /// What the fields' accessibility identifiers start with: `provider` when
    /// adding, `edit` when editing.
    let idPrefix: String
    @Binding var pairing: String
    @Binding var token: String
    /// What the other machine will list this device as, if it keeps a list.
    /// Not the provider's name, which is what this app calls that machine.
    @Binding var deviceName: String
    /// ``PairingReader/readField(_:)`` of `pairing`.
    let shape: Result<ReadPairing, PairingReadError>?
    /// Scan ticket's action, where the form offers one: adding, on a device
    /// that can scan. Nil draws no button.
    var scan: (() -> Void)?

    var body: some View {
        Section {
            TextField("pipe…-483920", text: $pairing, axis: .vertical)
                .accessibilityIdentifier("\(idPrefix)-ticket")
                .lineLimit(3...6)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
            // A code is redeemed for the token, so asking for one as well
            // would be asking for the thing the code exists to fetch.
            if readPairing?.hasCode != true {
                SecureField(tokenPlaceholder, text: $token)
                    .accessibilityIdentifier("\(idPrefix)-token")
            }
            if let scan {
                Button("Scan ticket", systemImage: "qrcode.viewfinder", action: scan)
            }
        } header: {
            Text("Pairing string")
        } footer: {
            pairingFooter
        }
        // Asked for only alongside a code: the name goes out with the
        // redeem, and a bare ticket redeems nothing.
        if readPairing?.hasCode == true {
            Section {
                TextField("Optional", text: $deviceName)
                    .accessibilityIdentifier("\(idPrefix)-device")
                    .autocorrectionDisabled()
            } header: {
                Text("This device")
            } footer: {
                Text(deviceFooter)
            }
        }
    }

    private var readPairing: ReadPairing? {
        try? shape?.get()
    }

    private var tokenPlaceholder: LocalizedStringKey {
        switch mode {
        case .adding: "Token"
        case .editing: "New token"
        }
    }

    private var deviceFooter: String {
        "What the other machine calls this one in its list of devices, if it keeps one. "
            + "The name above is what this app calls that machine. Leave blank to send none."
    }

    /// What the footer says while nothing is typed: guidance, since an empty
    /// field is not a mistake. A key rather than a `String`, so the command
    /// in backticks is drawn as code.
    private var blankFooter: LocalizedStringKey {
        switch mode {
        case .adding:
            "Paste or scan what `gglib remote enable --invite` shows. A bare ticket works once the key is stored."
        case .editing:
            "Blank keeps the ticket and token already stored. Paste what `gglib remote invite` shows."
        }
    }

    @ViewBuilder
    private var pairingFooter: some View {
        switch shape {
        case nil:
            Text(blankFooter)
        case .success(let readPairing) where readPairing.hasCode:
            Label(
                "A ticket and a code. The code is redeemed once, for a key of this device's own.",
                systemImage: "checkmark.circle")
        case .success:
            switch mode {
            case .adding:
                Label("Looks like a ticket. The token is separate.", systemImage: "checkmark.circle")
            case .editing:
                Label(
                    "Looks like a ticket. Leave the token blank to keep the one stored.",
                    systemImage: "checkmark.circle")
            }
        case .failure(let error):
            Label(error.errorDescription ?? "", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}
