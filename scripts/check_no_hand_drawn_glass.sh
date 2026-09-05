#!/usr/bin/env bash
# The transcript is flat and the glass is the system's. No view may fake
# glass or a bubble with a material or a translucent fill: Reduce
# Transparency and Increase Contrast are honoured by the glass modifiers,
# and anything hand-drawn would have to honour them by hand.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pattern='\.(ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial)|\.opacity\(0\.[0-9]+\)\s*$|Color\([^)]*opacity'
if hits=$(grep -rnE --include='*.swift' "$pattern" "$ROOT/Sources" "$ROOT/App" 2>/dev/null \
    | grep -v 'ScanTicketView.swift'); then
    echo "glass: a view draws its own translucency:" >&2
    printf '%s\n' "$hits" >&2
    exit 1
fi
echo "hand-drawn glass: none"
