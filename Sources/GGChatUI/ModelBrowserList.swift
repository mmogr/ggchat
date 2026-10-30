import GGChatCore
import SwiftUI

/// The model browser's first page, wherever it is shown: Add provider's
/// This iPhone, under its `top` (the kind picker), and the sheet of its own
/// that "Find a model…" opens (`ModelBrowserView`). A search of Hugging
/// Face; the models on this iPhone and those on their way; and what gglib
/// suggests for it, which a search's results take the place of. Each row
/// leads to a page for its repository (`ModelBrowserRepoView`), and each
/// chip opens the sheet saying how gglib judged it.
///
/// One opening reads the device once and says when, under the suggestions;
/// every size and verdict on it is the library's, asked through
/// `AppModel+Library`, and this computes none. Choosing a model there adds
/// This iPhone the first time (`AppModel+Downloads`). It sits in the
/// caller's `NavigationStack`, which the repository pages are pushed on.
struct ModelBrowserList<Top: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Bindable var browser: ModelBrowser
    /// What sits above the search in a group of its own, or nil for none.
    let top: Top?
    @State private var searching = false
    @State private var explaining: FitExplanation?

    init(browser: ModelBrowser, @ViewBuilder top: () -> Top) {
        self.browser = browser
        self.top = top()
    }

    var body: some View {
        List {
            if let top {
                Section { top }
            }
            Section {
                ModelSearchField(query: $browser.query) { run { await model.search(in: browser) } }
            }
            OnThisIPhoneSection { explaining = $0 }
            if browser.searched != nil {
                results
            } else {
                suggested
            }
        }
        .navigationDestination(for: String.self) { repo in
            ModelBrowserRepoView(browser: browser, repo: repo)
        }
        .sheet(item: $explaining) { explanation in
            FitWhySheet(explanation: explanation, checked: checked)
        }
        // A field emptied, by its cross or by hand, brings the suggestions
        // back.
        .onChange(of: browser.query) { _, query in
            if browser.searched != nil, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { await model.search(in: browser) }
            }
        }
        .task {
            if browser.suggestions == nil { await model.loadSuggestions(in: browser) }
        }
        // A task of its own, so the list is not held up by the suggestions,
        // which go out to Hugging Face.
        .task { await model.refreshInstalled() }
    }

    private var checked: String {
        model.checkedLine(for: browser, locale: locale, calendar: calendar)
    }

    private var suggested: some View {
        Section {
            if let suggestions = browser.suggestions {
                if suggestions.isEmpty {
                    Text("gglib has nothing to suggest for this iPhone.").foregroundStyle(.secondary)
                }
                ForEach(suggestions, id: \.self) { suggestion in
                    SuggestionRow(suggestion: suggestion) { explaining = $0 }
                }
            } else if let failure = browser.suggestionsFailure {
                Text(failure).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        } header: {
            Text("Suggested")
        } footer: {
            Text(checked)
        }
    }

    private var results: some View {
        Section("Hugging Face") {
            ForEach(browser.hits, id: \.repo) { hit in
                NavigationLink(value: hit.repo) {
                    HitRow(hit: hit)
                }
            }
            if searching {
                ProgressView()
            } else if let failure = browser.searchFailure {
                Text(failure).foregroundStyle(.secondary)
            } else if browser.hits.isEmpty {
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

extension ModelBrowserList where Top == EmptyView {
    /// The browser with nothing above its search.
    init(browser: ModelBrowser) {
        self.browser = browser
        top = nil
    }
}
