import GGChatCore
import SwiftUI

/// gglib's "what is the server doing" pane: slots, context in use, recent
/// requests and the flags gglib raised on them, fed by the SSE stream while
/// open, and the MCP servers a paired Mac offers. Shown only for providers
/// that answer the endpoint.
struct ProxyStatusView: View {
    @Environment(\.dismiss) private var dismiss
    let provider: ProviderConfig
    @State private var status: ProxyStatus?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                ProxyStatusSections(provider: provider, status: status, failure: failure)
            }
            .navigationTitle("Server status")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .followsProxyStatus(of: provider, status: $status, failure: $failure)
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 420)
        #endif
    }
}

/// The pane's rows, for its own list or the panel beside the chat on an open
/// iPhone Duo on its side: what the last snapshot said, or why there is none.
/// Whoever lays them out follows the stream with `followsProxyStatus`, on
/// the list itself, which is one view where these rows are many.
struct ProxyStatusSections: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderConfig
    let status: ProxyStatus?
    let failure: String?

    var body: some View {
        if let failure {
            Text(failure)
                .foregroundStyle(.red)
        }
        if let status {
            Section("Server") {
                LabeledContent("Active connections", value: "\(status.activeConnectionCount)")
                if let available = status.slotsAvailable {
                    LabeledContent("Slots", value: available ? "Available" : "Busy")
                }
            }
            Section("Slots") {
                ForEach(Array(status.slots.enumerated()), id: \.offset) { _, slot in
                    SlotRow(slot: slot)
                }
            }
            Section("Recent requests") {
                if status.recentRequests.isEmpty {
                    Text("None yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(status.recentRequests.reversed().enumerated()), id: \.offset) { _, request in
                    RecentRequestRow(request: request)
                }
            }
        } else if failure == nil {
            ProgressView("Waiting for the first snapshot")
        }
        ToolsOfferedSection(servers: model.toolsOffered(by: provider))
    }
}

extension View {
    /// Reads `provider`'s status stream into `status` while the view is on
    /// screen, or says in `failure` why it cannot, starting again for
    /// another provider. Nil reads nothing.
    func followsProxyStatus(
        of provider: ProviderConfig?, status: Binding<ProxyStatus?>, failure: Binding<String?>
    ) -> some View {
        modifier(ProxyStatusFeed(provider: provider, status: status, failure: failure))
    }
}

private struct ProxyStatusFeed: ViewModifier {
    @Environment(AppModel.self) private var model
    let provider: ProviderConfig?
    @Binding var status: ProxyStatus?
    @Binding var failure: String?

    func body(content: Content) -> some View {
        content.task(id: provider?.id) {
            status = nil
            failure = nil
            guard let provider else { return }
            await follow(provider)
        }
    }

    private func follow(_ provider: ProviderConfig) async {
        guard let stream = model.proxyStatusStream(for: provider) else {
            failure = "This provider does not report status."
            return
        }
        do {
            for try await snapshot in stream {
                status = snapshot
            }
        } catch is CancellationError {
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// The MCP servers a paired Mac offers this phone's runs, each by the name
/// it gives it and kept apart by its id, and how one is opened: on the Mac,
/// so there is nothing to tap (ADR 0013). No section where none are offered.
struct ToolsOfferedSection: View {
    let servers: [OfferedServer]

    var body: some View {
        if !servers.isEmpty {
            Section {
                ForEach(servers) { server in
                    Text(server.name)
                }
            } header: {
                Text("Tools offered")
            } footer: {
                Text("Opened on the Mac with `gglib mcp allow-remote <server>`.")
            }
        }
    }
}

struct SlotRow: View {
    let slot: ProxyStatus.Slot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Slot \(slot.id ?? 0)")
                Spacer()
                Text(slot.isProcessing == true ? "Generating" : "Idle")
                    .foregroundStyle(slot.isProcessing == true ? .primary : .secondary)
            }
            if let usage = slot.contextUsage, let promptTokens = slot.promptTokens, let contextSize = slot.contextSize {
                ProgressView(value: usage) {
                    Text("\(promptTokens.formatted()) of \(contextSize.formatted()) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let cached = slot.promptTokensCached, cached > 0 {
                    Text("\(cached.formatted()) from cache")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RecentRequestRow: View {
    let request: ProxyStatus.RecentRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(request.modelName ?? "unknown model")
                Spacer()
                if let seconds = request.recordedAtSeconds {
                    // One unit, not "47 min., 2 sec.", which is the default.
                    Text(
                        Date(timeIntervalSince1970: TimeInterval(seconds)),
                        format: .relative(presentation: .numeric, unitsStyle: .narrow)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            if !request.flags.isEmpty {
                Text(request.flags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
