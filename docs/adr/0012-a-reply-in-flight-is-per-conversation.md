# ADR 0012 — A reply in flight is per conversation

- **Status:** Accepted
- **Date:** 2026-10-19
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

While any reply was coming in, Send was greyed out in every other chat,
including a new one. Nothing decided that: the app held one reply in flight
for the whole app, one task streaming it and one send waiting for a pipe, and
every check asked whether any reply was in flight. A Mac's chats never had
the limit; each reply the Mac writes for one is carried on beside the
others.

The servers do not need it either. gglib runs one request at a time per
model and queues a second one behind the first in its admission queue, so a
second send is answered once the first reply ends. A server that runs
requests in parallel answers both at once.

## Decision

**Each conversation has at most one reply in flight, and conversations do not
wait for each other.** A send, Retry or Continue is refused only while its
own conversation has a reply in flight, or a hub is still writing one of its
replies (ADR 0002). Stop puts down that conversation's reply and no other.

Everything that put down "the" reply now puts down each one it covers:
the background walks away from or puts down every reply, and waits for all
of them before the pipes are hung up; removing a provider puts down every
reply through it; deleting a conversation puts down its own. Coming back
reads on from every reply a hub went on writing, not one after another.

A send through a pipe that is not connected still waits for it (ADR 0006),
one wait per conversation. Every wait on a pipe is woken when it changes, a
refused dial's sentence goes under every waiting question, and the pipe is
dialled once for all of them: a second wait joins a dial a first one started.

Nothing new is stored. A branch made from a conversation whose reply is
streaming is a conversation of its own, so it is answered at once.

## What would undo it

- gglib refusing or timing out a second request instead of queueing it, in
  daily use: then a send waits for another conversation's reply again, or
  only for one through the same provider.
- Two replies at once making a phone or the machine at home noticeably
  slower than one after the other: then they are queued here.
