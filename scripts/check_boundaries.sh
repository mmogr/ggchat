#!/usr/bin/env bash
# Module boundaries. Each rule is a sentence the architecture promises:
#
#   1. GGChatCore imports no UI framework, so it builds and tests from the
#      command line and could compile on Linux.
#   2. Only Secrets.swift talks to the Keychain.
#   3. Nothing imports iroh, modelpipe or a Rust module. The ffi is a later,
#      separate piece of work behind PipeConnector.
#   4. The app target holds one Swift file, `ggchatApp.swift`. Everything
#      else lives in the package.
#   5. Core tests do not import SwiftUI either.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
fail() { echo "boundary: $*" >&2; status=1; }

if hits=$(grep -rnE '^\s*import (SwiftUI|UIKit|AppKit|SwiftData|Combine|VisionKit|CoreData)\b' \
    "$ROOT/Sources/GGChatCore" 2>/dev/null); then
    fail "GGChatCore imports a UI framework:"$'\n'"$hits"
fi

if hits=$(grep -rlE '^\s*import Security\b|SecItem(Add|Copy|Update|Delete)' "$ROOT/Sources" 2>/dev/null \
    | grep -v 'GGChatCore/Secrets.swift'); then
    fail "only Secrets.swift may touch the Keychain:"$'\n'"$hits"
fi

if hits=$(grep -rniE '^\s*import (iroh|modelpipe|modelpipeffi)' "$ROOT/Sources" "$ROOT/App" "$ROOT/Tests" 2>/dev/null); then
    fail "nothing links iroh or modelpipe yet:"$'\n'"$hits"
fi
if [ -d "$ROOT/Sources" ] && find "$ROOT/Sources" "$ROOT/App" \( -name '*.rs' -o -name 'Cargo.toml' \) 2>/dev/null | grep -q .; then
    fail "no Rust in this repo"
fi

if [ -d "$ROOT/App/ggchat" ]; then
    extra=$(find "$ROOT/App/ggchat" -name '*.swift' ! -name 'ggchatApp.swift' || true)
    [ -z "$extra" ] || fail "the app target holds Swift beyond ggchatApp.swift:"$'\n'"$extra"
fi

if hits=$(grep -rnE '^\s*import (SwiftUI|UIKit|AppKit)\b' "$ROOT/Tests" 2>/dev/null); then
    fail "Core tests import a UI framework:"$'\n'"$hits"
fi

[ $status -eq 0 ] && echo "boundaries: ok"
exit $status
