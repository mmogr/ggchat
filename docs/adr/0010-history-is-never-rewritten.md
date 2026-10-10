# ADR 0010 — A saved reply is never rewritten: a change branches the chat

- **Status:** Accepted
- **Date:** 2026-10-10
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

A conversation here could only grow. Retry answered a question that had no
reply, and Continue carried on one that stopped, but nothing could ask a
question again in other words, have the model answer it again, or keep a
reply as the person would have written it. Those are the changes people
reach for most, and each of them, done in place, throws away a reply that
was saved and may have been read.

gglib decided the same question for its own chats in its ADR 0017 ("History
is never rewritten", gglib pull request #1375). A change that would discard
or alter a saved reply copies the chat, as far as the point it changes,
into a new chat of the same family, and makes the change there. The one
change made in place is an edit of the chat's last question while nothing
answers it, nor is being written. Every chat stays a plain list, and the
options at a branch point are the different turns the family's chats go on
with after what they share. gglib records the rules as cases
(`contracts/chats/branching.json`), and from gglib pull request #1380 a
paired device can make a change to one of the Mac's chats and answer the
question it leaves (`POST /v1/chats/{id}/changes`, a turn that says
`answer_saved`).

## Decision

The rules are gglib's, and this app holds the same ones. `BranchRules` in
`GGChatCore` is a mirror of `gglib_core::domain::branching`: `plan` says
whether a change is made in place or on a branch, or why it is refused,
`answerable` whether a chat ends in a question nothing answers, `points`
the options a family holds along a chat, and `preview` the line each
option is shown by. `BranchingContractTests` replays gglib's recorded cases
(`contracts/chats/branching.json`) against it, copied byte for byte. The
copy is a snapshot: a change to gglib's rules fails nothing here until the
file is copied again, so it is copied again whenever gglib's changes, and a
case gglib does not record, such as a line ending, is pinned here by a
test of its own.

**On this device**, a conversation is the unit, as it is on the Mac. A
branch is a new conversation with the same title, model, system prompt and
Thinking choice, holding a copy of each message as far as the change, and
then the message the change adds. A copy remembers the message it copies as
first written, and a branch the conversation it was made from and the first
of its family; the fields are optional, so a store written before them
reads every conversation as the first of a family of one. A copy is never
a reply being written: it carries no run, and resuming runs never reads it
as live. Images are kept by their hash, once, so a copy names them and
stores nothing again.

**On a paired Mac's chat**, ADR 0007 still holds: nothing of it is copied
here. A change is sent to the Mac, the Mac makes it by the same rules, and
the branch it makes is one of the Mac's chats, listed with the rest. This
device then opens the chat the Mac names, and, when the Mac says so, sends
the turn that answers it.

Opening another option at a branch point opens the conversation that holds
it; nothing is merged or moved.

## What would undo it

A chat that is a tree in one record (siblings under a message, a pointer to
the one shown) instead of a family of lists. That would let a branch be
switched without changing conversation, at the price of every reader,
writer and request builder learning the tree, and of a wire gglib does not
speak. It would be a change to gglib's ADR 0017 first, and to this one with
it.
