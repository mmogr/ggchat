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
/// fits: an installed one with its size and its chip, which a swipe deletes,
/// files and row, and, while there is no This iPhone, Use, which adds it
/// with that model; a download with its bar, how far it has come and a
/// cross that calls it off. A failure to list, delete or add is said under
/// the section.
struct OnThisIPhoneSection: View {
    @Environment(AppModel.self) private var model
    let explain: (FitExplanation) -> Void

    var body: some View {
        let rows = OnThisIPhoneRow.rows(installed: model.onDevice.installed, downloads: model.onDevice.downloads)
        Section("On this iPhone") {
            ForEach(rows) { row in
                switch row {
                case .installed(let item):
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
                case .downloading(let choice, let progress):
                    DownloadLine(choice: choice, progress: progress) { model.cancelDownload(choice) }
                        .deleteDisabled(true)
                }
            }
            .onDelete { offsets in
                let doomed = offsets.compactMap { index -> InstalledModel? in
                    if case .installed(let item) = rows[index] { item } else { nil }
                }
                Task {
                    for item in doomed { await model.removeInstalled(item) }
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
        }
    }
}
