#!/usr/bin/env bash
# Every README claim that can be tested names its test in a marker:
#   <!-- test: ClassName.testName -->
# Each marker must name a test that exists. Each `make <target>` the README
# mentions must be a Makefile target.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

# A marker is satisfied only when one file declares the class and holds the
# method inside that declaration. Asking whether some file contains both,
# which is what this did, is weaker than it looks: three files here hold two
# test classes each, so `WireTests.testRecentRequestFlags` -- a class and a
# method that share a file and nothing else -- was accepted, and a marker
# went on passing after its method moved to the neighbouring class.
#
# Python rather than awk because the enforcement job runs on Linux, where
# `awk` is mawk, and this repo already reaches for python3 in the Makefile
# and the workflows.
ROOT="$ROOT" python3 - <<'PY' || status=1
import os, re, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
readme = (root / "README.md").read_text()
markers = re.findall(r"<!-- test: ([A-Za-z0-9_.]+) -->", readme)

# A type or extension at column 0 opens a region and closes the previous one.
# Members and nested types are indented, so they stay in the region they
# belong to. `extension Foo` counts as Foo: that is where a test class may
# keep some of its methods.
# The indent is captured, not skipped, and it decides whether a declaration
# opens a new region or sits inside the current one.
#
# Anchoring at column 0 was wrong: a whole test class indented inside a
# `#if canImport(Security)` never matched, so none of its methods were
# attributed to anything and every marker naming them failed. Allowing any
# indentation is also wrong, and fails differently: a nested member type — a
# helper `private final class Probe` inside a test case — would open a region
# of its own and steal every method declared after it.
#
# So a declaration opens a region only when it is at or outside the current
# region's indent. A type nested deeper is passed over, and its methods stay
# attributed to the type the reader would name in a marker.
DECL = re.compile(
    r"^(?P<indent>[ \t]*)"
    r"(?:@\w+\s+)*(?:final\s+|public\s+|internal\s+|private\s+|fileprivate\s+|open\s+)*"
    r"(?:class|struct|actor|enum|extension)\s+(?P<name>\w+)"
)

owners: dict[str, set[str]] = {}
for path in sorted(root.glob("Tests/**/*.swift")) + sorted(root.glob("App/**/*.swift")):
    current = None
    current_indent = 0
    for line in path.read_text().splitlines():
        declaration = DECL.match(line)
        if declaration:
            indent = len(declaration.group("indent").expandtabs(4))
            if current is None or indent <= current_indent:
                current = declaration.group("name")
                current_indent = indent
            continue
        if current:
            method = re.search(r"\bfunc\s+(\w+)\s*\(", line)
            if method:
                owners.setdefault(current, set()).add(method.group(1))

failed = False
for marker in markers:
    cls, _, method = marker.partition(".")
    if method not in owners.get(cls, set()):
        print(f"readme: marker names no test: {marker}", file=sys.stderr)
        print(f"readme: no file declares {cls} with a func {method} inside it", file=sys.stderr)
        failed = True
sys.exit(1 if failed else 0)
PY

while IFS= read -r target; do
    if ! grep -qE "^$target:" "$ROOT/Makefile"; then
        echo "readme: no Makefile target named $target" >&2
        status=1
    fi
done < <(grep -oE '`make [a-z-]+`' "$ROOT/README.md" | sed -E 's/`make ([a-z-]+)`/\1/' | sort -u)

[ $status -eq 0 ] && echo "readme: ok"
exit $status
