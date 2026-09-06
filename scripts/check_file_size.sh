#!/usr/bin/env bash
# Files stay under LIMIT lines. The repo is new, so this is a threshold and
# not a ratchet: nothing has ever been allowed over it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIMIT=300
over=$(find "$ROOT/Sources" "$ROOT/Tests" "$ROOT/App" -name '*.swift' -not -path '*/.build/*' 2>/dev/null \
    -exec wc -l {} + | awk -v limit="$LIMIT" '$2 != "total" && $1 > limit { print $1 " " $2 }' || true)
if [ -n "$over" ]; then
    echo "size: files over $LIMIT lines:" >&2
    printf '%s\n' "$over" >&2
    exit 1
fi
echo "size: ok"
