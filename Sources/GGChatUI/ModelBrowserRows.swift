import GGChatCore
import SwiftUI

/// A browser row: a title, a small detail after it if there is one, and a
/// control trailing. On one line where they fit, with the detail under the
/// title where they do not, the title cut in the middle; at the
/// accessibility sizes, one under another, wrapping, so nothing is clipped.
///
/// With a `link`, the title and detail are a link to that repository's page
/// and the control sits beside the link, not in it, so each takes its own
/// taps and VoiceOver reaches both.
struct CompactRow<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let detail: String?
    let link: String?
    let trailing: Trailing

    init(title: String, detail: String?, link: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.link = link
        self.trailing = trailing()
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                linked(
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                        detailText
                    })
                trailing
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    linked(
                        HStack(spacing: 8) {
                            Text(title).lineLimit(1)
                            detailText.lineLimit(1)
                        })
                    trailing
                }
                HStack(spacing: 8) {
                    linked(
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).lineLimit(1).truncationMode(.middle)
                            detailText.lineLimit(1)
                        })
                    trailing
                }
            }
        }
    }

    /// `content` filling the row's leading part, as a link to `link`'s page
    /// when there is one.
    @ViewBuilder
    private func linked(_ content: some View) -> some View {
        let filled = content.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
        if let link {
            // The plain style drops the list's own chevron, so the row draws
            // one, as a hit row has, before its chip.
            NavigationLink(value: link) {
                HStack(spacing: 4) {
                    filled
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
        } else {
            filled
        }
    }

    @ViewBuilder private var detailText: some View {
        if let detail {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A repository's name as the browser says it: the model, which is the last
/// part, and the owner before it.
enum RepoName {
    /// "Qwen3-1.7B-GGUF" for "Qwen/Qwen3-1.7B-GGUF".
    nonisolated static func model(_ repo: String) -> String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }

    /// "Qwen" for "Qwen/Qwen3-1.7B-GGUF", or nil for a name with no owner.
    nonisolated static func owner(_ repo: String) -> String? {
        let parts = repo.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
    }
}

/// A suggestion: the model, its quantization and size, which lead to its
/// repository's page, and beside them the chip, which opens the sheet that
/// says gglib's sentence on why this one.
struct SuggestionRow: View {
    let suggestion: Suggestion
    let explain: (FitExplanation) -> Void

    var body: some View {
        CompactRow(title: RepoName.model(suggestion.repo), detail: Self.detail(suggestion), link: suggestion.repo) {
            FitChipButton(
                explanation: FitExplanation(suggestion: suggestion),
                identifier: "fit-\(suggestion.repo)/\(suggestion.quantization)", open: explain)
        }
    }

    /// "Q4_K_M · 1.07 GB".
    nonisolated static func detail(_ suggestion: Suggestion) -> String {
        "\(suggestion.quantization) · \(Sizes.download(suggestion.bytes))"
    }
}

/// A search hit: the model, its owner small beside it, and what Hugging Face
/// says of it under them.
struct HitRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let layout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            layout {
                Text(RepoName.model(hit.repo))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.middle)
                if let owner = RepoName.owner(hit.repo) {
                    Text(owner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(Self.detail(hit, locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "1.7B · 40K context · 9,400 downloads", leaving out what the
    /// repository does not say.
    nonisolated static func detail(_ hit: SearchHit, locale: Locale) -> String {
        var parts: [String] = []
        if let billions = hit.parametersB {
            parts.append("\(billions.formatted(.number.precision(.fractionLength(0...1)).locale(locale)))B")
        }
        if let trained = hit.trainedCtx { parts.append("\(FitChip.context(trained)) context") }
        parts.append("\(hit.downloads.formatted(.number.locale(locale))) downloads")
        return parts.joined(separator: " · ")
    }
}

/// The search field at the top of the browser: Hugging Face is searched as
/// the keyboard's Search is pressed, and clearing the field brings the
/// suggestions back.
struct ModelSearchField: View {
    @Binding var query: String
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search Hugging Face", text: $query)
                .submitLabel(.search)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .onSubmit(submit)
                .accessibilityIdentifier("model-search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
    }
}
