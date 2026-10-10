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
#
# 2026-09-29: 335 -> 337. Two tests pin that a message keeps its run's id and
# cursor, and that a store opens across that change in both directions.
#
# 2026-09-29: 337 -> 350. Thirteen tests pin that a reply to gglib is a run:
# the fallback asked once, the background walking away where Stop cancels, no
# Continue or Retry while the hub writes, reading on after every cut to the
# same text, a drop in front read on, and each way a run can end.
#
# 2026-09-29: 235 -> 257. The README claim for runs names all twenty-two of
# their tests.
#
# 2026-09-29: 350 -> 358. Eight tests pin that a reply still being written
# always has a way out (a refusal, Stop, removing the provider), that reading
# on after a drop is paced and bounded, that a lost start is sent again under
# its id, that a return reads on with no pipe, and that no log line names a run.
#
# 2026-09-29: 257 -> 265. The runs claim names the eight tests of its way out.
#
# 2026-09-29: 358 -> 359 and 265 -> 266. One test pins that a loop-guard trip
# is read under the key gglib sends now and the one an older hub sent.
#
# 2026-09-29: 359 -> 361. Two tests pin that a conversation's unread mark is
# kept in the store and that a store opens across that change both ways.
#
# 2026-09-29: 361 -> 366 and 266 -> 273. Five tests pin the list's marks: a
# reply still being written, one unread until opened, one that ends on screen
# never unread, an order the marks leave alone, and a word and label for each.
# They and the two store tests are the whole of that guard, and the README
# claim names all seven.
#
# 2026-09-29: 366 -> 367 and 273 -> 274. One test pins that a run's report
# that cannot be read is a refusal and not a drop.
#
# 2026-09-29: 367 -> 371 and 274 -> 278. Four tests pin that selecting is not
# reading: a launch keeps every mark, a reply read on at launch in the
# restored conversation is unread, one that ends with no chat shown is
# unread, and one the person stopped never is.
#
# 2026-09-29: 371 -> 372 and 278 -> 279. One test pins that a chat opened
# after going Back is read whatever iOS 27 tells the view after its appear.
#
# 2026-09-30: 372 -> 376. Four tests replay the hub's chat bodies gglib
# records, a missing optional and an unknown key included.
#
# 2026-09-30: 376 -> 383. Seven tests pin the hub chats client: where it asks
# and with what key, and that device_not_named, a 404, another 4xx, a body it
# cannot read, a page that is not JSON, a 5xx and no answer each mean what
# they should.
#
# 2026-09-30: 383 -> 390. Seven tests pin a paired Mac's chats in the list:
# listed when its pipe comes up and on a pull, only for a pipe, opened read
# only with nothing written to the store, dropped by Back, a Mac that does
# not share its chats saying so, and the launch's quiet dial raising no alert.
#
# 2026-09-30: 390 -> 396. Six tests pin what an unreachable Mac's section
# shows: the titles its list last saw and when, kept after every list and
# through a relaunch, gone with the provider; that opening one then says the
# Mac is unreachable, also after a dial that fails; and that a store opens
# across the two new columns both ways.
#
# 2026-09-30: 396 -> 397 and 279 -> 304. One test pins that a launch lists
# each paired Mac's chats; the claim for a paired Mac's chats names all
# twenty-five of their tests.
#
# 2026-09-30: 397 -> 398 and 304 -> 305. One test pins that a hub row whose
# metadata cannot be read keeps its row and loses only the metadata.
#
# 2026-09-30: 398 -> 404 and 305 -> 311. Six tests pin what a Mac's section
# does when a list fails (it keeps what it saw and says when), that a pull
# lists through a pipe already up, that an older gglib has no section, that a
# lost ticket says to pair again, that the background stops a refresh, and
# that a chat on screen keeps its rows while it is read again.
#
# 2026-09-30: 404 -> 411. Seven tests pin a turn on a Mac's chat: its body is
# the recorded one with only its two keys, put as an agent run with the key;
# no_model, conflict and conversation_not_found each have their own refusal,
# and every other answer means what it should; the run's events are read as
# text, reasoning and tool lines; and Stop is the run's cancel.
#
# 2026-09-30: 411 -> 416. Five tests pin carrying a Mac's chat on: a send puts
# only the new text and the reply is read from the run, then replaced by the
# Mac's rows with nothing written to the store; Stop cancels and reads the rows
# once the run ends; each refusal is said in its own words; a second send while
# the Mac writes is refused here; and a failed run says so.
#
# 2026-09-30: 416 -> 424. Eight tests pin walking away from a Mac's reply:
# leaving the chat and the background cancel nothing, and a return reads on
# from the cursor with nothing applied twice; a reading that gets nothing is
# paced; a run the Mac no longer has, or a removed provider, is forgotten; a
# launch reads a kept run from its start, and a list that no longer names it
# forgets it; and a store opens across the new column both ways.
#
# 2026-09-30: 424 -> 425. One test pins that a Mac's chat says Writing while
# this phone holds a reply the Mac is writing to it, out of reach included.
#
# 2026-09-30: 311 -> 332. The claim for carrying a Mac's chat on names all
# 21 of its tests.
#
# 2026-09-30: 425 -> 430 and 332 -> 337. Five tests pin a lost turn kept and
# put again under its id, a list forgetting one that never arrived and keeping
# one that did, a gglib that takes a turn as a chat run, and nothing read on
# beside a Stop whose cancel is not answered yet; the claim names all five.
#
# 2026-09-30: 430 -> 433 and 337 -> 340. A list no longer ends a lost turn it
# does not name, since the Mac names a run only once reserved; three tests pin
# a lost turn put again after its run ended, the text given back by a send to
# a Mac out of reach, and an accepted send clearing it.
#
# 2026-10-01: 433 -> 448 and 340 -> 355. Four tests pin the time on a Mac's
# chat row and the hub's time read as UTC; eleven pin a lost send sent again
# when a list does not name it, on coming back, on the pipe coming up and when
# leaving its chat cut it short, and never beside itself, out of reach, on the
# way away, after Stop, after a refusal, or once started, with a refused one's
# text given back on opening; the claims name all fifteen.
#
# 2026-10-01: 448 -> 446 and 355 -> 354. Settings no longer shows the readings
# both ADRs struck, and nothing counts them (issue 89). Two tests pinned only
# that counting -- every background counted as a close, and a pipe going away
# mid-reply counted as a mid-reply close -- and go with their two markers.
# The tests that also pinned a pill, a reconnect, a partial or a retry keep
# those asserts and lose only the counts. The gallery's Settings test, the one
# check of what Settings shows, gains the marker it never had.
#
# 2026-10-02: 446 -> 453 and 354 -> 362. Seven tests pin the day this build
# stops opening: read from the list inside a profile's envelope, none for a
# blob with no list, a list with no date or a bundle with no profile, the
# file found under its name, and Settings' line, said where the person is and
# absent with no date. They are the whole of that guard; the claim names them
# and the gallery's Settings test, which finds no such line in the simulator.
#
# 2026-10-02: 453 -> 456 and 362 -> 367. Three tests pin that a Keychain
# that will not read a pipe's ticket or token is said as its own reason, in
# the alert, on a waiting question and in a quiet dial's log line, and never
# as missing (issue 85). They are the whole of that guard; the claim names
# them, the missing case and the read the Keychain refuses.
#
# 2026-10-02: 456 -> 457 and 367 -> 369. A return to the foreground dials
# every pipe at once (issue 85). The test that a hang-up stopped the resume
# before its next dial goes, since there is no next dial: one test pins both
# dials out before either lands, and one that a hang-up arriving before the
# dials go out calls every one of them off. The claim names both.
#
# 2026-10-02: 457 -> 460 and 369 -> 372. Three tests pin that a save marks
# only what changed (issue 139): an unchanged conversation marks no row, one
# change marks only its row, and a failure is encoded again only when it
# changed. Nothing else notices a save that marks every row, so they are the
# whole of that guard, and the claim names all three.
#
# 2026-10-02: 460 -> 469 and 372 -> 381. Nine tests pin that a markdown
# table is drawn as one (issue 87): its header, alignments and rows, a cell
# per column, a cell's inline styling, a caret cell kept, a table under a
# paragraph line, text that is not a table kept as a paragraph, the table
# view chosen for it, and what VoiceOver reads. They are the whole of that
# guard, and the README claim names all nine.
#
# 2026-10-02: 469 -> 480 and 381 -> 392. Eleven tests pin that a streaming
# reply is parsed again only after its settled blocks (issue 82): every
# prefix of written and random replies against a whole parse, a fence and a
# table still open, a later definition, text that starts again, which block
# boundary is clean, which `]:` may be a definition, and the work per token
# in the core and in both rows. A parse of the whole reply per token passes
# everything else, so they are the whole of that guard, and the README
# claim names all eleven.
#
# 2026-10-02: 480 -> 483 and 392 -> 395. Three tests pin that a line break
# inside a paragraph reads as a space and a hard break as a newline: in plain
# text, beside code, emphasis and a link, and in a heading, a list item and a
# quote. Each failed against the rendering that dropped a break, and nothing
# else did, so they are the whole of that guard, and the README claim names
# all three.
#
# 2026-10-02: 483 -> 484 and 395 -> 396. One test pins that punctuation
# reads as typed, `---` not turned into an em dash. It is the only test that
# fails when smart punctuation is on, and the README claim names it.
#
# 2026-10-02: 484 -> 485 and 396 -> 397. One test reads every line the app
# writes as a pipe is dialled, refused, dropped and paired, and finds no
# ticket, token or code in any (issue 70). Nothing else reads those lines, so
# it is the whole of that guard, and the claim names it.
#
# 2026-10-02: 23 -> 24 and 397 -> 398. The live walks paste their key, since
# XCUITest writes typed text into its output and the result bundle (issue
# 120). One test pastes a key that is not one into the form and finds the
# field holding it and the pasteboard empty. It is the whole of that guard,
# and the claim names it.
#
# 2026-10-04: 485 -> 501 and 398 -> 414. Sixteen tests pin a message's
# images: the id and the shape gglib names a stored image by, its token
# estimate, which model the list says reads images, the wire (a turn with
# none the same bytes as before, text then each image in order, no empty
# text part, no turn sent without its bytes), the bytes read once per image
# for a send, Retry and a run's PUT sent again, and both ways a model that
# cannot see refuses, with each image code's line. They are the whole of
# that guard, and the README claim names all sixteen.
#
# 2026-10-04: 501 -> 517, 24 -> 25 and 414 -> 431. Seventeen more pin the
# images from this side: the one downscale (upright, the 2560-pixel edge,
# no metadata, PNG or JPEG, the 8 MiB refusal, the id of the bytes sent),
# which model can see and the local refusal that keeps the draft, a turn of
# images alone, a turn refused keeping its images for Retry, the strip's
# estimate, the title of an image-only turn, the bytes kept beside the store,
# deleted with the last turn naming them and gone after a reset, and a paste
# walked on a simulator. They are the whole of that guard, and the second
# README claim names all seventeen.
#
# 2026-10-04: 517 -> 521 and 431 -> 435. Four more pin the draft: an image
# added for a model that cannot see is refused as it is added, a draft
# refused partway takes back the images it kept, a refused draft keeps its
# text and images while a taken one is empty, and the same image added twice
# is one. The second README claim names them too.
#
# 2026-10-04: 521 -> 543 and 435 -> 457. Twenty-two tests pin a turn to a
# Mac's chat with images: the recorded image turn and upload, the upload and
# the fetch on the wire, the fetch kept out of a URL cache that keeps
# everything else, each image refusal, every image sent before the turn names
# it, a turn of images alone, an image the Mac let go sent again under the
# same run id, once only, a text turn refused for an image not sent any, a
# lost turn put again without sending them twice, the text and images given
# back, a Mac too old for images, the local refusal for a model that cannot
# see, a row of images alone, and the Mac's images held in memory once, never
# stored, and dropped with the chat. They are the whole of that guard, and
# the README claim names all twenty-two.
#
# 2026-10-05: 543 -> 570, 25 -> 26 and 457 -> 485. Twenty-eight tests pin the
# context ring: gglib's worked examples replayed through each way a reading
# arrives, and which saved reply decides; that a reading needs both counts
# and a size and is never estimated; the percent, its levels, the figure from
# 70 and the mark from 90, the sheet's sentences, the locale's digits and what
# VoiceOver hears; gglib's keys on the wire, in a run's usage frame, an agent
# run's `turn_usage` and a saved row; the mock's counts; a finished reply
# keeping its reading on both routes, a stopped or failed one leaving it,
# another model hiding it, a reply read on, a reply cut off; the column,
# written only when changed and opened across in both directions; a Mac's
# chat reading its rows, a reply in hand replacing them, no ring over a chat
# the Mac stops sending, and nothing of it written to the phone; and the ring
# and its sheet walked on a simulator. They are the whole of that guard, and
# the two README claims name all twenty-eight.
#
# 2026-10-05: 570 -> 599, 26 -> 27 and 485 -> 515. Thirty tests pin the
# Thinking switch: gglib's `reasoning` capability; a budget of zero on the
# wire and the body unchanged without it; the budget on a send, Continue,
# Retry and a run's `PUT` sent again, to gglib alone and not for a model
# listed as not thinking; the choice kept across a relaunch, cleared by a
# model that does not think, in a column opened across in both directions;
# where the switch is offered, its symbol and spoken value, and that it shows
# on unless off and a press sets what it shows, in both kinds of chat; the
# mock skipping its reasoning; gglib's recorded `thinking_turn` and the
# settings an opened chat carries; a Mac's chat opening as the Mac remembers,
# saying the choice once as `off` or `default`, following the Mac again once
# the Mac has taken a choice set here, a turn put again and a refused turn,
# nothing of it written to the phone; the chat's model looked up in the Mac's
# list, a reply that names none not hiding the one before it, the list read
# on opening, quietly, and again when the pipe comes up; and the switch walked
# on a simulator. They are the whole of that guard, and the two README claims
# name all thirty.
#
# 2026-10-10: 599 -> 609 and 515 -> 524. Ten tests pin the branching rules
# (ADR 0010): gglib's recorded cases replayed, every change's plan or refusal
# and every family's branch points, and that there are cases to replay; the
# line an option is shown by, cut at 80 characters, ended at either line
# ending, for images alone and for a reply; a reply saved as it was; a tie in
# time; and the rules over this device's own ids and times. They are the
# whole of that guard, and the README claim names nine of them.
#
# 2026-10-10: 609 -> 621 and 524 -> 536. Twelve tests pin a local branch:
# an answered question's edit, a regenerate and an edited reply each on a
# new branch, answered or not as gglib's rules say, and the original left as
# it was, its options oldest first; Branch from here sending nothing; an
# unanswered question edited in place, as a new message, but on a branch
# while its reply streams; a reply saved as it was, refused; a refused
# regenerate; a copy's settings, origin and no run; a branch of a branch in
# the first family; and the lineage through the store. The README claim
# names all twelve.
#
# 2026-10-10: 621 -> 625, 27 -> 28 and 536 -> 541. Five tests pin the
# branch screens: the switcher's position, said and shown, and how it lists
# an option; what each item of a turn's menu does; when the editor can save;
# and a reply edited from its menu walked on a simulator, opening its branch
# with the switcher and going back by Previous. The README claim names all
# five.
#
# 2026-10-10: 625 -> 643 and 541 -> 559. Eighteen tests pin a Mac's chat's
# branches: an edit that opens the Mac's branch and answers it, keeping
# nothing here; Branch from here answering nothing; a refusal's sentence;
# Answer; the Thinking choice on the answer; a point at a reply that called
# a tool; no question drawn above an answer; nothing sent while busy or out
# of reach; nothing opened for a chat left; a change in place read again;
# an editor across a read; and the branching bodies gglib records, the turn
# a row is in, and gglib's refusals. The README claim names all eighteen.
floor "package test cases" "$(test_cases "$ROOT/Tests")" 643
floor "XCUITest cases" "$(test_cases "$ROOT/App/ggchatUITests")" 28
floor "README test markers" "${markers:-0}" 559

exit $status
