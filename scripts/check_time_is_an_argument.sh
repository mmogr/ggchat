#!/usr/bin/env bash
# Time and randomness are arguments in Core. Only Clock.swift may touch the
# system clock, so the mock provider and the mock pipe repeat exactly under
# an ImmediateSleeper or a gated one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib/scan.sh
. "$ROOT/scripts/lib/scan.sh"
pattern='Date\(\)|Date\.now|Task\.sleep|ContinuousClock\(\)|SuspendingClock\(\)|asyncAfter|Thread\.sleep|usleep\('
# Every target below the seams. GGChatPipe is where a retry or a settling
# delay would be written, so it is the one that most needs a `Sleeper` rather
# than a real clock -- a connector that slept for real would make its own
# tests slow and non-deterministic -- and GGChatLocal, which wraps gglib's
# binding as GGChatPipe wraps modelpipe's, is held to the same.
#
# Each directory is required to exist, so a renamed target is reported as
# missing. A file grep cannot read fails the gate too (`scan`): the `if` this
# replaced read a missing path and an unreadable file alike as "no hits", and
# printed "ok".
for module in GGChatCore GGChatPipe GGChatLocal; do
    [ -d "$ROOT/Sources/$module" ] || {
        echo "time: Sources/$module is missing, so this gate would pass vacuously" >&2
        exit 1
    }
done
found=$(scan -rnE "$pattern" "$ROOT/Sources/GGChatCore" "$ROOT/Sources/GGChatPipe" "$ROOT/Sources/GGChatLocal")
hits=$(printf '%s\n' "$found" | grep -v '^$' | grep -v '/Clock.swift:' || true)
if [ -n "$hits" ]; then
    echo "time: a module below the seam reads the clock outside Clock.swift:" >&2
    printf '%s\n' "$hits" >&2
    exit 1
fi
echo "time: ok"
