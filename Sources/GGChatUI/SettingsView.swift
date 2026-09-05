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
                    Text("Counted on this device only. ADR 0001 and ADR 0002 read these.")
                }
                #if DEBUG
                    if !connectedPipes.isEmpty {
                        Section("Debug") {
                            ForEach(connectedPipes) { provider in
                                Button("Force \(provider.name) closed", systemImage: "bolt.slash") {
                                    (model.pipeSession(for: provider.id) as? MockPipeSession)?.forceClosed()
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

#Preview {
    SettingsView()
        .environment(AppModel.preview)
}
