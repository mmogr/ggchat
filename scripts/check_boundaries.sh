#!/usr/bin/env bash
# Module boundaries. Each rule is a sentence the architecture promises:
#
#   1. GGChatCore and GGChatPipe import no UI framework. Core so it builds and
#      tests from the command line and could compile on Linux; Pipe because the
#      connector behind the seam is `Sendable` and has no business drawing.
#   2. Only Secrets.swift talks to the Keychain.
#   3. Only GGChatPipe imports modelpipe, and nothing imports iroh or a Rust
#      module directly. The binding is one target's business: everything above
#      the seam speaks `PipeConnector` and knows nothing about the transport.
#   4. The app target holds one Swift file, `ggchatApp.swift`. Everything
#      else lives in the package.
#   5. Core tests do not import SwiftUI either.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
fail() { echo "boundary: $*" >&2; status=1; }

for module in GGChatCore GGChatPipe; do
    if hits=$(grep -rnE '^\s*@?[A-Za-z_]*\s*import (SwiftUI|UIKit|AppKit|SwiftData|Combine|VisionKit|CoreData)\b' \
        "$ROOT/Sources/$module" 2>/dev/null); then
        fail "$module imports a UI framework:"$'\n'"$hits"
    fi
done

if hits=$(grep -rlE '^\s*import Security\b|SecItem(Add|Copy|Update|Delete)' "$ROOT/Sources" 2>/dev/null \
    | grep -v 'GGChatCore/Secrets.swift'); then
    fail "only Secrets.swift may touch the Keychain:"$'\n'"$hits"
fi

# `iroh` and the low-level `modelpipe_ffiFFI` are banned outright; the
# `Modelpipe` product is allowed in the one target and the one test target that
# exist to wrap it. The word boundary matters: without it `modelpipe` matches
# the start of `modelpipe_ffiFFI`, so the two rules could not be told apart.
#
# The attribute prefix matters more. The old pattern anchored on `^\s*import`,
# which `@preconcurrency import Modelpipe` walks straight past -- so the rule
# could be disabled anywhere by writing an attribute in front of it, silently
# and while still reading like a rule.
imports=$(grep -rniE '^\s*(@[A-Za-z_]+([(][^)]*[)])?\s+)*import (iroh|modelpipe|modelpipeffi|modelpipe_ffiFFI)\b' \
    "$ROOT/Sources" "$ROOT/App" "$ROOT/Tests" 2>/dev/null || true)
if stray=$(printf '%s' "$imports" | grep -v '^$' \
    | grep -viE '^[^:]*/(Sources/GGChatPipe|Tests/GGChatPipeTests)/[^:]*:[0-9]+:\s*import Modelpipe\s*$'); then
    fail "only GGChatPipe may import Modelpipe, and nothing may import iroh:"$'\n'"$stray"
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
