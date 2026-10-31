#!/usr/bin/env bash
# The design rule: let the system draw the glass. Exactly EXPECTED custom
# `.glassEffect` call sites exist, all in one file, inside one
# GlassEffectContainer. The number goes up only when the design doc does.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib/scan.sh
. "$ROOT/scripts/lib/scan.sh"
EXPECTED=3

# Not Sources/GGLib: gglib's generated Swift, vendored as released.
sites=$(scan -rn --include='*.swift' --exclude-dir=GGLib -E '\.glassEffect\(' "$ROOT/Sources" "$ROOT/App")
count=$(printf '%s' "$sites" | grep -c . || true)
if [ "$count" -ne "$EXPECTED" ]; then
    echo "glass: expected $EXPECTED .glassEffect sites, found $count" >&2
    printf '%s\n' "$sites" >&2
    exit 1
fi
if [ "$count" -gt 0 ]; then
    files=$(printf '%s\n' "$sites" | cut -d: -f1 | sort -u)
    if [ "$(printf '%s\n' "$files" | wc -l | tr -d ' ')" -ne 1 ]; then
        echo "glass: sites are spread over several files:" >&2
        printf '%s\n' "$files" >&2
        exit 1
    fi
    # `scan`, not `|| true`: a file it cannot read counted as no container
    # and an empty count, which `-ne` cannot compare, so the `if` passed.
    containers=$(scan -c 'GlassEffectContainer' "$files")
    if [ "$containers" -ne 1 ]; then
        echo "glass: $files must hold exactly one GlassEffectContainer, has $containers" >&2
        exit 1
    fi
fi
echo "glass: ok ($count sites)"
