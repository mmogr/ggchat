import GGChatCore
import SwiftUI

/// A download under way, as its row shows it: a bar, how much of how much has
/// come, and Cancel. While the app is away the library pauses it, and the
/// line says it goes on when ggchat is open again. Every figure is the
/// library's; this only draws them.
struct DownloadBar: View {
    let progress: DownloadProgress
    /// The quantization, which tells the controls of one row from another's.
    let name: String
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bar
                .accessibilityLabel("Downloading \(name)")
                .accessibilityIdentifier("download-bar")
            HStack {
                Text(Self.words(for: progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                // Not "Cancel" alone to VoiceOver or a walk: the walks
                // sweep away whatever button is called just that.
                Button("Cancel", role: .cancel, action: cancel)
                    .font(.subheadline)
                    .accessibilityLabel("Cancel download, \(name)")
            }
            // A button in a row with others: it takes its own taps rather
            // than the row taking them all.
            .buttonStyle(.borderless)
        }
    }

    /// Filled as far as the library has said, or turning while it has not
    /// said how big the download is.
    @ViewBuilder private var bar: some View {
        if let total = progress.total, total > 0 {
            ProgressView(value: Double(min(progress.bytes, total)), total: Double(total))
        } else {
            ProgressView()
        }
    }

    /// The line under the bar: "268 MB of 1.07 GB", or what the download is
    /// doing instead of coming in.
    static func words(for progress: DownloadProgress) -> String {
        switch progress.state {
        case .queued: "Waiting to start"
        case .running:
            if let total = progress.total {
                "\(Sizes.download(progress.bytes)) of \(Sizes.download(total))"
            } else {
                "\(Sizes.download(progress.bytes)) so far"
            }
        case .paused: "Paused, resumes when ggchat is open"
        case .verifying: "Checking the download"
        case .done: "Downloaded"
        case .failed(let reason): reason
        }
    }
}
