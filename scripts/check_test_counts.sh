#!/usr/bin/env bash
# Floors under the things a deletion makes smaller. Nothing else in CI
# notices a test that disappears: the suite passes with fewer cases, the
# xcresult reports fewer, and the badge simply reads a smaller total. A
# README claim whose marker is removed stops being checked by
# check_readme_claims.sh, which only looks at markers that are still there.
#
# These are floors, not ratchets. Adding a test needs no edit here -- except
# when the new tests are the whole of a change's guard, in which case leaving
# the floor where it was means every guard the change contributes can be
# deleted and no gate notices. Raise it past them in the same commit.
# Removing a test needs an edit here as well, in the commit that removes it,
# where it can be argued for.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

# Test methods under a directory. XCTest requires the `test` prefix, so this
# counts what the runner would actually run.
test_cases() {
    # grep exits 1 on no match, which under pipefail would take the whole
    # pipeline down; a directory that has lost every test should be reported
    # as zero and fail the floor, not abort the script before the message.
    { grep -rhoE '\bfunc +test[A-Za-z0-9_]*\(' "$@" --include='*.swift' 2>/dev/null || true; } | wc -l | tr -d ' '
}

floor() {
    local what="$1" have="$2" want="$3"
    if [ "$have" -lt "$want" ]; then
        echo "counts: $what fell to $have, the floor is $want" >&2
        echo "counts: if the deletion is deliberate, lower the floor in $(basename "${BASH_SOURCE[0]}") in the same commit" >&2
        status=1
    else
        echo "counts: $what $have (floor $want)"
    fi
}

markers=$({ grep -coE '<!-- test: [A-Za-z0-9_.]+ -->' "$ROOT/README.md" 2>/dev/null || true; })

# 248 -> 243 when the key file's name and its healing moved into the binding
# (modelpipe-ffi 0.4.0): six cases went down with them, and the status a
# pairing refusal now carries brought one back. What is left here is what this
# side still owes, which is the directory. The claims are not weaker, they are
# made one layer down, against the code that does the work.
#
# 243 -> 246 for the three guards that hold this change's silent failures to
# account: the key file's name, the discard-and-retry that heals one this
# device cannot use, and the name of the directory they all live in. Each is a
# whole guard of its own, so the floor moves past them -- left where it was,
# any of the three could be deleted and no gate would notice, while a rename
# on either side of the boundary orphans every paired device in silence.
#
# 2026-09-23: 246 -> 255, 22 -> 23 and 166 -> 171 for the system prompt. A
# prompt that stops being sent fails nothing else: the request still goes out,
# the reply still streams, and it reads a little less like what was asked for.
# These tests are the whole of its guard -- that it goes ahead of send,
# Continue and Retry but is never kept as a message, that blank sends none,
# that it survives a relaunch, and that the sheet keeps what was saved -- so
# the floors move past every one of them, the README's markers included.
floor "package test cases" "$(test_cases "$ROOT/Tests")" 255
floor "XCUITest cases" "$(test_cases "$ROOT/App/ggchatUITests")" 23
floor "README test markers" "${markers:-0}" 171

exit $status
