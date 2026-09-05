#!/usr/bin/env bash
# Every log line goes through a LogSink, so the redaction test can see it.
# print, debugPrint and NSLog bypass that.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if hits=$(grep -rnE '(^|[^.[:alnum:]_])(print|debugPrint|NSLog)\(' --include='*.swift' "$ROOT/Sources" "$ROOT/App" 2>/dev/null \
    | grep -v '^\s*//' | grep -vE '^[^:]+:[0-9]+:\s*//' | grep -vE '"[^"]*print\([^"]*"'); then
    echo "print: use a LogSink instead:" >&2
    printf '%s\n' "$hits" >&2
    exit 1
fi
echo "print: ok"
