#!/usr/bin/env bash
# No credential in any log line, ever. This is the static half: a log call
# may not interpolate an identifier that names a credential, and may not
# log a request's headers. The runtime half is
# OpenAICompatibleProviderTests.testNoCredentialEverReachesALogLine.
#
# It works by name. A value that holds a secret has to go by a name with one
# of these words in it, in any case: `apiKey` or `token` for a key, `ticket`
# for a ticket, `pairing` for a ticket-code pairing string or a reading of
# one, `secret` or `credential` for a credential on its way into or out of
# the store. A name with none of them is one this cannot see; the few left
# so are named in the change that closed #109. A value interpolated whole
# is judged by its name as well, so what `\(paired)` prints is the type's
# to keep clean (#110), not this gate's.
#
# Each call is read twice, and refused if either reading finds a listed
# word after an interpolation (`\(` or a raw `\#(`), literal text included:
# - line by line, as this gate always has, so a call on one line is read
#   with the rest of its line;
# - whole, from `.log(` or `logger.<level>(` to the parenthesis that
#   closes it, so a call swift-format wraps across lines is one call. String
#   literals (raw ones too), their interpolations and comments are read as
#   what they are, so a parenthesis in any of them does not end the call. A
#   call that never closes, such as a `.log(` in a comment, is read as its
#   first line.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$ROOT" python3 - <<'PY'
import os, re, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
call = re.compile(r"\.log\(|logger\.(?:trace|debug|info|notice|warning|error|critical|fault)\(")
names = re.compile(
    r"\\#*\(.*(?:apikey|token|ticket|secret|credential|pairing|authorization|allhttpheaderfields|httpbody)",
    re.IGNORECASE,
)


def closing(text, at):
    """Index of the parenthesis that closes the one at `at`, or -1.

    A frame is code (with its parenthesis depth), a string literal (with its
    count of `#`s and whether it is a `\"\"\"` block), or a block comment
    (with its nesting). An interpolation is a code frame inside a string.
    """
    frames = [["code", 0]]
    i = at
    while i < len(text):
        top = frames[-1]
        if top[0] == "code":
            if text.startswith("//", i):
                end = text.find("\n", i)
                i = len(text) if end < 0 else end
                continue
            if text.startswith("/*", i):
                frames.append(["comment", 1])
                i += 2
                continue
            if text[i] in '#"':
                j = i
                while j < len(text) and text[j] == "#":
                    j += 1
                if j < len(text) and text[j] == '"':
                    block = text.startswith('"""', j)
                    frames.append(["string", j - i, block])
                    i = j + (3 if block else 1)
                    continue
            if text[i] == "(":
                top[1] += 1
            elif text[i] == ")":
                top[1] -= 1
                if top[1] == 0:
                    if len(frames) == 1:
                        return i
                    frames.pop()
            i += 1
            continue
        if top[0] == "comment":
            if text.startswith("/*", i):
                top[1] += 1
                i += 2
            elif text.startswith("*/", i):
                top[1] -= 1
                i += 2
                if top[1] == 0:
                    frames.pop()
            else:
                i += 1
            continue
        _, hashes, block = top
        escape = "\\" + "#" * hashes
        close = ('"""' if block else '"') + "#" * hashes
        if text.startswith(escape + "(", i):
            frames.append(["code", 1])
            i += len(escape) + 1
        elif text.startswith(escape, i):
            i += len(escape) + 1
        elif text.startswith(close, i):
            frames.pop()
            i += len(close)
        elif text[i] == "\n" and not block:
            frames.pop()
            i += 1
        else:
            i += 1
    return -1


hits, calls = [], 0
for folder in ("Sources", "App"):
    if not (root / folder).is_dir():
        sys.exit(f"log: {folder}/ is missing, so there is nothing to read")
    for path in sorted((root / folder).rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for m in call.finditer(text):
            calls += 1
            start = text.rfind("\n", 0, m.start()) + 1
            line_end = text.find("\n", m.start())
            line_end = len(text) if line_end < 0 else line_end
            end = closing(text, m.end() - 1)
            if end < 0:
                end = line_end - 1
            line = text[start:line_end]
            whole = " ".join(part.strip() for part in text[m.start() : end + 1].splitlines())
            if names.search(line) or names.search(whole):
                shown = " ".join(part.strip() for part in text[start : max(end + 1, line_end)].splitlines())
                hits.append(f"{path.relative_to(root)}:{text.count(chr(10), 0, m.start()) + 1}: {shown}")

if calls == 0:
    sys.exit("log: no log call found under Sources/ or App/, which is a gate reading nothing")
if hits:
    print("log: a log call touches a credential or a header:", file=sys.stderr)
    print("\n".join(hits), file=sys.stderr)
    sys.exit(1)
print(f"log: ok ({calls} calls)")
PY
