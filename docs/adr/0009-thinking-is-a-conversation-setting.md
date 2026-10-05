# ADR 0009 — Thinking is a conversation setting, and a Mac's chat keeps its own

- **Status:** Accepted
- **Date:** 2026-10-05
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

Some models think before they answer, and for a quick question that is time
spent on something nobody asked for. Nothing in this app could turn it off.

gglib can. From gglib pull request #1278, which adds the Thinking choice, it
says three things a client can use. Its model list names
the models that think: `reasoning` in an entry's `capabilities`, beside
`vision`. A request to `chat/completions`, or a run's `PUT`, turns thinking
off for itself with `reasoning_budget_tokens: 0`, which gglib honoured
already and remembers nothing of. And a turn on one of gglib's own chats may
say `"thinking": "off"` or `"default"`, which gglib remembers on the chat and
says back in the opened chat's `settings`. A gglib from before this lists no
model as one that thinks, and refuses a turn that carries the key.

An effort level is the other control, and it is left out: gglib drops a
client's level by design.

## Decision

**Thinking is a setting of the conversation, as its system prompt is (ADR
0005), offered only where gglib says the model thinks; for a Mac's chat the
Mac remembers it and this phone stores nothing.**

The switch is offered only where it can do something. For a conversation
kept here the provider must be gglib, a pipe or a server that answered the
status probe, and its list must name the conversation's model with
`reasoning`. Another server, an older gglib, a model the list does not name
and a list not read yet all have no switch.

A conversation kept here stores the choice: `Conversation.thinkingOff`, one
optional column that reads as on, set by id and leaving `updatedAt` alone.
It is sent from the one place a request is built, so a send, Continue, Retry
and a run's `PUT` sent again all carry it: `reasoning_budget_tokens: 0` when
off, and no key at all otherwise, so with the switch on the body is byte for
byte what it was. It goes to gglib alone, and not for a model the list names
as one that does not think. Picking such a model clears a stored Off, since
there is then no switch to turn it back on with.

A Mac's chat stores nothing here (ADR 0007). The opened chat says what the
Mac remembers and the switch shows it. Set here, the choice is held in
memory with the open chat and said with the next turn, once: `off`, or
`default` to tell the Mac to forget. Once the Mac takes that turn it is what
the Mac remembers, and later turns say nothing. A turn put again after a
lost answer carries the same body. A change made and not sent is gone on
Back; keeping it would mean writing something about a Mac's chat to this
phone.

Whether a Mac's chat has the switch is a lookup by name: the model its
settings name, else its last reply's, else the one the list of chats gives
it, in that Mac's model list. So opening a Mac's chat lists the Mac's models
when this phone has none, and a pipe coming up lists them again; a list that
fails keeps the one before.

The control is one toggle in the top bar of both kinds of chat, where the
system prompt's button is: a brain, filled while on and an outline while
off, with "On" or "Off" as its spoken value, so the state is never the tint
alone.

Three costs are known. A gglib added by address is not known to be gglib
after a relaunch until its status probe answers, so until then it has no
switch and a request carries no budget. If that first probe fails (the Mac
asleep, gglib not started, the phone off the network), the app takes the
server as not gglib for the rest of that run: it has no switch, and a stored
Off is not sent, until the app is launched again. A pipe is not affected. A
Mac's chat that names no model this phone can find in the Mac's list has no
switch. A chat that has never run can still have one: made with a model from
the Mac's catalogue, it takes that model from its row in the list of chats,
and the switch is there when the Mac lists that model as one that thinks.
And a Mac's chat set off elsewhere runs off from here whether or not the
switch can be shown.

## What would undo it

- **Reading:** one of a Mac's chats open on gglib's chat page and here,
  each read again, with the two switches disagreeing. Then one side has
  drifted from `contracts/chats/recorded.json`, and the recording is copied
  again and replayed before either switch is believed.
- gglib saying in the opened chat whether its model thinks: then the lookup
  by name goes, and with it the list read on opening.
- A change made and not sent being lost on Back and noticed in use: then
  gglib needs a way to set the choice without a turn. A copy kept on this
  phone is not the answer.
- People wanting one choice for every conversation on a model: then a
  default per model, which a conversation's own choice still overrides.
- gglib honouring a client's effort level: then the switch may become a
  level, by a decision of its own.
