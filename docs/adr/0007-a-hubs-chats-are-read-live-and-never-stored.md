# ADR 0007 — A hub's chats are read live and never stored

- **Status:** Accepted
- **Date:** 2026-09-30
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

A paired Mac keeps its chats in its own database, and since gglib's chats
routes (`GET /v1/chats`, `GET /v1/chats/{id}`, read only by a device through
its tunnel) this phone can see them. The owner's rule for them is "look,
don't copy": each machine keeps the chats it makes, and the others read them
where they are. Copying them here would mean a second record to keep in
step, a phone holding text a `gglib remote forget` at the Mac could not take
back, and a backup, lock and deletion story for all of it.

## Decision

Each paired Mac has a section in the list, "On home", below this phone's own
conversations. It is listed at launch, when the Mac's pipe comes up, and on a
pull of the list. Opening one of its chats reads the rows live into memory
and draws the questions and the replies, read only; Back drops them, and
opening it again reads it again. Nothing of it goes through the conversation
store. A server added by address has no section.

The one thing kept is what the list itself showed: each chat's id, title and
time of last change, and when the list was read, on the provider's row, as
its last-heard time is. While the Mac cannot be reached its section shows
those titles with "last seen 10:42", and opening one says the Mac is
unreachable. They go when the provider does. No message text from the Mac
is ever written to the phone.

The launch now dials every paired Mac, quietly, so the list is live when it
is first seen; before, a pipe was dialled only when a conversation on it was
opened. Coming back to the foreground dials each of them again once, as
`resumeEveryPipe` dials every pipe it had: one attempt, with no retry loop.

> **Amended 2026-09-30 — a Mac's chat is carried on from this phone, and the
> Mac writes the reply.** A send in a Mac's chat is `PUT runs/{id}?kind=agent`
> with `{conversation_id, content}` and nothing else, under an id minted here.
> The Mac rebuilds the history from its own record, runs the reply as an agent
> run, and saves the question and the reply to the chat. This phone reads the
> run's events into memory, its text, its reasoning and a line for each tool,
> and once the run ends reads the Mac's rows in its place; no conversation and
> no message row is written here. Stop cancels the run. Leaving the chat, or the
> background, walks away from the run as ADR 0002 walks away from this phone's
> own; opening the chat again, coming back, or its pipe coming up reads on from
> the last event read.
>
> One more thing is kept on the provider's row: the id of each run this phone
> started that has not ended, and its chat's id, so a relaunch can read it on
> and the list can say "Writing". Not the cursor: the text before it was never
> kept, so a launch reads the run from its start. The run is forgotten when it
> ends, when the Mac no longer has it, when a list no longer names it as live,
> and with the provider. Still no message text from the Mac is written to the
> phone.

## What would undo it

- The owner asking to read a Mac's chats while it is asleep: then the rows
  are kept here, and this phone needs the lock, backup and deletion rules the
  plan dropped.
- The launch's dials costing more than the list is worth, a battery reading
  or the owner saying so: then a section lists only when a pull or an open
  asks for it.
