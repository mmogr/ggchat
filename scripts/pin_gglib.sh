#!/usr/bin/env bash
# Takes a gglib release, or a local gglib build, into this package.
#
#   scripts/pin_gglib.sh <version>
#   scripts/pin_gglib.sh --local <gglib checkout>
#
# <version>, 0.28.0-rc.2 say, takes release v<version> of mmogr/gglib. Its
# SHA256SUMS and its three archives are downloaded into a fresh temporary
# directory and each archive is checked against its line there before
# anything here changes. Then Sources/GGLib is replaced by the four files of
# the swift archive, binding.json included, which names what the framework's
# build_info() reports; and last the three lines Package.swift keeps for it are
# rewritten (the version, and each framework archive's checksum, which is its
# SHA-256), the rewrite refused if it left the file as it was. Each is made
# beside its place and moved in by rename, so neither is ever half written.
# Commit the two together: the Swift and the frameworks are one artifact, and
# scripts/check_gglib_take.sh holds the vendored Swift to the release.
#
# --local <gglib checkout> takes that checkout's own build instead, for a
# build with GGLIB_FFI_LOCAL_XCFRAMEWORK=1. Its target/apple/GglibFFI.xcframework
# (`make ffi-xcframework` there) and the llama.xcframework at the pin its
# scripts/llama_pin.sh names (`make phone-llama`, in target/apple/llama-<pin>)
# are copied into build/, and Sources/GGLib is replaced by the Swift that
# build generated beside the framework, with a binding.json made as gglib's
# release packaging makes one. Package.swift is left alone. Copied, not
# linked, so a gglib rebuilt during a build here cannot change what is linked.
# A checkout that is not the pinned release leaves Sources/GGLib unlike the
# release, which check_gglib_take.sh refuses: take the release again before
# committing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/Package.swift"
VENDORED="$ROOT/Sources/GGLib"
SWIFT_FILES=(gglib_ffi.swift GglibFFI.h module.modulemap)
usage="usage: pin_gglib.sh <version> | pin_gglib.sh --local <gglib checkout>"

fail() {
    echo "pin_gglib: $*" >&2
    exit 1
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# Makes a directory beside <path>, named in STAGE, so that what is made in it
# goes to <path> by a rename, which a full disk or an interrupt cannot leave
# half done. finish() removes whatever is left of it.
STAGES=()
staging() {
    STAGE=$(mktemp -d "$(dirname "$1")/.$(basename "$1").XXXXXX")
    chmod 755 "$STAGE"
    STAGES+=("$STAGE")
}

# Puts the staged directory <from> in the place of <path>.
swap_in() {
    rm -rf "$2"
    mv "$1" "$2"
}

# Stages Sources/GGLib, in STAGE, as exactly the files named from one directory.
stage_vendored() {
    local from=$1
    shift
    staging "$VENDORED"
    for file in "$@"; do
        cp "$from/$file" "$STAGE/$file"
    done
}

finish() {
    rm -rf "$WORK" ${STAGES[@]+"${STAGES[@]}"}
}
WORK=$(mktemp -d)
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "${1:-}" = --local ]; then
    [ $# -eq 2 ] || fail "$usage"
    CHECKOUT="$(cd "$2" 2>/dev/null && pwd)" || fail "$2 is not a directory"
    PIN="$("$CHECKOUT/scripts/llama_pin.sh")"
    APPLE="$CHECKOUT/target/apple"
    FRAMEWORK="$APPLE/GglibFFI.xcframework"
    LLAMA_DIR="$APPLE/llama-$PIN"
    SWIFT="$APPLE/swift"
    [ -d "$FRAMEWORK" ] || fail "$FRAMEWORK is missing: run \`make ffi-xcframework\` in $CHECKOUT"
    [ -d "$LLAMA_DIR/llama.xcframework" ] || fail "$LLAMA_DIR/llama.xcframework is missing: run \`make phone-llama\` in $CHECKOUT"
    [ "$(cat "$LLAMA_DIR/pin.txt" 2>/dev/null)" = "$PIN" ] \
        || fail "$LLAMA_DIR/pin.txt does not name the pin, $PIN: that llama.xcframework is another llama.cpp"
    for file in "${SWIFT_FILES[@]}"; do
        [ -f "$SWIFT/$file" ] || fail "$SWIFT/$file is missing: the framework's build writes the Swift beside it"
    done

    # What build_info() reports, read as gglib's scripts/apple/package-release.sh
    # reads it: gglib-ffi takes the workspace's version, and uniffi's is the
    # one Cargo.lock resolved.
    GGLIB_VERSION=$(awk '
        /^\[/ { section = $0 }
        section == "[workspace.package]" && /^version = / { gsub(/"/, "", $3); print $3 }
    ' "$CHECKOUT/Cargo.toml")
    UNIFFI=$(awk '
        /^\[\[package\]\]/ { name = "" }
        /^name = / { name = $3 }
        /^version = / && name == "\"uniffi\"" { gsub(/"/, "", $3); print $3 }
    ' "$CHECKOUT/Cargo.lock")
    [ -n "$GGLIB_VERSION" ] || fail "$CHECKOUT/Cargo.toml names no [workspace.package] version"
    [ -n "$UNIFFI" ] || fail "$CHECKOUT/Cargo.lock names no uniffi version"

    cp "${SWIFT_FILES[@]/#/$SWIFT/}" "$WORK/"
    jq -n --arg gglib "$GGLIB_VERSION" --arg uniffi "$UNIFFI" --arg pin "$PIN" \
        '{gglib_version: $gglib, uniffi_version: $uniffi, llama_pin: $pin}' >"$WORK/binding.json"

    mkdir -p "$ROOT/build"
    # -R copies a symlink as a link: the macOS slices are versioned bundles
    # whose top-level entries are links, and a bundle with copies in their
    # place is one macOS does not load.
    staging "$ROOT/build/GglibFFI.xcframework"
    gglib=$STAGE
    cp -R "$FRAMEWORK/." "$gglib"
    staging "$ROOT/build/llama.xcframework"
    llama=$STAGE
    cp -R "$LLAMA_DIR/llama.xcframework/." "$llama"
    stage_vendored "$WORK" "${SWIFT_FILES[@]}" binding.json
    swift=$STAGE
    swap_in "$gglib" "$ROOT/build/GglibFFI.xcframework"
    swap_in "$llama" "$ROOT/build/llama.xcframework"
    swap_in "$swift" "$VENDORED"

    echo "pin_gglib: build/ holds $CHECKOUT's frameworks (gglib $GGLIB_VERSION, llama.cpp $PIN), and Sources/GGLib its Swift"
    echo "pin_gglib: build with GGLIB_FFI_LOCAL_XCFRAMEWORK=1; Package.swift still pins its release"
    exit 0
fi

[ $# -eq 1 ] || fail "$usage"
VERSION=$1
# The version becomes part of a URL and three file names.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || fail "'$VERSION' is not a version (X.Y.Z, or X.Y.Z-suffix)"

RELEASE="https://github.com/mmogr/gglib/releases/download/v$VERSION"
FRAMEWORK_ZIP="GglibFFI-$VERSION.xcframework.zip"
SWIFT_ZIP="GglibFFI-swift-$VERSION.zip"
LLAMA_ZIP="llama-$VERSION.xcframework.zip"

for asset in SHA256SUMS "$FRAMEWORK_ZIP" "$SWIFT_ZIP" "$LLAMA_ZIP"; do
    curl -fsSL --retry 3 -o "$WORK/$asset" "$RELEASE/$asset" || fail "could not download $asset from $RELEASE"
done

# An archive's line in SHA256SUMS, which must be there exactly once and be
# what the downloaded file hashes to.
verified_sum() {
    local lines
    lines=$(awk -v name="$1" '$2 == name { print $1 }' "$WORK/SHA256SUMS")
    [ "$(printf '%s' "$lines" | grep -c .)" -eq 1 ] || fail "SHA256SUMS has no single line for $1"
    [ "$(sha256 "$WORK/$1")" = "$lines" ] || fail "$1 does not hash to its line in SHA256SUMS"
    printf '%s' "$lines"
}
FRAMEWORK_SUM=$(verified_sum "$FRAMEWORK_ZIP")
LLAMA_SUM=$(verified_sum "$LLAMA_ZIP")
verified_sum "$SWIFT_ZIP" >/dev/null

# The contract in gglib-ffi's README, "Release assets": each framework at its
# archive's root and nothing beside it, and the binding's four files.
roots() { unzip -Z1 "$1" | cut -d/ -f1 | LC_ALL=C sort -u | tr '\n' ' '; }
[ "$(roots "$WORK/$FRAMEWORK_ZIP")" = "GglibFFI.xcframework " ] || fail "$FRAMEWORK_ZIP does not hold GglibFFI.xcframework alone"
[ "$(roots "$WORK/$LLAMA_ZIP")" = "llama.xcframework " ] || fail "$LLAMA_ZIP does not hold llama.xcframework alone"
wanted=$(printf '%s\n' "${SWIFT_FILES[@]}" binding.json | LC_ALL=C sort | tr '\n' ' ')
[ "$(unzip -Z1 "$WORK/$SWIFT_ZIP" | LC_ALL=C sort | tr '\n' ' ')" = "$wanted" ] || fail "$SWIFT_ZIP does not hold ${wanted% }"
mkdir "$WORK/swift"
unzip -q "$WORK/$SWIFT_ZIP" -d "$WORK/swift"
said=$(jq -er .gglib_version "$WORK/swift/binding.json") || fail "$SWIFT_ZIP's binding.json names no gglib_version"
[ "$said" = "$VERSION" ] || fail "$SWIFT_ZIP's binding.json says gglib $said, not $VERSION"

# The three pinned lines, each found exactly once before it is rewritten, so
# a sed that matched nothing cannot pass for a pin.
for name in gglibVersion gglibChecksum llamaChecksum; do
    [ "$(grep -cE "^let $name = \"[^\"]*\"\$" "$MANIFEST")" -eq 1 ] || fail "Package.swift does not declare $name on exactly one line"
done
sed -E \
    -e "s/^let gglibVersion = \"[^\"]*\"\$/let gglibVersion = \"$VERSION\"/" \
    -e "s/^let gglibChecksum = \"[^\"]*\"\$/let gglibChecksum = \"$FRAMEWORK_SUM\"/" \
    -e "s/^let llamaChecksum = \"[^\"]*\"\$/let llamaChecksum = \"$LLAMA_SUM\"/" \
    "$MANIFEST" >"$WORK/Package.swift"
if cmp -s "$MANIFEST" "$WORK/Package.swift"; then
    fail "Package.swift already pins gglib $VERSION at these checksums; nothing was taken"
fi
# The manifest goes in last, by rename, so a take that stops short leaves it
# pinning the release it pinned, which check_gglib_take.sh holds the vendored
# Swift to.
stage_vendored "$WORK/swift" "${SWIFT_FILES[@]}" binding.json
swift=$STAGE
staging "$MANIFEST"
manifest=$STAGE
cp "$WORK/Package.swift" "$manifest/Package.swift"
swap_in "$swift" "$VENDORED"
mv "$manifest/Package.swift" "$MANIFEST"

echo "pin_gglib: Package.swift pins gglib $VERSION:"
echo "  $FRAMEWORK_ZIP $FRAMEWORK_SUM"
echo "  $LLAMA_ZIP $LLAMA_SUM"
echo "pin_gglib: Sources/GGLib is $SWIFT_ZIP; commit both together"
