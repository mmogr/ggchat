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
            DownloadMeter(progress: progress)
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

    /// How far the download has come, "41%", or nil while the library has
    /// not said how big it is.
    nonisolated static func percent(_ progress: DownloadProgress) -> String? {
        guard let total = progress.total, total > 0 else { return nil }
        return "\(min(progress.bytes, total) * 100 / total)%"
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

/// A download on its way, on one line of the browser's "On this iPhone": the
/// model, its quantization small under it, a bar, how far it has come, and a
/// cross that calls it off. While it is not coming in, paused or waiting or
/// being checked, a line under it says so, in `DownloadBar`'s words.
struct DownloadLine: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let choice: QuantChoice
    let progress: DownloadProgress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // At the accessibility sizes the names wrap on top and the bar
            // takes a line of its own, so nothing is clipped.
            if typeSize.isAccessibilitySize {
                names
                HStack(spacing: 8) { meter }
            } else {
                HStack(spacing: 8) {
                    names
                    Spacer(minLength: 8)
                    meter
                }
            }
            if progress.state != .running {
                Text(DownloadBar.words(for: progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RepoName.model(choice.repo))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.middle)
            Text(choice.quantization)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The bar, how far it has come, and the cross.
    @ViewBuilder private var meter: some View {
        DownloadMeter(progress: progress)
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 120)
            .accessibilityLabel("Downloading \(choice.quantization)")
        if let percent = DownloadBar.percent(progress) {
            Text(percent)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        // Not "Cancel" alone to VoiceOver or a walk, for `DownloadBar`'s
        // reason.
        Button(action: cancel) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Cancel download, \(choice.quantization)")
    }
}

/// A download's bar, filled as far as the library has said, or turning while
/// it has not said how big the download is.
struct DownloadMeter: View {
    let progress: DownloadProgress

    var body: some View {
        if let total = progress.total, total > 0 {
            ProgressView(value: Double(min(progress.bytes, total)), total: Double(total))
        } else {
            ProgressView()
        }
    }
}
