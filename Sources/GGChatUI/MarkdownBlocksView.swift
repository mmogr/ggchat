import GGChatCore
import SwiftUI

/// Renders parsed markdown blocks. Prose is plain text on the background;
/// code is a quiet inset panel with a copy button. No glass here.
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .textSelection(.enabled)
        case .heading(let level, let text):
            Text(text)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(item)
                            .textSelection(.enabled)
                    }
                }
            }
        case .quote(let inner):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tertiary)
                    .frame(width: 3)
                MarkdownBlocksView(blocks: inner)
            }
        case .thematicBreak:
            Divider()
        }
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 28)
                .accessibilityLabel(copied ? "Copied" : "Copy \(language ?? "code") block")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            ScrollView(.horizontal) {
                Text(code)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(.fill.tertiary, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(language ?? "Code") block")
    }

    private func copy() {
        #if os(iOS)
            UIPasteboard.general.string = code
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        #endif
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }
}
