#!/usr/bin/env bash
# Time and randomness are arguments in Core. Only Clock.swift may touch the
# system clock, so the mock provider and the mock pipe repeat exactly under
# an ImmediateSleeper or a gated one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pattern='Date\(\)|Date\.now|Task\.sleep|ContinuousClock\(\)|SuspendingClock\(\)|asyncAfter|Thread\.sleep|usleep\('
if hits=$(grep -rnE "$pattern" "$ROOT/Sources/GGChatCore" | grep -v '/Clock.swift:'); then
    echo "time: Core reads the clock outside Clock.swift:" >&2
    printf '%s\n' "$hits" >&2
    exit 1
fi
echo "time: ok"
