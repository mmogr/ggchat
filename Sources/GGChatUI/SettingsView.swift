import SwiftUI

/// Minimal. Diagnostics readings arrive with the pipe flow.
struct SettingsView: View {
    #if os(iOS)
        @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    Link("Source", destination: URL(string: "https://github.com/mmogr/ggchat")!)
                }
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
            .frame(minWidth: 400, minHeight: 240)
        #endif
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
