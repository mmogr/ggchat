/// Replies for the incremental markdown tests: written ones that mix every
/// kind of block, and lines to build random ones from.
enum LiveMarkdownSamples {
    static let replies = [
        """
        Here's how to read a file in **Swift** and Python.

        1. Open the file.
        2. Read it:
           - as `Data`, or
           - as a `String`.

        ```swift
        let text = try String(contentsOf: url, encoding: .utf8)
        print(text)
        ```

        And in Python:

        ```python
        def read(path: str) -> list[str]:
            with open(path) as f:
                return f.read().splitlines()[1:]
        ```

        > Note: both read the whole file at once.

        ---

        That's it.
        """,
        """
        | Model | Context | Notes |
        |:------|:-------:|------:|
        | Qwen3 **27B** | 32k | fast |
        | Llama | 8k | `slow \\| old` |
        a row with no pipes
        | ^ | 4k | x |

        A paragraph straight before a table:
        | a | b |
        |---|---|
        | 1 | 2 |
        ## Heading after a table
        Text under it.
        Setext heading
        ==============
        | not | a table |
        | --- |
        """,
        """
        # Title 🚀

        Some text with émoji 😀 and 日本語.

        - item one
        - item two

          continued paragraph in item two
        - [ ] a task
        - [x] a done one

        * another list
        + and another

        <div>
        an html block
        </div>

            indented code
            second line

        Text
        ***
        ~~~
        tilde fence
        ~~~
        ```js
        const x = [1, 2]
        """,
        """
        See [the docs] and [the ref][1].

        Some more text.

        [the docs]: https://example.com/docs
        [1]: <https://example.com/1> "Title"

        After the definitions, [the docs] again.
        """,
        "Line one\r\n\r\n- a\r\n- b\r\n\r\nEnd\r\n",
        "Old Mac lines\r\rthen new ones\n\n- a\n- b\n\nEnd\n",
        "First\n\n\u{FEFF}# Not a heading after a byte-order mark\n\nThird\n",
        "See [a].\n\nMore.\n\n[a\n]: /u\n\nEnd.\n",
        "See [a b c].\n\nMore.\n\n[a\nb\nc]: /u\n\nEnd.\n",
    ]

    /// One step of a long reply: a heading, prose, code, a list and a table.
    static func step(_ number: Int) -> String {
        """
        ## Step \(number)

        Paragraph \(number) explains what this step does, in a sentence or two of prose.

        ```python
        def step_\(number)(items: list[int]) -> list[int]:
            return [x * \(number) for x in items[1:]]
        ```

        - point one for \(number)
        - point two for \(number)

        | k | v |
        |---|---|
        | \(number) | \(number * 2) |


        """
    }

    static let lines = [
        "para text", "", "", "- item", "1. item", "2. item", "> quote", "```", "```py", "    indented",
        "# head", "---", "===", "| a | b |", "|---|---|", "|:-|-:|", "| 1 | 2 |", "<div>", "</div>",
        "[x]: /u", "see [x]", "  - nested", "* star", "+ plus", "| ^ | 2 |", "a | b", "-x", "#tag", "***",
        "~~~", "  ```", "<!-- c", "-->", "\t tab", "- [ ] task", "- [x] done", "def f() -> list[int]:",
        "> - q item", ">", "   para", "| a |", "|---|", "😀 日本", "**bold** `code`", "1) paren",
        "<custom-tag>", "  continued", "`unclosed", "> ```", "> code", "[a\\]b]: /x", "\\[x]: y",
    ]

    /// A seeded generator, so a failing document is the same on every run.
    struct Random {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: state >> 33) % bound
        }
    }
}
