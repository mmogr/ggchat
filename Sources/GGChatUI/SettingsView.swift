import GGChatCore
import SwiftUI

/// About, and the readings the ADRs name, each with its denominator.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
        @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent("Distinct tickets connected", value: "\(model.diagnostics.ticketDigests.count)")
                    Link("Source", destination: URL(string: "https://github.com/mmogr/ggchat")!)
                }
                ConnectionsSection()
                Section {
                    let readings = model.diagnostics
                    LabeledContent(
                        "Transport errors after resume",
                        value: "\(readings.transportErrorsAfterResume) of \(readings.foregroundResumes) resumes")
                    LabeledContent(
                        "Pipe closed mid-reply",
                        value: "\(readings.closedWhileStreaming) of \(readings.closedTransitions) closes")
                    LabeledContent("Continue pressed", value: "\(readings.continuePresses) times")
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text(
                        "Counted on this device only. Both ADRs struck the criteria "
                            + "these were meant to answer; the numbers are still real."
                    )
                }
                #if DEBUG
                    // Only the pipes this button can actually close. It works
                    // by downcasting to the mock, so against any other session
                    // it is a control that looks live, is pressable, and does
                    // nothing — and it is the only way to exercise the
                    // reconnect UI by hand, so a silent no-op there costs the
                    // one affordance that would have shown it was broken.
                    let forceable = connectedPipes.filter {
                        model.pipeSession(for: $0.id) is MockPipeSession
                    }
                    if !forceable.isEmpty {
                        Section("Debug") {
                            ForEach(forceable) { provider in
                                Button("Force \(provider.name) closed", systemImage: "bolt.slash") {
                                    (model.pipeSession(for: provider.id) as? MockPipeSession)?.forceClosed()
                                }
                            }
                            // The other close, and the one with no button
                            // until now: a machine that stops answering
                            // without saying so. "Force closed" reports a
                            // shutdown, honestly, because a person pressed it
                            // — so it could never exercise the sentence that
                            // only an unexpected close produces.
                            //
                            // The label deliberately does not begin with
                            // "Force ": `RemainingScreensUITests` matches
                            // `label BEGINSWITH 'Force '` with `.firstMatch`,
                            // and a second button under that prefix would make
                            // which one it taps a matter of layout order.
                            ForEach(forceable) { provider in
                                Button("Drop \(provider.name)", systemImage: "antenna.radiowaves.left.and.right.slash")
                                {
                                    (model.pipeSession(for: provider.id) as? MockPipeSession)?.dropped()
                                }
                            }
                        }
                    }
                #endif
                Section {
                    Text(
                        "Nothing you say leaves your devices. Credentials live in the Keychain; "
                            + "conversations stay on this device."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            #endif
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 360)
        #endif
    }

    private var connectedPipes: [ProviderConfig] {
        model.providers.filter { model.pipeSession(for: $0.id) != nil }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

/// What each live pipe says about itself: how it is carrying traffic, the
/// port it bound, and what its endpoint has spent on relays.
///
/// Live pipes only. A pipe that has closed is forgotten by `AppModel` so that
/// the next dial can happen at all, and a row of numbers about a connection
/// that no longer exists would be a reading with nothing behind it. Why a
/// pipe closed is said in a sentence when it happens, which is where a reason
/// belongs; this section is for the numbers.
///
/// No clock. These change interestingly only when the path does, and the path
/// is `model.pipeStatus(for:)` — already observed, so the numbers are
/// refreshed by the thing the section is already watching.
private struct ConnectionsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let live = model.providers.filter { model.pipeSession(for: $0.id) != nil }
        if !live.isEmpty {
            Section {
                ForEach(live) { provider in
                    LabeledContent(provider.name, value: path(for: provider))
                    if let readings = model.pipeSession(for: provider.id)?.readings {
                        LabeledContent("Port", value: "\(readings.port)")
                        LabeledContent(
                            "Relay connections",
                            value: "\(readings.relayConnectionsFailed) failed of \(readings.relayConnections)")
                        LabeledContent("Rate limited", value: "\(readings.relayConnectionsRatelimited) times")
                    }
                }
            } header: {
                Text("Connections")
            } footer: {
                Text(
                    "Read from the pipe itself. A direct connection with relay "
                        + "connections behind it hole-punched after starting through "
                        + "a relay, which is the ordinary way one forms."
                )
            }
        }
    }

    /// How this pipe is carrying traffic, said as a reading rather than as an
    /// affordance. Deliberately not "Reconnect": that word is the status
    /// pill's, it is a thing to press, and nothing here is pressable.
    private func path(for provider: ProviderConfig) -> String {
        switch model.pipeStatus(for: provider.id) {
        case .direct: "Direct"
        case .relayed: "Relayed"
        case .idle: "Connecting"
        case .closed, nil: "Not connected"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel.preview)
}
