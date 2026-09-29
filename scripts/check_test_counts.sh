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
#
# 2026-09-25: 255 -> 257 and 171 -> 173 for the lookup by key. A save or a
# delete asks for the one row with that key. A lookup that ignored its key and
# took the first row would pass any test that keeps one row of its table, and
# in use it would write an edit onto the wrong row or delete the wrong one. Two
# new tests guard it, one per table: twenty providers, and twenty
# conversations, with one of them edited and then deleted. Each fails when its
# table's save or its delete stops asking by key, and for a delete it is the
# only test that does, so the floor moves past both. The README claim names
# both, so the marker floor moves past both markers.
#
# 2026-09-28: 257 -> 262 and 173 -> 178 for the chunks a reply skips. Five
# new tests check what a reply does with a chunk it cannot read. Run with the
# streaming provider as it was before this change, these five failed and every
# other test passed, so the floor moves past all five. The README claim names
# each of them, so the marker floor moves past all five markers.
#
# 2026-09-28: 262 -> 272 and 178 -> 188 for a long prompt. Ten new tests
# check that only gglib is asked for progress, that its frames are read and
# shown and never kept, and that a chat reply waits ten minutes of silence on
# a session of its own. They are the whole of that guard, so the floor moves
# past all ten. The README claim names each of them, so the marker floor
# moves past all ten markers.
#
# 2026-09-28: 272 -> 292 and 188 -> 208. Twenty tests pin where the
# conversation store is kept, how an earlier build's store moves in, what the
# app does when it cannot keep one, and the words of its notice. The README
# claim names each of them, so both floors move past all twenty.
#
# 2026-09-29: 292 -> 309 and 208 -> 225 for when a machine was last heard.
# Seventeen new tests pin what counts as hearing it, that the time is kept in
# the store, when the line under the pill names a machine that has stopped
# answering, and the two sentences that no longer blame only this device.
# They are the whole of that guard, and the README claim names each of them.
#
# 2026-09-29: 309 -> 319 and 225 -> 235. Ten new tests pin that a send
# through a pipe that is not connected waits for it and how the wait ends, and
# that removing a provider puts down the reply through it first. They are the
# whole of that guard, and the README claim names each of them.
#
# 2026-09-29: 319 -> 335. Seven tests pin the runs client: the PUT and its
# fallback, frames numbered by seq, a stream cut at every byte read on from its
# cursor, not_found, cancel, and no run id in a log line; the floor also moves
# past the run wire replays that came before them.
floor "package test cases" "$(test_cases "$ROOT/Tests")" 335
floor "XCUITest cases" "$(test_cases "$ROOT/App/ggchatUITests")" 23
floor "README test markers" "${markers:-0}" 235

exit $status
