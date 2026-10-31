#!/usr/bin/env bash
# Module boundaries. Each rule is a sentence the architecture promises:
#
#   1. GGChatCore, GGChatPipe and GGChatLocal import no UI framework. Core so
#      it builds and tests from the command line and could compile on Linux;
#      Pipe and Local because what they put behind the seams is `Sendable` and
#      has no business drawing.
#   2. Only Secrets.swift talks to the Keychain.
#   3. Only GGChatPipe imports modelpipe, and nothing imports iroh or a Rust
#      module directly. The binding is one target's business: everything above
#      the seam speaks `PipeConnector` and knows nothing about the transport.
#      No Rust source or Cargo manifest sits in Sources, App, Tests or scripts.
#      Likewise only GGChatLocal imports gglib's binding, `GGLib`, and only the
#      binding imports the framework's own module, `GglibFFI`; nothing imports
#      llama.cpp's, which is there for GglibFFI to load.
#   4. The app target holds one Swift file, `ggchatApp.swift`. Everything
#      else lives in the package.
#   5. Core tests do not import SwiftUI either.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib/scan.sh
. "$ROOT/scripts/lib/scan.sh"
status=0
fail() { echo "boundary: $*" >&2; status=1; }

for module in GGChatCore GGChatPipe GGChatLocal; do
    hits=$(scan -rnE '^\s*@?[A-Za-z_]*\s*import (SwiftUI|UIKit|AppKit|SwiftData|Combine|VisionKit|CoreData)\b' \
        "$ROOT/Sources/$module")
    [ -z "$hits" ] || fail "$module imports a UI framework:"$'\n'"$hits"
done

found=$(scan -rlE '^\s*import Security\b|SecItem(Add|Copy|Update|Delete)' "$ROOT/Sources")
hits=$(printf '%s\n' "$found" | grep -v '^$' | grep -v 'GGChatCore/Secrets.swift' || true)
[ -z "$hits" ] || fail "only Secrets.swift may touch the Keychain:"$'\n'"$hits"

# `iroh` and the low-level `modelpipe_ffiFFI` are banned outright; the
# `Modelpipe` product is allowed in the one target and the one test target that
# exist to wrap it. The word boundary matters: without it `modelpipe` matches
# the start of `modelpipe_ffiFFI`, so the two rules could not be told apart.
#
# The attribute prefix matters more. The old pattern anchored on `^\s*import`,
# which `@preconcurrency import Modelpipe` walks straight past -- so the rule
# could be disabled anywhere by writing an attribute in front of it, silently
# and while still reading like a rule.
imports=$(scan -rniE '^\s*(@[A-Za-z_]+([(][^)]*[)])?\s+)*import (iroh|modelpipe|modelpipeffi|modelpipe_ffiFFI)\b' \
    "$ROOT/Sources" "$ROOT/App" "$ROOT/Tests")
if stray=$(printf '%s' "$imports" | grep -v '^$' \
    | grep -viE '^[^:]*/(Sources/GGChatPipe|Tests/GGChatPipeTests)/[^:]*:[0-9]+:\s*import Modelpipe\s*$'); then
    fail "only GGChatPipe may import Modelpipe, and nothing may import iroh:"$'\n'"$stray"
fi
# gglib's binding is GGChatLocal's alone, as modelpipe's is GGChatPipe's: the
# generated Swift in GGLib imports the framework's module, GGChatLocal and its
# tests import GGLib, and nothing else imports either. `llama` is banned
# outright. The same attribute-proof pattern as above, and the same refusal of
# an attribute on an allowed line.
imports=$(scan -rniE '^\s*(@[A-Za-z_]+([(][^)]*[)])?\s+)*import (GGLib|GglibFFI|llama)\b' \
    "$ROOT/Sources" "$ROOT/App" "$ROOT/Tests")
if stray=$(printf '%s' "$imports" | grep -v '^$' \
    | grep -viE '^[^:]*/(Sources/GGChatLocal|Sources/GGLib|Tests/GGChatLocalTests)/[^:]*:[0-9]+:\s*import (GGLib|GglibFFI)\s*$'); then
    fail "only GGChatLocal may import gglib's binding, and nothing may import llama:"$'\n'"$stray"
fi
# Rust anywhere this repo keeps code, tests or tooling. Only the directories
# that exist are handed to find, and what it prints is captured rather than
# piped into `grep -q`: under pipefail a missing directory made find exit
# non-zero, so the pipeline failed -- and the check passed -- even when grep
# had matched. find exits 0 when nothing matches, so with no `|| true` it
# stops the gate only on a folder it cannot read.
rust_dirs=()
for dir in Sources App Tests scripts; do
    if [ -d "$ROOT/$dir" ]; then rust_dirs+=("$ROOT/$dir"); fi
done
if [ ${#rust_dirs[@]} -gt 0 ]; then
    rust=$(find "${rust_dirs[@]}" \( -name '*.rs' -o -name 'Cargo.toml' \))
    [ -z "$rust" ] || fail "no Rust in this repo:"$'\n'"$rust"
fi

if [ -d "$ROOT/App/ggchat" ]; then
    extra=$(find "$ROOT/App/ggchat" -name '*.swift' ! -name 'ggchatApp.swift')
    [ -z "$extra" ] || fail "the app target holds Swift beyond ggchatApp.swift:"$'\n'"$extra"
fi

hits=$(scan -rnE '^\s*import (SwiftUI|UIKit|AppKit)\b' "$ROOT/Tests")
[ -z "$hits" ] || fail "Core tests import a UI framework:"$'\n'"$hits"

[ $status -eq 0 ] && echo "boundaries: ok"
exit $status
