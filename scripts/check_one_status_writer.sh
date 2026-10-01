#!/usr/bin/env bash
# One writer for `pipeStatuses` and `pipeCloseReasons`. The pill the user
# reads and the sentence saying why are the same event, and they are one event
# only because every write goes through `setPipeStatus`, which is also where
# the last-heard mark, the haptic and a send waiting for the pipe hear of a
# change. A direct `pipeStatuses[id] = .closed` anywhere else shows a close
# none of those hears about. A direct `pipeCloseReasons[id] = ...` is the
# same bug wearing the other hat: a reason written from somewhere the status is
# not would explain a different close from the one on screen.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRITER=setPipeStatus
# Both dictionaries the writer owns, as an alternation for awk.
GUARDED='pipeStatuses|pipeCloseReasons'

strays=$(
    find "$ROOT/Sources" "$ROOT/App" -name '*.swift' -print0 2>/dev/null \
        | xargs -0 awk -v writer="$WRITER" -v guarded="$GUARDED" '
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
            $0 ~ "(" guarded ")(\\[[^]]*\\])?[[:space:]]*(=[^=]|\\+=)" ||
                $0 ~ "(" guarded ")\\.(removeAll|removeValue|updateValue)" {
                    if (fn != writer) {
                        printf "%s:%d:%s\n", FILENAME, FNR, $0
                    }
                }
        ' || true
)

if [ -n "$strays" ]; then
    echo "pipe status: written outside $WRITER(), so the change it shows goes unheard or unexplained:" >&2
    printf '%s\n' "$strays" >&2
    exit 1
fi
echo "pipe status: ok (one writer for status and reason)"
