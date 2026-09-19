#!/usr/bin/env bash
# Every log line goes through a LogSink, so the redaction test can see it.
# print, debugPrint, NSLog and dump bypass that. dump prints a value's
# description and, beneath it, its mirror: every stored property unless the
# type supplies a customMirror. A URLRequest's mirror lists its headers, so
# its dump carries the Authorization header where its description is only
# its URL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if hits=$(grep -rnE '(^|[^.[:alnum:]_])((Swift|Foundation)\.)?(print|debugPrint|NSLog|dump)[[:space:]]*\(' \
    --include='*.swift' "$ROOT/Sources" "$ROOT/App" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:\s*//' | grep -vE '"[^"]*print\([^"]*"'); then
    echo "print: use a LogSink instead:" >&2
    printf '%s\n' "$hits" >&2
    exit 1
fi
echo "print: ok"
