import GGChatCore
import SwiftUI

/// Finds a model for this iPhone: what gglib suggests for it, a search of
/// Hugging Face, and a page for each repository saying whether each of its
/// quantizations fits, and why. One opening reads the device once and says
/// when; every size and verdict on it is the library's, asked through
/// `AppModel+Library`, and this computes none.
struct ModelBrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Bindable var browser: ModelBrowser
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                suggested
                search
            }
            .navigationTitle("Find a model")
            .navigationDestination(for: String.self) { repo in
                ModelBrowserRepoView(browser: browser, repo: repo)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if browser.suggestions == nil { await model.loadSuggestions(in: browser) }
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 480)
        #endif
    }

    private var suggested: some View {
        Section {
            if let suggestions = browser.suggestions {
                if suggestions.isEmpty {
                    Text("gglib has nothing to suggest for this iPhone.").foregroundStyle(.secondary)
                }
                ForEach(suggestions, id: \.self) { suggestion in
                    NavigationLink(value: suggestion.repo) {
                        SuggestionRow(suggestion: suggestion)
                    }
                }
            } else if let failure = browser.suggestionsFailure {
                Text(failure).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        } header: {
            Text("Suggested for this iPhone")
        } footer: {
            Text(model.checkedLine(for: browser, locale: locale, calendar: calendar))
        }
    }

    private var search: some View {
        Section("Search") {
            TextField("Search Hugging Face", text: $browser.query)
                .submitLabel(.search)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .onSubmit { run { await model.search(in: browser) } }
                .accessibilityIdentifier("model-search")
            ForEach(browser.hits, id: \.repo) { hit in
                NavigationLink(value: hit.repo) {
                    HitRow(hit: hit)
                }
            }
            if searching {
                ProgressView()
            } else if let failure = browser.searchFailure {
                Text(failure).foregroundStyle(.secondary)
            } else if browser.searched != nil, browser.hits.isEmpty {
                Text("Nothing on Hugging Face matches that.").foregroundStyle(.secondary)
            } else if browser.nextCursor != nil {
                Button("More results") { run { await model.searchMore(in: browser) } }
            }
        }
    }

    /// One search at a time, with a spinner in its place while it runs.
    private func run(_ search: @escaping () async -> Void) {
        guard !searching else { return }
        searching = true
        Task {
            await search()
            searching = false
        }
    }
}

/// A suggestion: the repository, the quantization and its size, whether it
/// fits, and gglib's sentence on why this one.
private struct SuggestionRow: View {
    let suggestion: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.repo)
            HStack {
                Text("\(suggestion.quantization) · \(Sizes.download(suggestion.bytes))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                FitChip(verdict: suggestion.verdict)
            }
            Text(suggestion.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A search hit: the repository and what Hugging Face says of it.
private struct HitRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hit.repo)
            Text(Self.detail(hit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "1.7B parameters · trained on 40K · 9,400 downloads", leaving out
    /// what the repository does not say.
    static func detail(_ hit: SearchHit) -> String {
        var parts: [String] = []
        if let billions = hit.parametersB {
            parts.append("\(billions.formatted(.number.precision(.fractionLength(0...1))))B parameters")
        }
        if let trained = hit.trainedCtx { parts.append("trained on \(FitChip.context(trained))") }
        parts.append("\(hit.downloads.formatted()) downloads")
        return parts.joined(separator: " · ")
    }
}
