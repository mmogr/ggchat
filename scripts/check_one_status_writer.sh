#!/usr/bin/env bash
# One writer for `pipeStatuses`. The pill the user reads and ADR 0002's "of M
# closes" are the same event only because every write goes through
# `setPipeStatus(_:for:cutShort:)`, which is where the counting is. A direct
# `pipeStatuses[id] = .closed` anywhere else shows a close the counter never
# hears about — the bug this gate exists to keep fixed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRITER=setPipeStatus

strays=$(
    find "$ROOT/Sources" "$ROOT/App" -name '*.swift' -print0 2>/dev/null \
        | xargs -0 awk -v writer="$WRITER" '
            FNR == 1 { fn = "" }
            # A comment quoting a write is not a write, and does not name the
            # function a write would be in either.
            /^[[:space:]]*(\/\/|\/\*|\*)/ { next }
            # The enclosing function, so a write can be attributed to one.
            match($0, /(^|[^A-Za-z0-9_])func[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
                fn = substr($0, RSTART, RLENGTH)
                sub(/.*func[[:space:]]+/, "", fn)
            }
            # A subscript assignment, and replacing or emptying the whole
            # dictionary. `==` and `!=` are reads and do not match.
            /pipeStatuses(\[[^]]*\])?[[:space:]]*(=[^=]|\+=)/ ||
                /pipeStatuses\.(removeAll|removeValue|updateValue)/ {
                    if (fn != writer) {
                        printf "%s:%d:%s\n", FILENAME, FNR, $0
                    }
                }
        ' || true
)

if [ -n "$strays" ]; then
    echo "pipe status: written outside $WRITER(), so the close it shows is not counted:" >&2
    printf '%s\n' "$strays" >&2
    exit 1
fi
echo "pipe status: ok (one writer)"
