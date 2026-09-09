#!/usr/bin/env bash
# The mock pipe is absent from a release build, not merely unchosen by it.
#
# `PipeConnectorFactory` picks `UnavailablePipeConnector` outside DEBUG, but
# that is a choice made at runtime by a binary that still contains the mock.
# `MockPipeConnector` and `MockPipeSession` are therefore declared inside an
# `#if DEBUG`, and this is what holds them there: a release build alone would
# not, because the mock compiles perfectly well in one.
#
# Every target that could carry the symbols is scanned, GGChatPipe included:
# the loop below is the whole of the search, so a target left out of it is a
# target certified clean without being opened.
#
# Symbols, not sources. A grep over the sources would have to strip comments --
# `PipeConnector.swift` and `UnavailablePipeConnector.swift` both name the mock
# in a doc comment, on purpose, and a source grep would fail a correctly fixed
# tree.
#
# Needs a Swift toolchain and the macOS SDK, so it is not in `make enforce`
# (that job runs on Linux); `make build-release` runs the build and then this.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BANNED='MockPipeConnector|MockPipeSession'
CORE="$ROOT/.build/release/GGChatCore.build"
PIPE="$ROOT/.build/release/GGChatPipe.build"
UI="$ROOT/.build/release/GGChatUI.build"
# Compiled in every configuration, so its presence is the proof that the module
# declaring the mock was really read. Looked for in its own object and not
# across the union of both targets' symbols: the name also appears in three
# GGChatUI objects that call the factory, so a union check stays green with
# GGChatCore.build deleted -- certifying the mock absent from a module it never
# opened. Per target for the same reason: each must have yielded objects.
SENTINEL='UnavailablePipeConnector'
SENTINEL_OBJECT="$CORE/$SENTINEL.swift.o"

objects=''
for target in "$CORE" "$PIPE" "$UI"; do
    found=$(find "$target" -name '*.o' 2>/dev/null || true)
    if [ -z "$found" ]; then
        echo "release: no objects under $target; run 'make build-release'" >&2
        exit 1
    fi
    objects="$objects$found"$'\n'
done

if [ ! -f "$SENTINEL_OBJECT" ]; then
    echo "release: $SENTINEL_OBJECT is missing, so GGChatCore was not really read" >&2
    exit 1
fi
# `grep -c` and not `grep -q`: `-q` closes the pipe on its first match and
# `pipefail` would read nm's SIGPIPE as a failed search.
if [ "$(nm -a "$SENTINEL_OBJECT" | grep -cE "$SENTINEL" || true)" -eq 0 ]; then
    echo "release: no $SENTINEL symbol in $SENTINEL_OBJECT, so nothing was really inspected" >&2
    exit 1
fi

symbols=$(mktemp)
trap 'rm -f "$symbols"' EXIT

# nm prints a `path/to/file.o:` header per file, and one of those paths is
# MockPipeConnector.swift.o -- the file is still compiled, it just yields
# nothing now. Matching a header would fail the very tree this is meant to
# pass, so the headers go. A file and not a pipe, for the reason just above.
printf '%s' "$objects" | tr '\n' '\0' | xargs -0 nm -a | grep -v ':$' > "$symbols"

count=$(grep -cE "$BANNED" "$symbols" || true)
if [ "$count" -ne 0 ]; then
    echo "release: the mock pipe is in the release build ($count symbols matching $BANNED):" >&2
    grep -E "$BANNED" "$symbols" | head -5 >&2
    exit 1
fi

echo "release: ok, no mock pipe in the release build"
