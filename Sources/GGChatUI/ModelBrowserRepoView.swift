import GGChatCore
import SwiftUI

/// One repository's quantizations, a row each: its size, whether it fits
/// this iPhone and why, and Download, which one too big for this iPhone does
/// not offer; once chosen, the download's bar and Cancel. The verdicts are
/// asked with the opening's one reading, so they agree with the suggestions
/// it showed.
struct ModelBrowserRepoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    let browser: ModelBrowser
    let repo: String
    @State private var why: WhyShown?

    var body: some View {
        List {
            if let offers = browser.offers[repo] {
                Section {
                    if offers.isEmpty {
                        Text("This repository publishes no quantization this iPhone can run.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(offers, id: \.name) { offer in
                        row(offer)
                    }
                } header: {
                    Text(repo)
                } footer: {
                    Text(checked)
                }
            } else if let failure = browser.offerFailures[repo] {
                Text(failure).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(repo.split(separator: "/").last.map(String.init) ?? repo)
        .task {
            if browser.offers[repo] == nil { await model.loadOffers(of: repo, in: browser) }
        }
        .sheet(item: $why) { shown in
            FitWhySheet(repo: repo, offer: shown.offer, checked: checked)
        }
    }

    private var checked: String {
        model.checkedLine(for: browser, locale: locale, calendar: calendar)
    }

    private func row(_ offer: QuantOffer) -> some View {
        let choice = QuantChoice(repo: repo, quantization: offer.name)
        let progress = model.onDevice.downloads[choice]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(offer.name).font(.headline)
                Spacer(minLength: 8)
                FitChip(verdict: offer.verdict)
            }
            HStack(spacing: 16) {
                Text(Self.size(offer))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Why") { why = WhyShown(offer: offer) }
                    .accessibilityLabel("Why, \(offer.name)")
                switch progress?.state {
                case .done?:
                    Text("Downloaded").font(.subheadline).foregroundStyle(.secondary)
                case nil, .failed?:
                    Button("Download") { model.download(offer, of: repo) }
                        .disabled(!offer.verdict.allowsDownload)
                        .accessibilityLabel("Download, \(offer.name)")
                default:
                    EmptyView()
                }
            }
            // Two buttons in one row: each takes its own taps rather than
            // the row taking them all.
            .buttonStyle(.borderless)
            if let progress, progress.state.isUnderWay {
                DownloadBar(progress: progress, name: offer.name) { model.cancelDownload(choice) }
            } else if case .failed(let reason)? = progress?.state {
                Text(reason).font(.caption).foregroundStyle(.red)
            }
        }
    }

    /// "1.07 GB", or "4.29 GB in 2 files" for a split model.
    private static func size(_ offer: QuantOffer) -> String {
        let size = Sizes.download(offer.totalBytes)
        return offer.shardCount > 1 ? "\(size) in \(offer.shardCount) files" : size
    }
}

/// The quantization whose Why sheet is up.
private struct WhyShown: Identifiable {
    let offer: QuantOffer
    var id: String { offer.name }
}
