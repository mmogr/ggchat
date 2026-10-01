#!/usr/bin/env bash
# The transcript is flat and the glass is the system's. No view may fake
# glass or a bubble with a material or a translucent fill: Reduce
# Transparency and Increase Contrast are honoured by the glass modifiers,
# and anything hand-drawn would have to honour them by hand.
#
# One line is let through: the caption over the scanner's live camera
# picture, which sits on a material capsule so it can be read against
# whatever the camera sees. It is matched by its file and its text together,
# not by line number and not by the file alone, so it can move within the
# file, and a second material in that file is refused like one anywhere else.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pattern='\.(ultraThinMaterial|thinMaterial|regularMaterial|thickMaterial|ultraThickMaterial)|\.opacity\(0\.[0-9]+\)\s*$|Color\([^)]*opacity'
caption_file="$ROOT/Sources/GGChatUI/ScanTicketView.swift"
caption_line='.background(.regularMaterial, in: .capsule)'

# Only directories that exist, and grep's output captured rather than piped.
# GNU grep, which CI runs, exits 2 for a missing directory even when it
# matched elsewhere, and under pipefail that failed the pipeline -- which
# passed the check.
dirs=()
for dir in Sources App; do
    if [ -d "$ROOT/$dir" ]; then dirs+=("$ROOT/$dir"); fi
done
hits=''
if [ ${#dirs[@]} -gt 0 ]; then
    hits=$(grep -rnE --include='*.swift' "$pattern" "${dirs[@]}" 2>/dev/null || true)
fi

captions=0
strays=''
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file=${hit%%:*}
    text=${hit#*:}
    text=${text#*:}
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    if [ "$file" = "$caption_file" ] && [ "$text" = "$caption_line" ]; then
        captions=$((captions + 1))
    else
        strays+="$hit"$'\n'
    fi
done <<<"$hits"

status=0
if [ -n "$strays" ]; then
    echo "glass: a view draws its own translucency:" >&2
    printf '%s' "$strays" >&2
    status=1
fi
if [ "$captions" -gt 1 ]; then
    echo "glass: the scanner's caption is let through once, and $(basename "$caption_file") has it $captions times" >&2
    status=1
fi
[ $status -eq 0 ] && echo "hand-drawn glass: none but the scanner's caption ($captions)"
exit $status
