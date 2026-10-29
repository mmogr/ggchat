#!/usr/bin/env bash
# The vendored Swift in Sources/GGLib is the pinned gglib release's, byte for
# byte, and the two frameworks Package.swift pins are that release's too.
#
# Reads the version and the two checksums from the lines
# scripts/pin_gglib.sh rewrites, downloads that release's SHA256SUMS and its
# swift archive into a fresh temporary directory, checks the archive against
# its line, and compares its four files with Sources/GGLib, which may hold
# nothing else. Each pinned checksum must then be the release's own line for
# its framework archive. SwiftPM checks a download against the manifest; this
# checks the manifest against the release the Swift came from, so the binding
# and the frameworks it is checked against at run time cannot come from two
# releases, and no hand edit of the vendored Swift survives.
#
# A checksum of zeros is refused: it pins nothing, and a tree carrying one
# cannot be built without GGLIB_FFI_LOCAL_XCFRAMEWORK. Needs the network;
# runs on Linux and macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/Package.swift"
VENDORED="$ROOT/Sources/GGLib"

fail() {
    echo "gglib take: $*" >&2
    exit 1
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# The value of one of the pinned lines, which must be declared exactly once.
pinned() {
    local values
    values=$(sed -nE "s/^let $1 = \"([^\"]*)\"\$/\\1/p" "$MANIFEST")
    [ "$(printf '%s' "$values" | grep -c .)" -eq 1 ] || fail "Package.swift does not declare $1 on exactly one line"
    printf '%s' "$values"
}

VERSION=$(pinned gglibVersion)
GGLIB_SUM=$(pinned gglibChecksum)
LLAMA_SUM=$(pinned llamaChecksum)
ZEROS=0000000000000000000000000000000000000000000000000000000000000000
if [ "$GGLIB_SUM" = "$ZEROS" ] || [ "$LLAMA_SUM" = "$ZEROS" ]; then
    fail "Package.swift pins no release of gglib $VERSION: a checksum is zeros. Take one with scripts/pin_gglib.sh $VERSION once it is published"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
RELEASE="https://github.com/mmogr/gglib/releases/download/v$VERSION"
SWIFT_ZIP="GglibFFI-swift-$VERSION.zip"
for asset in SHA256SUMS "$SWIFT_ZIP"; do
    curl -fsSL --retry 3 -o "$WORK/$asset" "$RELEASE/$asset" || fail "could not download $asset from $RELEASE"
done

# The release's line for an archive, which must be there exactly once.
release_sum() {
    local lines
    lines=$(awk -v name="$1" '$2 == name { print $1 }' "$WORK/SHA256SUMS")
    [ "$(printf '%s' "$lines" | grep -c .)" -eq 1 ] || fail "the release's SHA256SUMS has no single line for $1"
    printf '%s' "$lines"
}

SWIFT_RELEASED=$(release_sum "$SWIFT_ZIP")
GGLIB_RELEASED=$(release_sum "GglibFFI-$VERSION.xcframework.zip")
LLAMA_RELEASED=$(release_sum "llama-$VERSION.xcframework.zip")
[ "$(sha256 "$WORK/$SWIFT_ZIP")" = "$SWIFT_RELEASED" ] || fail "$SWIFT_ZIP does not hash to its line in SHA256SUMS"
[ "$GGLIB_SUM" = "$GGLIB_RELEASED" ] || fail "Package.swift's gglibChecksum is not the release's for GglibFFI-$VERSION.xcframework.zip"
[ "$LLAMA_SUM" = "$LLAMA_RELEASED" ] || fail "Package.swift's llamaChecksum is not the release's for llama-$VERSION.xcframework.zip"

mkdir "$WORK/swift"
unzip -q "$WORK/$SWIFT_ZIP" -d "$WORK/swift"
# Both ways: a file the release has and the vendored copy lacks, one the
# vendored copy has beyond the release's, and any byte that differs.
if ! difference=$(diff -r "$WORK/swift" "$VENDORED" 2>&1); then
    echo "gglib take: Sources/GGLib is not $SWIFT_ZIP as released:" >&2
    printf '%s\n' "$difference" | sed "s|$WORK/swift|$SWIFT_ZIP|g" | head -20 >&2
    echo "gglib take: take the release again with scripts/pin_gglib.sh $VERSION; never edit the binding" >&2
    exit 1
fi

echo "gglib take: ok, Sources/GGLib is $SWIFT_ZIP, and Package.swift pins that release's frameworks"
