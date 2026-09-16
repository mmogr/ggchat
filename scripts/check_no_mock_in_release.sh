#!/usr/bin/env bash
# The mock pipe is absent from a release build, not merely unchosen by it.
#
# `PipeConnectorFactory` picks `ModelpipeConnector` outside DEBUG, but a mock
# left unchosen is still in the binary.
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

# Where a module's release objects are depends on which build system `swift
# build` ran. The native one writes `.build/release/<Module>.build/<File>.swift.o`;
# the swiftbuild one, the default from Swift 6.4, writes one object per source
# under `.build/out/Intermediates.noindex/<package>.build/Release/<Module>-*.build/
# Objects-normal/<arch>/<File>.o`, and leaves `.build/release` pointing at the
# products, which hold each module as one merged object and a static library.
# Either per-file layout is read; the merged object is not, because the
# sentinel check below wants the object of one named source.
#
# The layout is decided once, from where `.build/release` points: `swift build`
# repoints that symlink on every build, at `out/Products/Release` under
# swiftbuild and at `<triple>/release` under the native system. Deciding from
# the build that just ran is what keeps a leftover tree from the other build
# system out of the reading: a native build does not clean `.build/out`, so a
# tree that has seen both systems keeps swiftbuild's objects indefinitely, and
# a check that fell back to them when a native module directory was missing
# certified that module from a build that was not this one. Under the layout
# chosen, a module with no objects fails below.
#
# The link is followed, not read as a label: a dangling link, a link at another
# configuration or no link at all is refused here, rather than answered from a
# glob that never looked where the link points.
case "$(cd "$ROOT/.build/release" 2>/dev/null && pwd -P)" in
    */out/Products/Release) LAYOUT=swiftbuild ;;
    */release) LAYOUT=native ;;
    *)
        echo "release: $ROOT/.build/release is missing or is not a release build directory; run 'make build-release'" >&2
        exit 1
        ;;
esac

release_objects() {
    local module=$1 dir
    if [ "$LAYOUT" = native ]; then
        find "$ROOT/.build/release/$module.build" -name '*.o' 2>/dev/null || true
        return
    fi
    for dir in "$ROOT"/.build/out/Intermediates.noindex/*.build/Release/"$module"-*.build/Objects-normal; do
        [ -d "$dir" ] || continue
        find "$dir" -name '*.o' 2>/dev/null || true
    done
}

# Compiled in every configuration, so its presence is the proof that the module
# declaring the mock was really read. Looked for in its own object and not
# across the union of both targets' symbols: the name also appears in three
# GGChatUI objects that call the factory, so a union check stays green with
# GGChatCore's objects deleted -- certifying the mock absent from a module it
# never opened. Per target for the same reason: each must have yielded objects.
SENTINEL='UnavailablePipeConnector'

objects=''
for module in GGChatCore GGChatPipe GGChatUI; do
    found=$(release_objects "$module")
    if [ -z "$found" ]; then
        echo "release: no objects for $module under the $LAYOUT layout of $ROOT/.build; run 'make build-release'" >&2
        exit 1
    fi
    objects="$objects$found"$'\n'
done

# `UnavailablePipeConnector.swift.o` under the native layout,
# `UnavailablePipeConnector.o` under swiftbuild; exactly one either way.
SENTINEL_OBJECT=$(release_objects GGChatCore | grep -E "/$SENTINEL(\.swift)?\.o\$" || true)
if [ "$(printf '%s' "$SENTINEL_OBJECT" | grep -c .)" -ne 1 ]; then
    echo "release: expected one $SENTINEL object among GGChatCore's, found:" >&2
    printf '%s\n' "$SENTINEL_OBJECT" >&2
    echo "release: so GGChatCore was not really read" >&2
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

echo "release: ok, no mock pipe in the release build ($LAYOUT layout)"
