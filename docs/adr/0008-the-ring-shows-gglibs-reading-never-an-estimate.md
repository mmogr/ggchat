# ADR 0008 — The context ring shows gglib's reading, and is hidden rather than estimated

- **Status:** Accepted
- **Date:** 2026-10-05
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

A conversation fills its model's context, and nothing in the app said how
full it was. The numbers exist on the serving side: gglib counts the prompt
and completion tokens of every reply and knows the context its server was
started with. This app read the counts off the stream and threw them away.

Two shortcuts would have drawn a ring sooner, and both draw one the server
never vouched for.

The model list's `context_window` is the wrong size. gglib shaves every
entry by a safety margin of 8 percent, and only the running model's entry is
its live context (`gglib-proxy/src/models_endpoint.rs` and `models_list.rs`
as of gglib pull request #1273). A ring over it reads full early for the
loaded model and is a guess for any other.

Counting on the phone is the wrong count. The phone has no tokenizer for the
model, and cannot see what the server trimmed from a request or what a tool
call added to one.

## Decision

**The ring draws what gglib reported for the last finished reply's last model
call, and when gglib reported no context size there is no ring.**

From gglib pull request #1273 on, gglib sends the size beside the counts on
each way a reply reaches this app: inside a chat stream's `usage`, for a
request that asked for progress (`context_size`, `trimmed_messages`); on an
agent run's `turn_usage` event; and beside a saved reply's row
(`contextSize`, `trimmedMessages`, `finishReason`). `ContextReading` exists
only when the prompt tokens, the completion tokens and a size above zero are
all there. Absent is unknown, never zero, and the model list's
`context_window` is not a fallback.

The arithmetic and the words are not chosen here. They follow one file of
worked examples, `contracts/context/readings.json`. The file is gglib's: it
is added by the gglib change that draws the same ring on its chat page, the
pull request stacked on #1273. This repo holds a copy of it, byte for byte,
which `ContextContractTests` replays. Used is the prompt plus the completion
of that one call and never a sum, the percent is a whole number with a half
rounded up, a warning starts at 70 and danger at 90, and the sheet's
sentences are fixed.

A reply that is stopped or fails leaves the reading of a conversation kept
here as it was, while on a Mac's chat a reply stopped after one of its model
calls finished moves the reading to that call. A reply that finishes with no
size leaves none: an older reply's is not shown in its place. A conversation
kept here keeps its reading in one optional column, with the model that made
it, and does not draw it under another model. A Mac's chat keeps nothing: its
reading is read from the Mac's rows, replaced by what a reply in hand counts,
and dropped with the chat (ADR 0007).

So against an older gglib, or any other server, the app looks as it did:
no ring.

One reading is knowingly lost. A run's counts arrive in a frame of their own,
and a reply walked away from after that frame and before the run's end is
read on without them, so it finishes with no reading, and the ring is gone
until the next reply. A run read on from between its finish frame and its
usage frame gets the counts without the line that says the reply was cut off.
Keeping them would take one more stored field for a window a frame wide; the
last line below says when that is worth it.

## What would undo it

- **Reading:** the same conversation open on gglib's chat page and here,
  showing different percents, or a ring here that disagrees with the context
  the server status pane shows for the same slot. Then the copy of
  `readings.json` is stale or one side has drifted from it, and the file is
  copied again and replayed before either ring is believed.
- A server other than gglib that people use with this app and that reports
  the context it was started with: then that report is read too, by a rule of
  its own, and still nothing is estimated.
- The owner asking for a ring before the first reply, or against a server
  that sends no size. That is an estimate, and it would be drawn as one and
  said to be one, not with this ring.
- The reading lost to a walked-away run being noticed in use: then the counts
  are kept with the message's run id and cursor, and written as the reading
  only when the run's report says it completed.
