#!/usr/bin/env bash
# Prints a directory to put in CPATH for a DocC build, holding a module map
# that names GglibFFI by the vendored header alone.
#
# SwiftPM's native build system, the default before Swift 6.4, extracts each
# target's symbols with swift-symbolgraph-extract, and it hands that tool a
# binary target's slice with -I where a framework needs -F. ModelpipeFFI is
# a static library whose slice holds its module map, so -I finds it; GglibFFI
# is a framework, so the tool cannot load it, and with it neither
# GGChatLocal nor GGChatUI. The map written here is a plain module over
# Sources/GGLib/GglibFFI.h, which scripts/check_gglib_take.sh holds to the
# release and which is the framework's own header, so the symbols are the
# same. Nothing links against it: it is only read to describe the API.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/.build/docs-gglib-module"
mkdir -p "$DIR"
cat >"$DIR/module.modulemap" <<MAP
module GglibFFI {
    header "$ROOT/Sources/GGLib/GglibFFI.h"
    export *
}
MAP
echo "$DIR"
