import GGChatCore
import SwiftUI

/// gglib's "what is the server doing" pane: slots, context in use, recent
/// requests and the flags gglib raised on them. Fed by the SSE stream while
/// open. Shown only for providers that answer the endpoint.
struct ProxyStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let provider: ProviderConfig
    @State private var status: ProxyStatus?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
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
            }
            .navigationTitle("Server status")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await follow() }
        #if os(macOS)
            .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func follow() async {
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
                    Text(Date(timeIntervalSince1970: TimeInterval(seconds)), style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
