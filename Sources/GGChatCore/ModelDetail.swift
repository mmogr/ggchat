import Foundation

// The one short line under a model's name in the model list. gglib writes
// `description` as "<architecture> - <parameters> parameters, <quantization>",
// with "unknown" for a part its catalogue does not know (gglib-core
// `ModelSummary::description`), and lists no field for either part on its
// own, so the line is read back out of that sentence. Any other server's
// description is shown as it came, on one line.

extension ModelInfo {
    /// "27B · Q8_0" for gglib's description, a part it calls unknown left
    /// out; any other description on one line; nil for none, or for one with
    /// nothing in it.
    public var detailLine: String? {
        Self.detailLine(describing: description)
    }

    /// The line `detailLine` shows for `description`, pure so a test can
    /// read gglib's own strings through it.
    public static func detailLine(describing description: String?) -> String? {
        guard let description else { return nil }
        let oneLine = description.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !oneLine.isEmpty else { return nil }
        guard let match = oneLine.wholeMatch(of: /.+ - (\S*) parameters, (.+)/) else { return oneLine }
        let parts = [String(match.1), String(match.2)].filter { !$0.isEmpty && $0 != "unknown" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
