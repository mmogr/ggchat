import GGChatCore
import SwiftUI

/// A row of the browser's "On this iPhone": a model installed, or one on its
/// way. The downloads under way show here as well as on the page each was
/// chosen from, so going back from a repository does not lose sight of one.
enum OnThisIPhoneRow: Identifiable, Equatable {
    case installed(InstalledModel)
    case downloading(QuantChoice, DownloadProgress)

    var id: String {
        switch self {
        case .installed(let model): "installed/\(model.id)"
        case .downloading(let choice, _): "downloading/\(choice.repo)/\(choice.quantization)"
        }
    }

    /// The models installed, as the library lists them, then the downloads
    /// under way, paused ones included, by repository and quantization. A
    /// download done or failed is not on its way: a done one is among the
    /// installed once they are read again, and a failed one says so on its
    /// repository's page.
    static func rows(installed: [InstalledModel]?, downloads: [QuantChoice: DownloadProgress]) -> [Self] {
        let under = downloads.filter { $0.value.state.isUnderWay }
            .sorted { ($0.key.repo, $0.key.quantization) < ($1.key.repo, $1.key.quantization) }
        return (installed ?? []).map(Self.installed) + under.map { Self.downloading($0.key, $0.value) }
    }
}

/// The models on this iPhone and those on their way, one line each where it
/// fits: an installed one with its size and its chip, and, while there is no
/// This iPhone, Use, which adds it with that model; a download with its bar,
/// how far it has come and a cross that calls it off. An installed one is
/// removed, files and row, three ways: a swipe, Remove… in the menu a long
/// press opens, and the section's Edit; each asks first, naming the model
/// and the room it frees. A failure to list, delete or add is said under the
/// section.
struct OnThisIPhoneSection: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
        @Environment(\.editMode) private var editMode
    #endif
    let explain: (FitExplanation) -> Void
    /// The model whose removal is being asked about, while it is.
    @State private var removing: InstalledModel?

    var body: some View {
        let rows = OnThisIPhoneRow.rows(installed: model.onDevice.installed, downloads: model.onDevice.downloads)
        Section {
            ForEach(rows) { row in
                switch row {
                case .installed(let item):
                    installedRow(item)
                case .downloading(let choice, let progress):
                    DownloadLine(choice: choice, progress: progress) { model.cancelDownload(choice) }
                        .deleteDisabled(true)
                }
            }
            // A swipe, or Edit's delete control, asks about one row at a
            // time, and the row stays until the removal is confirmed.
            .onDelete { offsets in
                for index in offsets {
                    if case .installed(let item) = rows[index] { removing = item }
                }
            }
            if model.onDevice.installed == nil, model.onDevice.installedFailure == nil {
                ProgressView()
            } else if rows.isEmpty, model.onDevice.installedFailure == nil {
                Text("No model is on this iPhone yet.").foregroundStyle(.secondary)
            }
            if let failure = model.onDevice.installedFailure {
                Text(failure).foregroundStyle(.secondary)
            }
        } header: {
            header
        }
    }

    /// The section's title, and Edit while a model is installed: the way to
    /// removing one for whoever does not know the swipe. Editing is the
    /// list's, but only this section's rows can be deleted. It ends once the
    /// last model has gone, with nothing left to remove.
    private var header: some View {
        HStack {
            Text("On this iPhone")
            #if os(iOS)
                if model.onDevice.installed?.isEmpty == false {
                    Spacer()
                    EditButton()
                }
            #endif
        }
        #if os(iOS)
            .onChange(of: model.onDevice.installed?.isEmpty ?? true) { _, empty in
                if empty { editMode?.wrappedValue = .inactive }
            }
        #endif
    }

    private func installedRow(_ item: InstalledModel) -> some View {
        CompactRow(title: item.name, detail: Sizes.download(item.bytes)) {
            HStack(spacing: 12) {
                FitChipButton(explanation: FitExplanation(installed: item), open: explain)
                if model.thisIPhoneID == nil {
                    Button("Use") { model.useInstalled(item) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Use \(item.name)")
                }
            }
        }
        .contextMenu {
            Button("Remove\u{2026}", systemImage: "trash", role: .destructive) { removing = item }
        }
        // On the row, so on an iPad the question points at the model it is
        // about.
        .confirmationDialog(
            Self.removalQuestion(for: item),
            isPresented: Binding(get: { removing?.id == item.id }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                removing = nil
                Task { await model.removeInstalled(item) }
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text(Self.removalDetail(for: item))
        }
    }

    /// What the question before a removal asks: "Remove mock-phone-1.7b?"
    static func removalQuestion(for item: InstalledModel) -> String {
        "Remove \(item.name)?"
    }

    /// What it says under the question: the room the removal frees.
    static func removalDetail(for item: InstalledModel) -> String {
        "This frees \(Sizes.download(item.bytes)) on this iPhone."
    }
}
