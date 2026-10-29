import SwiftUI

/// Adds a provider, of the kind picked at the top: a server by its address
/// (`AddServerForm`), a pipe by the pairing string a machine printed
/// (`AddPipeForm`), or, where this build runs models on this device, This
/// iPhone, whose page is the model browser's (`ModelBrowserList`): choosing
/// a model there adds This iPhone the first time, and there is nothing to
/// name, since a device has one engine and so one such provider.
struct AddProviderView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case server = "Server"
        case pipe = "Pipe"
        case thisIPhone = "This iPhone"
        var id: String { rawValue }

        /// The kinds the picker offers: This iPhone only where this build
        /// runs models on this device, so the Mac, and a build with no
        /// engine, offer the other two alone.
        static func offered(runsModelsHere: Bool) -> [Kind] {
            runsModelsHere ? allCases : [.server, .pipe]
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.server
    /// What the Server and Pipe forms hold: kept here, so a change of kind
    /// loses nothing typed, and a pairing's redeem writes its outcome where
    /// the sheet still shows it.
    @State private var draft = ProviderDraft()
    /// This iPhone's one opening of the browser while the sheet is up, made
    /// the first time This iPhone is picked, which reads this device.
    @State private var browser: ModelBrowser?

    var body: some View {
        NavigationStack {
            Group {
                switch kind {
                case .server:
                    AddServerForm(draft: $draft) { picker }
                case .pipe:
                    AddPipeForm(draft: $draft) { picker }
                case .thisIPhone:
                    if let browser {
                        ModelBrowserList(browser: browser) { picker }
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { dismiss() }
                                }
                            }
                    }
                }
            }
            .navigationTitle("Add provider")
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 380)
        #endif
    }

    private var picker: some View {
        Picker("Kind", selection: Binding(get: { kind }, set: { pick($0) })) {
            ForEach(Kind.offered(runsModelsHere: model.runsModelsHere)) { kind in
                Text(kind.rawValue).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        // A code on its way out keeps the Pipe form up until it is answered.
        .disabled(draft.redeeming)
        .accessibilityIdentifier("provider-kind")
    }

    /// Picks `chosen`, opening the browser for This iPhone the first time,
    /// in the same change, so its page never draws without one. A failure
    /// said for one kind is not left under another.
    private func pick(_ chosen: Kind) {
        if chosen == .thisIPhone, browser == nil { browser = model.makeModelBrowser() }
        if chosen != kind { draft.failure = nil }
        kind = chosen
    }
}

/// What Add provider's Server and Pipe forms hold, as typed: the name this
/// app will call the provider, a server's address and key, a pipe's
/// pairing string, token and the name it sends for this device; why the
/// last add failed; and whether a code is being redeemed.
struct ProviderDraft {
    var name = ""
    var address = ""
    var apiKey = ""
    var pairing = ""
    var token = ""
    var deviceName = ""
    var failure: String?
    var redeeming = false
}

/// What this app calls the provider, in the Server and Pipe forms.
struct AddProviderNameSection: View {
    @Binding var name: String

    var body: some View {
        Section("Name") {
            TextField("gglib on the Mac", text: $name)
                .accessibilityIdentifier("provider-name")
        }
    }
}

extension View {
    /// What the Server and Pipe forms share: the grouped style, the reason
    /// an add failed under the form, Cancel, and Add, a spinner in its place
    /// while `busy`.
    func addProviderChrome(
        failure: String?, busy: Bool = false, canAdd: Bool, add: @escaping () -> Void
    ) -> some View {
        modifier(AddProviderChrome(failure: failure, busy: busy, canAdd: canAdd, add: add))
    }
}

private struct AddProviderChrome: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let failure: String?
    let busy: Bool
    let canAdd: Bool
    let add: () -> Void

    func body(content: Content) -> some View {
        content
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Add", action: add)
                            .disabled(!canAdd)
                    }
                }
            }
    }
}

#Preview {
    AddProviderView()
        .environment(AppModel.preview)
}
