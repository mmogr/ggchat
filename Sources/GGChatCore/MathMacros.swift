import Foundation

/// The few LaTeX commands models write that SwiftMath, which draws math in
/// ggchat, does not know, each said in ones it does, as KaTeX defines many of
/// its own. Used only for drawing: the text keeps what the model wrote.
///
/// - `\mathrel{X}` is `X` with a thick space either side, the space TeX puts
///   around a relation between two ordinary symbols. TeX leaves that space
///   out in a few places, after another relation or at the start of a
///   formula, where this keeps it.
/// - `\:` is the medium space, which SwiftMath calls `\>`.
/// - `\dots` is `\ldots`.
/// - `\lvert` and `\rvert` are `\vert`, and `\lVert` and `\rVert` are
///   `\Vert`.
///
/// A command SwiftMath knows that has one of these as a prefix, as `\dotsc`
/// has `\dots`, is left as it is, and so is a `\mathrel` with no braced
/// argument after it.
public enum MathMacros {
    public static func expand(_ latex: String) -> String {
        guard latex.contains("\\") else { return latex }
        let characters = Array(latex)
        var out = ""
        var index = 0
        while index < characters.count {
            guard characters[index] == "\\", index + 1 < characters.count else {
                out.append(characters[index])
                index += 1
                continue
            }
            let name = commandName(characters, at: index + 1)
            let end = index + 1 + name.count
            if name == "mathrel", let (open, close) = argument(characters, from: end) {
                out += #"\;"# + expand(String(characters[(open + 1)..<close])) + #"\;"#
                index = close + 1
                continue
            }
            out += replacements[name].map { "\\" + $0 } ?? "\\" + name
            index = end
        }
        return out
    }

    private static let replacements: [String: String] = [
        ":": ">", "dots": "ldots", "lvert": "vert", "rvert": "vert", "lVert": "Vert", "rVert": "Vert",
    ]

    /// The command after a backslash at `start`: a run of letters, or else
    /// the one character there.
    private static func commandName(_ characters: [Character], at start: Int) -> String {
        let letters = characters[start...].prefix { $0.isASCII && $0.isLetter }
        return letters.isEmpty ? String(characters[start]) : String(letters)
    }

    /// The braces of an argument at `start`, after spaces, if one opens
    /// there and closes. A brace after a backslash is escaped.
    private static func argument(_ characters: [Character], from start: Int) -> (open: Int, close: Int)? {
        var index = start
        while index < characters.count, characters[index] == " " { index += 1 }
        guard index < characters.count, characters[index] == "{" else { return nil }
        let open = index
        var depth = 0
        while index < characters.count {
            switch characters[index] {
            case "\\":
                index += 2
                continue
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return (open, index) }
            default:
                break
            }
            index += 1
        }
        return nil
    }
}
