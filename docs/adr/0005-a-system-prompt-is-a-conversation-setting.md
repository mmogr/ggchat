# ADR 0005 — A system prompt is a conversation setting, not a turn in the transcript

- **Status:** Accepted
- **Date:** 2026-09-23
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

Until now this app never sent a system message. `Role.system` is declared
in `Models.swift` and nothing made one, the wire encoder passes any role
through as its raw value, and gglib's OpenAI-compatible endpoint, local or
over a pipe, accepts a `role: "system"` turn and protects it. The gap was
entirely on this side: nothing created a prompt, nothing stored one, and
there was nowhere to type it.

The obvious place to keep a prompt is the one `Role.system` suggests: a
message at the head of `Conversation.messages`. That is the choice this ADR
exists to turn down, because `messages` already means something precise and
three things depend on it.

It is what the transcript draws. A system turn stored there is a SYSTEM row
above the first question unless every view learns to skip it, and a view
that forgets draws the user's instructions to the model as if they were part
of the conversation.

It is what Retry and Continue read. Under ADR 0002 both are decided by the
last message: Continue needs a partial assistant reply there, Retry needs
the user's question. A prompt at the head does not move the last message,
but it does make "the conversation" mean two things, the one the user reads
and the one the model receives, and every later rule written against
`messages` would have to say which it meant.

It is what the tests read. Every assertion on `messages[0]` and every
role array in the streaming, refusal and error tests is written against a
transcript that starts with the user. A stored prompt shifts all of them by
one, and a test that passes after that shift has stopped saying what it
said.

## Decision

**The prompt is a field of the conversation, `Conversation.systemPrompt`,
and becomes a turn only when a request is built.**

`Conversation.requestMessages` is the transcript with the prompt in front of
it as a `.system` message, or the transcript alone when there is no prompt.
It is read in exactly one place, where `AppModel+Streaming` builds the
`ChatRequest`, and send, Continue and Retry all pass through that place. So
all three carry the prompt without any of them knowing it exists, and the
guards they apply to the last message are untouched.
`requestMessages` is computed, not stored: its result goes only into the
`ChatRequest` and is never assigned back to `messages`, so the system turn
built for a request never reaches `update(_:)` or storage.

The prompt is live. The next request uses whatever it says at that moment,
and Continue is a request like any other, so a prompt edited under a partial
reply is the prompt that reply is continued with. The alternative is to
record on each reply the prompt it was written under, which is more state
for a case nobody has reported; the kill criteria below say what would
change that.

Blank means none. `setSystemPrompt(_:for:)` trims what it is given and
stores nil when nothing is left, and `hasSystemPrompt` treats a prompt of
only whitespace as absent, so the model is never sent an empty system turn.

The system turn carries a fixed id, `Conversation.systemPromptMessageID`,
and is dated with the conversation's `createdAt`. `Message` otherwise mints
a fresh `UUID()` and callers pass the clock, and either would make two
requests built from the same conversation unequal. A fixed id cannot collide
with a stored message because the turn is never stored.

Editing the prompt does not touch `updatedAt`. The sidebar is sorted by it,
and a setting changed is not a conversation moved to the top of the list.

The prompt is kept in an optional `systemPrompt` column on
`ConversationRecord`. Optional is what lets SwiftData's lightweight
migration add it to a store written before it existed, with every row
reading nil; a non-optional attribute would fail that migration, and
`makeContainer` would fall back to an in-memory store and log it, which to
the user looks like every conversation gone. The same property cuts the
other way: an older build that opens a store carrying the new column meets a
model it does not know, fails to open it, and falls back to memory in the
same way. That hazard is not new. `MessageRecord.failureData` was added the
same way and already carries it, so a downgrade past either change loses the
store for that launch and not the file on disk.

## Kill criteria

- **Reading:** `LiveGGLibTests.testASystemPromptSteersTheReply`, run with
  `make test-live` against a gglib. If the prompt has no visible effect on
  the reply, or a server refuses a request because of the leading system
  turn, then prepending it is the wrong shape for that server and the prompt
  needs another route, such as being folded into the first user turn for
  servers that will not take a system role.
- If Continue after a prompt edit is reported to visibly restart the reply
  rather than carry it on, the prompt stops being live for a partial: snapshot
  it onto the partial message when the stream stops, and send that snapshot
  when the same reply is continued.
- If users ask to see in the transcript when the prompt changed, the answer
  is a header row above the first message, drawn from the field, not a turn
  stored in `messages`.
