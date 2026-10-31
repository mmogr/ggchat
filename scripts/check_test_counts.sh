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

markers=$({ cat "$ROOT/README.md" "$ROOT/docs/what-is-true-today.md" "$ROOT/docs/contributing.md" 2>/dev/null | grep -coE '<!-- test: [A-Za-z0-9_.]+ -->' || true; })

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
#
# 2026-10-09: 643 -> 646 and 559 -> 563. Three tests pin the images a tool
# makes on a Mac's reply: gglib's `result.images` read in order and a result
# without them meaning nothing; each tool's images joining the reply in order;
# and the reply drawing them as the Mac's, with words or before any. They are
# the whole of that guard, and the README claim names all three and the run's
# events test that now carries one.
#
# 2026-10-09: 646 -> 650 and 563 -> 567. Four tests pin a tool's saved row:
# its images under the text of the reply that follows, in order across two
# tool rows, and one without images still passed over; a reply that ended
# after its tool drawn as those images alone; a saved reply's images drawn
# under its text and a question's above; and an image a tool made read from
# the Mac by id once, while the reply is written, and not again for its row.
# They are the whole of that guard, and the README claim names all four.
#
# 2026-10-09: 650 -> 652 and 567 -> 569. Two tests replay gglib's recorded
# tool reply: its frames read as the tool's line, its image and its text, and
# its rows put the image on the tool's row alone. They are the only check
# that the shape gglib records is the shape read here, and the README claim
# names both.
#
# 2026-10-10: 652 -> 656 and 569 -> 573. Four tests pin what gglib's drawing
# adds to its list and its refusals: each drawing code's own line and side,
# on a saved failure too; `image_generation` and `embeddings` read as models
# that cannot chat; the model list offering only those that can; and a
# provider with no model chosen taking the first that can. They are the whole
# of that guard, and the README claim names all four.
#
# 2026-10-10: 656 -> 661 and 573 -> 578. Five tests pin how a hub is asked
# whether it can draw: the route's two answers, a 404 read as a hub that
# cannot, and any other failure as the error it is; the ask on catch-up and
# the sentence for each answer; a failed ask keeping the answer before and a
# removed provider taking its own; only gglib asked and offered the switch;
# and a Mac's chat saying its Mac's sentence. They are the whole of that
# guard, and the README claim names all five.
#
# 2026-10-10: 661 -> 666 and 578 -> 583. Five tests pin Draw on a Mac's chat:
# the turn's body with and without `draw`; the word said only with the switch
# on; never to a Mac that cannot draw, is too old or was never heard from;
# the switch off again in the draft a send leaves; and a refused draft and a
# turn put again keeping it. They are the whole of that guard, and the README
# claim names all five.
#
# 2026-10-10: 666 -> 672 and 583 -> 589. Six tests pin a picture's progress:
# gglib's recorded `tool_progress` and `waiting` frames read stage by stage,
# with the call's end ahead of its image; frames that do not read meaning
# nothing; the line for each stage and for each wait; the latest word shown
# until its own tool ends; and a Mac's reply holding it until its run ends.
# They are the whole of that guard, and the README claim names all six.
#
# 2026-10-10: 672 -> 677 and 589 -> 594. Five tests pin the look at a picture
# being drawn: a `preview` read ahead of the numbering, with and without an
# id, moving no cursor; one that does not read passed over; only the latest
# held, gone with its own tool; a Mac's reply showing it with its cursor
# where it was; and a run that ends mid-picture leaving none. They are the
# whole of that guard, and the README claim names all five.
#
# 2026-10-10: 677 -> 694 and 594 -> 611. Seventeen tests pin drawing from a
# conversation kept here: the run's query with its body unchanged, the
# report's `frames` and the decoder it picks, a reply's images kept off the
# wire; the run asked to draw only with the switch on and a hub that can, the
# switch off after a send, the answer picking the decoder, Retry and Continue;
# the picture read once and kept under its id, asked for again when lost,
# named and not kept when the hub lacks it, a reply read on with its decoder,
# a reply of a picture alone; and the two columns kept, and opened across the
# change. They are the whole of that guard, and the README claims name all
# seventeen.
#
# 2026-10-10: 694 -> 695 and 611 -> 612. One test pins a turn a Mac refuses
# by ending its run: the draft given back with Draw as it was and the code's
# own line, and a run that failed otherwise, or after its reply began, ending
# as a reply that stopped. It is the whole of that guard, and the README
# claim names it.
#
# 2026-10-10: 695 -> 699 and 612 -> 616. Four tests pin what is drawn of
# drawing: the switch's symbol, spoken value and what a press does; a Mac's
# reply drawing the work in the spinner's place; the work's bar and latest
# look; and a reply kept here with its tool lines, its spinner and what is
# drawn under it. No UI walk covers the switch in a composer, so they are the
# whole of that guard, and the README claim names all four.
#
# 2026-10-10: 699 -> 703 and 616 -> 620. Four more tests pin drawing from a
# conversation kept here: a question a hub refused to draw for no longer
# asking; a provider moved to another Mac forgetting what was said of
# drawing; a run written a way this build cannot read stopped and given up;
# and its report, and a list holding it, still read. The README claim for a
# kept conversation names all four.
#
# 2026-10-11: 703 -> 704 and 620 -> 621. One test pins a run that draws
# reporting an error of its own before it ends failed: that sentence is what
# the question shows, with no code, and Retry asks for the picture again. It
# is what gglib does when the model never asks for the picture, and the
# README claim for a kept conversation names it.
#
# 2026-10-11: 704 -> 707 and 621 -> 624. Three tests pin drawing a second
# time in one chat: a press of Draw alone being a change to the draft, and a
# conversation kept here and a Mac's chat each taking a second picture with
# its steps and looks. The first fails when a draft's equality stops
# comparing the switch, and is the whole of that guard; the README claim
# names all three.
#
# 2026-10-11: 707 -> 713 and 624 -> 630. Six tests pin the image models a
# hub lists and the choice a message that draws carries: the contract's
# answer read in order; an answer with no list reading as an older gglib and
# an empty list not; a family or a role this build does not know; the
# question naming a model to be judged; and `image_model` in a turn's body
# and in a run's query, only when it draws. The fixture is written from the
# contract, gglib having recorded none. They are the whole of that guard,
# and the README claim names all six.
#
# 2026-10-11: 713 -> 728 and 630 -> 645. Fifteen tests pin a chat's choice
# of image model: the menu's rows and when there is one, and what the
# control says; a Mac from before the list given no menu and never sent the
# word, from either kind of chat; the choice said with each message that
# draws and no other, kept with a conversation and held only with a Mac's
# chat open; a model without its files not chosen; a moved provider
# forgetting it; the column kept, and opened across the change; and a stale
# choice said and never swapped, a refused run or turn keeping its question
# and its choice, and the Mac asked about the model chosen. They are the
# whole of that guard, and the README claims name all fifteen.
#
# 2026-10-11: 728 -> 741 and 645 -> 658. Thirteen tests pin a conversation
# kept here remembering how its picture was made: the recorded frames of a
# picture read as its call and its answer; the request after it carrying
# the call, the answer and then the words, as gglib's rule for a drawn
# picture reads them; another server, and a reply from before, sent the
# words alone; two pictures under their own ids; a call nothing answered
# left out; a branch keeping the calls and the rows unchanged; an answer
# read on a later reading finding its call; and the column kept, and opened
# across the change. A reply that stops carrying its calls fails nothing
# else: the request still goes and the model says it cannot draw. They are
# the whole of that guard, and the README claim names all thirteen.
#
# 2026-10-12: 741 -> 744 and 658 -> 661. Three tests pin the Draw control
# asking which image model where a Mac has several and no default: when a
# hub waits for a choice, the menu without its "Default" row and what the
# control then says, and a Mac's chat waiting, then naming the model that
# draws. They are the whole of that guard, and the README claim names all
# three.
#
# 2026-10-12: 744 -> 781 and 661 -> 698. Thirty-seven tests pin a drawn picture
# fixed or drawn again: where a pointer lands in the picture and which
# strokes paint; the request's body for a fix and a redo; the stream read to
# its picture, its error or its empty end, and each stage's sentence; the
# keep route; which pictures the drawing tool made, in a Mac's rows and in a
# reply kept here; the mask, its size, its opaque black, its strokes from the
# top left, a rub-out and a dot, and the box the picture is fitted to; what
# must be chosen first, what a fix and a redo send, a render followed, failed,
# stopped, left and replaced, and that nothing is kept before Keep; Keep on a
# Mac's chat and on a conversation kept here, a failed Keep keeping the
# picture, a failed read after it, the image model the editor starts at or
# asks for on a Mac with no default, and
# where the button is offered; a reader that leaves closing the request; the
# Mac looked up when asked, a pipe hung up and dialled again, the mask the
# size of the bytes held since opening, and the editor outliving its row. No
# UI walk reaches the editor, so they are the whole of that guard, and the
# README claims name all thirty-seven.
#
# 781 -> 785 for the quick actions on the app's icon: which are offered, the
# provider each starts with, the note a started chat's composer reads once,
# and a picture left open closed. The press on the icon and the camera
# opening are seen only on a phone, so these four are the whole of what a
# gate holds of it.
#
# 785 -> 790 for a picture opened whole: how far it is enlarged, where it
# sits, what a double tap shows, and the bytes it offers to share or save
# from a Mac's chat and from this device's store. The pinch itself and the
# save to Photos are seen only on a phone, so these five are the whole of
# what a gate holds of it.
#
# 2026-10-21: 790 -> 799 and 698 -> 708, to the counts the suite and the
# README had reached, and past the one test and marker that read a Z-Image
# model's family as gglib names it. Nothing else shows that label, so the
# test is the whole of its guard.
#
# 799 -> 801 and 708 -> 710 for a status probe that fails: it keeps nothing
# and the next one asks, while a 404 is kept and not asked again. A probe
# that kept its failure would hide a gglib's Thinking switch for the rest of
# the run and fail nothing else, so these two are the whole of that guard, and
# the README claim names both.
#
# 801 -> 807 and 710 -> 717, to the counts after it, for the
# provider a conversation is with (#86): a new chat with the open one's
# provider, the first when that provider is gone, a Mac's chat's provider,
# a model choice that leaves the provider's default alone, a move to another
# provider resetting what was chosen for the one left, and no move while a
# reply streams or a hub writes it. No UI walk changes a provider, so these
# are the whole of that guard, and the README claim names all seven.
#
# 807 -> 818 and 717 -> 728 for the drawn picture shown to a model that reads
# images: the parts and their order, the newest picture only, the same
# message on every later request, a newer picture moving it, none where
# nothing drew, none from a reply where another tool answered too (two),
# none for a model without `vision`, none for a server not known to be
# gglib, and none when its bytes are gone. A picture left out sends the chat
# that worked before, so nothing else fails when it stops being sent; these
# eleven are the whole of its guard, and the floors move to the totals they
# reach.
#
# 2026-10-22: 818 -> 823 for the composer kept off the fold of a half-open
# iPhone Duo. A composer left across the crease fails nothing: it still
# sends. These five are the whole of its guard -- no fold, a fold it crosses,
# one it misses, a horizontal one, and a pane too narrow to move into -- so
# the floor moves past them.
#
# 2026-10-23: 823 -> 832 and 728 -> 737 for the tools a paired Mac offers.
# A question that stops being sent with them fails nothing: it is answered
# as a plain chat, only without the search. These nine are the whole of
# that guard -- the answer's `mcp_servers` read whether or not the Mac can
# draw, the query table with the body unchanged, every question run with
# them, a Mac that cannot draw still running them, none to a Mac that names
# none, Retry with them and Continue without, none to a gglib reached by
# address, and a lost PUT sent again with them for a question and without
# for a Continue -- and the README claim names all nine.
#
# 2026-10-24: 832 -> 848 and 737 -> 756 for the tool calls under a reply and
# the Tools switch. A row that stops being drawn, a server or failure that
# stops being kept, or a switch that stops being sent fails nothing else:
# the reply still reads and the question is still answered. These sixteen
# are the whole of that guard -- an exchange kept before the two fields,
# the server and failure read from the run, the request unchanged by them,
# the heading, the arguments, the cut answer, a call never answered, the
# row's words and mark, one row per call and none under a question, the
# switch on by default and turned off, off sent as a plain run or with the
# drawing tool alone, off kept on a PUT sent again, no switch where no tools
# are offered and off told there only to a Mac not yet heard from, the
# column kept and opened across in both directions, and the servers listed
# in the status sheet -- and the README claims name them, beside three
# earlier tests they extend: the query table, a branch's copy and a move to
# another provider.
#
# 2026-10-24: 848 -> 850 and 756 -> 758. One test pins that a gglib which
# refuses `tools=none` leaves its sentence on the question, still drawing,
# and one that a question with Draw put again after a relaunch, before the
# Mac's answer is back, keeps the tools off.
#
# 2026-10-24: 850 -> 853 and 758 -> 761 for the line of a call the model is
# still writing. A frame that stops being read, or a count that stops being
# shown, fails nothing else: the call's own line still comes. These three
# are the whole of that guard -- the frames read on both doors with a cut
# that ends in an error, the count in the locale's digits, and each later
# line taking the writing line's place -- and the README claim names them.
#
# 2026-10-24: 853 -> 854 and 761 -> 762. One test pins that a Mac's run
# which ends while a call is still being written leaves no line for that
# call on the ended reply.
#
# 2026-10-24: 854 -> 861, 28 -> 29 and 762 -> 770 for a long chat's way back
# to its latest message. A button that never shows fails nothing: the chat
# still scrolls, only by hand. These eight are the whole of its guard -- none
# at the bottom, the composer's inset not counted, none under half a screen,
# one past it, none for a short chat, a chat at its latest kept there as the
# keyboard comes up and one scrolled up left alone, and the walk that scrolls
# up, jumps back and follows the next reply -- so the floors move past all
# of them.
#
# 2026-10-24: 861 -> 867 and 770 -> 776 for the conversation list kept beside
# the chat on an open iPhone Duo. A list left behind its button fails
# nothing: it is still a tap away. These six are the whole of its guard --
# kept on a tall regular-width window, left alone on a wide one, a square
# one, one too narrow for the list and a chat, a folded Duo, and a folded Duo
# on its side -- so the floors move past them.
#
# 2026-10-24: 867 -> 869 and 776 -> 778 for the list laid beside the chat on a
# phone, where iOS lays a split view's list over the chat. A list at the
# wrong width fails nothing: it is still beside the chat. These two are the
# whole of that rule's guard -- three eighths of the open Duo, and never
# under 240 points -- so the floors move past them.
#
# 2026-10-24: 869 -> 872 and 778 -> 781 for the window read by its width. On
# the open Duo the keyboard made the window read as wide, the layout changed
# under the field, and the keyboard went back down; nothing else fails when
# it does. These three are the whole of that guard -- the keyboard's height
# ignored, a turn or a fold read afresh, and the first reading taken as it
# is -- so the floors move past them.
#
# 2026-10-24: 872 -> 873 and 781 -> 782. One test pins that a chat a few points
# short of its latest, as a finished reply's row drawn again leaves it, is
# still taken back there when the keyboard comes up: on CI's slower runners
# it was left with the reply under the keyboard.
#
# 2026-10-25: 873 -> 875 and 782 -> 784. Two tests pin that a chat at its
# latest follows a reply as it grows, even a few points short of its very
# bottom, and that one scrolled well up, or with nothing coming, is not: the
# bottom anchor let go of such a chat on CI's iPad and the reply ran on under
# the keyboard. Nothing else fails when it does.
#
# 2026-10-25: 875 -> 887, 29 -> 30 and 784 -> 797 for an iPhone Duo open on
# its side as a book. Pages that never show fail nothing: the chat still
# spans the fold as it did. These twelve are the whole of that rule's guard
# -- read as sideways, not when folded, turned small or upright, the walk's
# height waived, the pages met at the fold, none flat, none across a prop
# fold or beside a fold too near an edge, half the screen flat, and the
# panel's parts for a chat kept here, one offered nothing and a Mac's -- and
# the walk is the only check that the panel takes the list's place and the
# draft is kept, so the floors move past all thirteen.
#
# 2026-10-26: 887 -> 888 and 797 -> 798. A paired Mac's servers are read by
# id and name, and two the Mac lists under one name are two: folded into
# one, a pick of either would start both, and nothing else fails. The one
# test is the whole of that guard, so the floors move past it.
#
# 2026-10-26: 888 -> 887 and 798 -> 797. A run names its servers by id or
# says `none`, and `builtin` is gone from the wire, so a gglib that refuses
# `none` is one from before ids, which refuses every run that names a
# server as well; the test that a refused `none` left its sentence on the
# question pinned a case this build no longer singles out, and goes with
# its marker.
#
# 2026-10-26: 887 -> 909 and 797 -> 819 for each conversation picking which
# of the paired Mac's servers it uses. A pick that stops being named, a new
# conversation that names every server, a switch that drops the picks or a
# choice that a relaunch, a branch or a move gets wrong fails nothing else:
# the reply still comes, with other tools or none. These twenty-two are the
# whole of that guard -- the choice's own rules, its column, its menu and
# its panel rows, and the runs it names -- so the floors move past them.
#
# 2026-10-26: 909 -> 916 and 819 -> 826 for the wrench's "!". A badge that
# never shows, or never clears, fails nothing: the menu still picks. These
# seven are the whole of its guard -- a new chat badged, a change from the
# menu clearing it in one write, showing twice writing once, a server
# opened later badging every chat, a branch keeping what its source saw,
# what counts as unseen, and the Duo panel button's name -- so the floors
# move past them.
#
# 2026-10-26: 30 -> 31. The walk is the only check that the wrench shows
# for a paired Mac that opens a server, that its menu's row picks it, and
# that the name the toolbar keeps follows; a menu SwiftUI lays out wrong
# fails nothing else.
#
# 2026-10-28: 916 -> 927 and 826 -> 837 for math kept as written. Math that
# markdown reads as markdown fails nothing else: the reply still shows, with
# a backslash gone here and a word in italics there. These eleven are the
# whole of its guard, so the floors move past them.
#
# 2026-10-28: 31 -> 32 and 837 -> 838. The walk is the only check that the
# composer takes the caret and a message while a reply runs and holds it
# unsent until the reply ends; a field shut mid-reply fails nothing else:
# every other walk types between replies.
#
# 2026-10-29: 927 -> 939 for what each kind of provider is and speaks. A
# pipe answers yes to every one of these questions and an address no, the
# probe aside, so a site asking the wrong one passes every other test until
# a kind answers them differently. These twelve are the only place a kind
# answers each question by name -- a session, a paired Mac, a pipe, gglib,
# runs and the Draw switch -- so the floor moves past them.
#
# 2026-10-29: 939 -> 967, 32 -> 33 and 838 -> 858 for the provider that runs
# on this iPhone's own engine. It is gglib by its kind and keeps no runs and
# no drawing, and before it no kind said yes to the first and no to the other
# two, so a predicate that forgot it passes every test written before it;
# the engine seam, its mock and its sentinel, the stored kind, the advice
# under a model too big and the order in which a serve and a shutdown wait
# for each other are guarded nowhere else either. These twenty-eight, the
# walk and the twenty markers naming them are the whole of that guard, so
# the floors move past them.
#
# 2026-10-29: 967 -> 976, 33 -> 35 and 858 -> 868 for the model browser. That
# it reads the device once per opening and asks every verdict with that
# reading, that a quantization too big for this iPhone never reaches the
# library, that choosing a model adds This iPhone once, that a download
# whose steps stop short can be chosen again, and the words a chip and the
# Why sheet say are guarded nowhere else: a browser that read the device per
# row, or downloaded what cannot run, would pass every test before these.
# These nine, the two walks, and the ten markers naming the walks and eight
# of the nine are the whole of that guard, so the floors move past them.
#
# 2026-10-29: 976 -> 988, 35 -> 36 and 868 -> 881 for downloads to this
# iPhone. That the bar only goes up through a pause and a resume, that Cancel
# takes the partial file away, that a finished download joins the model
# list, that one there is no room for never reaches the library, that the
# models directory is private and out of the backup at launch and after each
# download, and that the library hears pauses and resumes in the order the
# scenes came are guarded nowhere else: a download that started again on
# each return, or models a backup carried, would pass every test before
# these. These twelve, the walk and the thirteen markers naming them are the
# whole of that guard, so the floors move past them.
#
# 2026-10-29: 988 -> 999, 36 -> 38 and 881 -> 894 for this iPhone's engine
# running in the foreground only. That a send waits for the engine and
# through its load, that the background puts the engine down only after the
# replies, that a serve landing while the app is away takes itself down,
# that coming back serves nothing, that a memory warning spares a reply,
# that a send which joined a serve put down serves the engine again, that
# Load again serves afresh and asks again, that a refused serve says why
# under the question, and what the pill says for each state are guarded
# nowhere else: an engine holding its model through the background would
# pass every test before these. These eleven, the two walks and the
# thirteen markers naming them are the whole of that guard, so the floors
# move past them.
#
# 2026-10-29: 999 -> 1002 and 894 -> 898 for the gglib this build carries.
# A binding and a framework from two releases build without a word and trap
# at the first call, on a device, and a Settings row that named a constant
# would read true until the next release. The call through the Mac's
# framework held to the vendored binding.json, the row's words and the row
# reading the linked framework are guarded nowhere else; these three, and
# the four markers naming them and the walk that reads the row, are the
# whole of that guard, so the floors move past them. The walk gained an
# assertion, not a case, so its floor stays.
#
# 2026-10-29: 1002 -> 1023 and 898 -> 909 for gglib's own model library.
# Each of gglib's records and errors read as the app's own, an open that
# failed tried again and a pause that opens nothing, a download's steps that
# stay in one stream through a pause and call gglib's download off when the
# stream ends first, a download asked of the library followed through its
# watch, the library's folders private and out of the backup, a
# model listed, judged and removed through the Mac's framework, a search
# and quantizations against Hugging Face behind GGCHAT_LIVE_HF, and a chip
# and sheet that promise a download will tell only when it can: none is
# guarded anywhere else, since every other test drives the mock library.
# These twenty-one and the eleven markers naming them are the whole of that
# guard, so the floors move past them.
#
# 2026-10-29: 1023 -> 1038, 38 -> 39 and 909 -> 924 for gglib's own engine on
# an iPhone. What each of its states is said as, that the pill's model is the
# name its proxy lists, that its stream starts where it stands, ends after
# stopped and stops pulling when nobody listens, that a serve off loopback is
# refused, that it is served from the model library's own open, that the Mac
# runs none, that the app model serves and puts it down as it does the mock,
# and that a reply it streamed raises the ring are guarded nowhere else: an
# engine whose pill read Not loaded for ever would pass every test before
# these. These fourteen, the recorder that makes the replayed fixture, the
# device walk and the fifteen markers naming them are the whole of that
# guard, so the floors move past them.
#
# 2026-10-29: 1038 -> 1039 and 924 -> 926 for the library's folders, which
# are marked out of the backup at every open and not only when made: a mark
# cleared since is restored by the next open, which nothing else checks. Its
# marker, and the engine's claim that its library is private and out of the
# backup now naming the test that shows it, are the whole of that guard.
#
# 2026-10-29: 1039 -> 1044 and 926 -> 931 for This iPhone in Add provider and
# the browser's compact rows. That This iPhone is a kind only where a model
# runs here, that its page in Add provider opens no sheet of its own, that a
# chip's sheet carries gglib's sentence for a suggestion and no figures for
# an installed model, the line each row says, and "On this iPhone" holding
# the installed models and the downloads on their way are guarded nowhere
# else: a Mac offering This iPhone, or the browser's sheet stacked over Add
# provider, would pass every test before these. These five and the five
# markers naming them are the whole of that guard, so the floors move past
# them. The empty phone's walk was renamed for its new way in, not added,
# so its floor stays.
#
# 2026-10-30: 1044 -> 1045, 39 -> 40 and 931 -> 933 for the ways back to the
# browser. That Use adds This iPhone with a model already on this iPhone
# only while there is none, and that Settings' "Models on this iPhone" leads
# to the browser, are guarded nowhere else: a phone whose This iPhone was
# removed, with models still on it, or one whose This iPhone already has a
# model while another provider is there, would have no way back in and pass
# every test before these. The test, the walk and the two markers naming
# them are the whole of that guard, so the floors move past them.
#
# 2026-10-30: 1045 -> 1056, 40 -> 41 and 933 -> 945 for the one model list.
# The line under each model read out of gglib's description, a part it calls
# unknown left out and any other server's said as it came; a section for each
# provider in their order, filled without dialling a pipe or serving the
# engine; a pipe that is down dimmed under what it listed last; a pick on
# another provider moving the conversation with that model and dropping what
# the move drops, waiting for a reply in flight, and giving a conversation
# with no provider one; the chips, the search and when it is offered; and the
# list walked with two providers on a simulator. A list that offered only the
# conversation's own provider again would fail none of the tests before
# these, so these eleven, the walk and the twelve markers naming them are the
# whole of that guard, and the floors move past them.
#
# 2026-10-30: 1056 -> 1060 and 945 -> 949 for the list's own reach. Connect
# on a pipe that has listed nothing dialling it and its models arriving,
# opening the list asking a pipe that is up again, and the list sized from
# the chat's free height so its search stays above the keyboard, with more
# left at an accessibility text size, where its chips go and its search
# scrolls with the rows: a list that showed a dead line for such a pipe,
# never relisted one, or ran under the top bar would fail nothing before
# these. These four and their markers are the whole of that guard, so the
# floors move past them.
#
# 2026-10-31: 1060 -> 1061 and 949 -> 950 for gglib's published code list.
# One new test reads gglib's `docs/error-codes.json`, vendored at v0.28.0,
# and fails when gglib publishes a code that is neither in the vocabulary nor
# filed as not shown here. The hand-typed list it replaces failed nothing when
# gglib added a code, so this test is the whole of that guard, and the
# README claim names it.
#
# 2026-10-31: 1061 -> 1062 and 950 -> 951 for a Continue of a reply that has
# only thought, put again after its PUT lost its answer. It is put again
# ending on that reply, with no tools and not drawing; dropped as if it were a
# fresh question's empty placeholder, it would be the question itself again,
# with the conversation's tools and its Draw. No other test has a reply of
# reasoning alone put again, so this one and its marker are the whole of
# that guard, and the floors move past them.
floor "package test cases" "$(test_cases "$ROOT/Tests")" 1062
floor "XCUITest cases" "$(test_cases "$ROOT/App/ggchatUITests")" 41
floor "README test markers" "${markers:-0}" 951

exit $status
