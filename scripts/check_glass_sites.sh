#!/usr/bin/env bash
# The design rule: let the system draw the glass. Exactly EXPECTED custom
# `.glassEffect` call sites exist, all in one file, inside one
# GlassEffectContainer. The number goes up only when the design doc does.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED=3

sites=$(grep -rn --include='*.swift' -E '\.glassEffect\(' "$ROOT/Sources" "$ROOT/App" 2>/dev/null || true)
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
    containers=$(grep -c 'GlassEffectContainer' "$files" || true)
    if [ "$containers" -ne 1 ]; then
        echo "glass: $files must hold exactly one GlassEffectContainer, has $containers" >&2
        exit 1
    fi
fi
echo "glass: ok ($count sites)"
