#!/usr/bin/env bash
# Files stay under CODE_LIMIT lines of code, and under LINE_LIMIT lines in
# all. A line of code is one that is neither blank nor a comment (`//` or
# `///` after any indent; the repo writes no `/* */`), so the prose that
# carries this repo's design record is not what a file gives up first to
# stay under the limit. The second limit keeps that prose from growing
# without bound. The repo is new, so these are thresholds and not ratchets:
# nothing has ever been allowed over them. Sources/GGLib is not counted: it
# is gglib's generated Swift, vendored as released, and check_gglib_take.sh
# holds it to the release rather than to a size.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODE_LIMIT=250
LINE_LIMIT=400
files=$(find "$ROOT/Sources" "$ROOT/Tests" "$ROOT/App" -name '*.swift' -not -path '*/.build/*' \
    -not -path "$ROOT/Sources/GGLib/*")
if [ -z "$files" ]; then
    echo "size: no Swift files under $ROOT" >&2
    exit 1
fi
# One count per file. A file awk cannot read fails the gate, through
# `set -e`, rather than counting as empty.
over=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 awk -v code_limit="$CODE_LIMIT" -v line_limit="$LINE_LIMIT" '
    function report() {
        if (name != "" && (code > code_limit || lines > line_limit))
            print code " lines of code, " lines " lines: " name
    }
    FNR == 1 { report(); name = FILENAME; code = 0; lines = 0 }
    { lines++ }
    /^[[:space:]]*$/ || /^[[:space:]]*\/\// { next }
    { code++ }
    END { report() }')
if [ -n "$over" ]; then
    echo "size: files over $CODE_LIMIT lines of code or $LINE_LIMIT lines:" >&2
    printf '%s\n' "$over" >&2
    exit 1
fi
echo "size: ok"
