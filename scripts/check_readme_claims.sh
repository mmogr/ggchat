#!/usr/bin/env bash
# Every README claim that can be tested names its test in a marker:
#   <!-- test: ClassName.testName -->
# Each marker must name a test that exists. Each `make <target>` the README
# mentions must be a Makefile target.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

while IFS= read -r marker; do
    class="${marker%%.*}"
    method="${marker#*.}"
    if ! grep -rlE "class $class\b" "$ROOT/Tests" | xargs grep -lE "func $method\b" >/dev/null 2>&1; then
        echo "readme: marker names no test: $marker" >&2
        status=1
    fi
done < <(grep -oE '<!-- test: [A-Za-z0-9_.]+ -->' "$ROOT/README.md" | sed -E 's/<!-- test: (.*) -->/\1/')

while IFS= read -r target; do
    if ! grep -qE "^$target:" "$ROOT/Makefile"; then
        echo "readme: no Makefile target named $target" >&2
        status=1
    fi
done < <(grep -oE '`make [a-z-]+`' "$ROOT/README.md" | sed -E 's/`make ([a-z-]+)`/\1/' | sort -u)

[ $status -eq 0 ] && echo "readme: ok"
exit $status
