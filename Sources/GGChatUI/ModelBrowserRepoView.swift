import GGChatCore
import SwiftUI

/// One repository's quantizations, a row each: its size, the chip saying
/// whether it fits this iPhone, which opens the sheet saying how gglib judged
/// it, and a download button, which one too big for this iPhone does not
/// have; once chosen, the download's bar and Cancel under it, and once done,
/// a mark saying it is on this iPhone. The verdicts are asked with the
/// opening's one reading, so they agree with the suggestions it showed, and
/// the footer says when that was.
struct ModelBrowserRepoView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    let browser: ModelBrowser
    let repo: String
    @State private var explaining: FitExplanation?

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
                    // The title is the model; the whole name, owner and
                    // all, is said once, here, as Hugging Face spells it.
                    Text(repo).textCase(nil)
                } footer: {
                    Text(checked)
                }
            } else if let failure = browser.offerFailures[repo] {
                Text(failure).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(RepoName.model(repo))
        .task {
            if browser.offers[repo] == nil { await model.loadOffers(of: repo, in: browser) }
        }
        .sheet(item: $explaining) { explanation in
            FitWhySheet(explanation: explanation, checked: checked)
        }
    }

    private var checked: String {
        model.checkedLine(for: browser, locale: locale, calendar: calendar)
    }

    private func row(_ offer: QuantOffer) -> some View {
        let choice = QuantChoice(repo: repo, quantization: offer.name)
        let progress = model.onDevice.downloads[choice]
        return VStack(alignment: .leading, spacing: 6) {
            CompactRow(title: Self.title(offer), detail: nil) {
                HStack(spacing: 12) {
                    FitChipButton(explanation: FitExplanation(repo: repo, offer: offer)) { explaining = $0 }
                    control(offer, progress: progress)
                }
            }
            if let progress, progress.state.isUnderWay {
                DownloadBar(progress: progress, name: offer.name) { model.cancelDownload(choice) }
            } else if case .failed(let reason)? = progress?.state {
                Text(reason).font(.caption).foregroundStyle(.red)
            }
        }
    }

    /// What ends the row: a download button, which one too big for this
    /// iPhone does not have; a mark once it is on this iPhone; nothing while
    /// it downloads, whose bar and Cancel are under the row.
    @ViewBuilder
    private func control(_ offer: QuantOffer, progress: DownloadProgress?) -> some View {
        switch progress?.state {
        case .done?:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("On this iPhone")
                .accessibilityIdentifier("downloaded")
        case nil, .failed?:
            if offer.verdict.allowsDownload {
                Button {
                    model.download(offer, of: repo)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Download, \(offer.name)")
            }
        default:
            EmptyView()
        }
    }

    /// "Q4_K_M · 1.07 GB", or "Q8_0 · 4.29 GB in 2 files" for a split model.
    nonisolated static func title(_ offer: QuantOffer) -> String {
        let size = Sizes.download(offer.totalBytes)
        let files = offer.shardCount > 1 ? " in \(offer.shardCount) files" : ""
        return "\(offer.name) · \(size)\(files)"
    }
}
