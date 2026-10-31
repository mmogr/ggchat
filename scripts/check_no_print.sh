#!/usr/bin/env bash
# Every log line goes through a LogSink, so the redaction test can see it.
# print, debugPrint, NSLog and dump bypass that. dump prints a value's
# description and, beneath it, its mirror: every stored property unless the
# type supplies a customMirror. A URLRequest's mirror lists its headers, so
# its dump carries the Authorization header where its description is only
# its URL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib/scan.sh
. "$ROOT/scripts/lib/scan.sh"
# Not Sources/GGLib, gglib's generated Swift, vendored as released and held to
# the release by check_gglib_take.sh: the one `print` uniffi writes there is
# for a handle it cannot find, which never reaches this app's log.
found=$(scan -rnE '(^|[^.[:alnum:]_])((Swift|Foundation)\.)?(print|debugPrint|NSLog|dump)[[:space:]]*\(' \
    --include='*.swift' --exclude-dir=GGLib "$ROOT/Sources" "$ROOT/App")
hits=$(printf '%s\n' "$found" | grep -v '^$' | grep -vE '^[^:]+:[0-9]+:\s*//' | grep -vE '"[^"]*print\([^"]*"' || true)
if [ -n "$hits" ]; then
    echo "print: use a LogSink instead:" >&2
    printf '%s\n' "$hits" >&2
    exit 1
fi
echo "print: ok"
