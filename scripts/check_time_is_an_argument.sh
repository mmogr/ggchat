#!/usr/bin/env bash
# Time and randomness are arguments in Core. Only Clock.swift may touch the
# system clock, so the mock provider and the mock pipe repeat exactly under
# an ImmediateSleeper or a gated one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pattern='Date\(\)|Date\.now|Task\.sleep|ContinuousClock\(\)|SuspendingClock\(\)|asyncAfter|Thread\.sleep|usleep\('
# Both targets below the seam. GGChatPipe is where a retry or a settling delay
# would be written, so it is the one that most needs a `Sleeper` rather than a
# real clock -- a connector that slept for real would make its own tests slow
# and non-deterministic.
#
# Each directory is required to exist. `grep` over a missing path exits 2, and
# the `if` below reads any non-zero as "no hits", so a renamed target would
# have turned this gate off and still printed "ok".
for module in GGChatCore GGChatPipe; do
    [ -d "$ROOT/Sources/$module" ] || {
        echo "time: Sources/$module is missing, so this gate would pass vacuously" >&2
        exit 1
    }
done
if hits=$(grep -rnE "$pattern" "$ROOT/Sources/GGChatCore" "$ROOT/Sources/GGChatPipe" | grep -v '/Clock.swift:'); then
    echo "time: a module below the seam reads the clock outside Clock.swift:" >&2
    printf '%s\n' "$hits" >&2
    exit 1
fi
echo "time: ok"
