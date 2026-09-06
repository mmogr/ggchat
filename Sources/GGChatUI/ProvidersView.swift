import GGChatCore
import SwiftUI

/// List, add, edit, remove. A provider's model is picked in the composer;
/// a row here is the way to its name and its credentials.
struct ProvidersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.providers) { provider in
                    // The row is the edit affordance. Before this it was not
                    // a control of any kind, so a pipe whose ticket had gone
                    // stale — which is every pipe, every session — could only
                    // be deleted and built again.
                    NavigationLink {
                        EditProviderView(provider: provider)
                    } label: {
                        ProviderRow(provider: provider)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.removeProvider(model.providers[index].id)
                    }
                }
            }
            .overlay {
                if model.providers.isEmpty {
                    ContentUnavailableView(
                        "No providers", systemImage: "server.rack",
                        description: Text("Add a server by address, or a modelpipe ticket."))
                }
            }
            .navigationTitle("Providers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add provider", systemImage: "plus") { adding = true }
                }
                #if DEBUG
                    ToolbarItem(placement: .automatic) {
                        Button("Add mock provider", systemImage: "wand.and.sparkles") {
                            try? model.addProvider(
                                ProviderConfig(
                                    name: "Mock", kind: .openAICompatible(baseURL: AppModel.mockBaseURL),
                                    defaultModel: "mock-27b"),
                                credentials: [:])
                        }
                    }
                #endif
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $adding) {
                AddProviderView()
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 360)
        #endif
    }
}

struct ProviderRow: View {
    let provider: ProviderConfig

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: provider.isPipe ? "point.3.connected.trianglepath.dotted" : "server.rack")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch provider.kind {
        case .openAICompatible(let baseURL):
            Redaction.describe(baseURL)
        case .pipe:
            "modelpipe · " + (provider.defaultModel ?? "no model chosen")
        }
    }
}

#Preview {
    ProvidersView()
        .environment(AppModel.preview)
}
