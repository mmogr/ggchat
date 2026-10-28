import GGChatCore
import SwiftUI

/// The downloads under way, on the browser's first page as well as on the
/// page each was chosen from, so going back from a repository does not lose
/// sight of one. Nothing shows while none is under way.
struct DownloadingSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let under = model.onDevice.downloads.filter { $0.value.state.isUnderWay }
            .sorted { ($0.key.repo, $0.key.quantization) < ($1.key.repo, $1.key.quantization) }
        if !under.isEmpty {
            Section("Downloading") {
                ForEach(under, id: \.key) { choice, progress in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(choice.repo) · \(choice.quantization)")
                        DownloadBar(progress: progress, name: choice.quantization) {
                            model.cancelDownload(choice)
                        }
                    }
                }
            }
        }
    }
}

/// The models on this iPhone, each with its size, as the library lists
/// them. A swipe deletes one, its files and its row; a failure to list or
/// delete is said here, under the section.
struct InstalledSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Installed") {
            if let installed = model.onDevice.installed {
                if installed.isEmpty {
                    Text("No model is on this iPhone yet.").foregroundStyle(.secondary)
                }
                ForEach(installed) { item in
                    LabeledContent(item.name, value: Sizes.download(item.bytes))
                }
                .onDelete { offsets in
                    let doomed = offsets.map { installed[$0] }
                    Task {
                        for item in doomed { await model.removeInstalled(item) }
                    }
                }
            } else if model.onDevice.installedFailure == nil {
                ProgressView()
            }
            if let failure = model.onDevice.installedFailure {
                Text(failure).foregroundStyle(.secondary)
            }
        }
    }
}
