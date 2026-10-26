# ADR 0013 — Tools are a switch of the conversation, and what the Mac offers is chosen on the Mac

- **Status:** Accepted; superseded in part by ADR 0014
- **Date:** 2026-10-24
- **Supersedes:** nothing
- **Superseded by:** [ADR 0014](0014-each-conversation-picks-which-of-the-macs-servers-it-uses.md),
  in part: the all-or-none switch and "what the Mac offers is chosen on the
  Mac, never here". Each conversation now picks, by id, which of the
  offered servers it uses, under a master switch.

## Context

A paired Mac says which MCP servers a run from this phone is offered, in
its answer about drawing (`mcp_servers`), and since ggchat #215 every
question to such a Mac is a run with their tools. Which servers those are
is set on the Mac, with `gglib remote enable --allow-mcp`. Nothing on the
phone could say "not for this question": a quick question went through the
agent loop with a web search on offer, whether or not it was wanted.

gglib can run a chat without them. From the gglib pull request that adds
it, `PUT /v1/runs/{id}?kind=chat&tools=none` runs the chat with no MCP
tool, and with `&draw=true` only the drawing tool. A gglib from before it
refuses `none` with a 400.

## Decision

**Whether a question may call the Mac's tools is a setting of the
conversation, on until turned off. Which servers the Mac offers is read
here, never chosen here.**

The switch is offered only where it can do something: a conversation kept
on this phone whose provider is a paired Mac that named servers it offers.
A gglib reached by address, a Mac that names none, one from before the
list and one not heard from have no switch. The first three are never told
the tools are off, whatever a conversation stores. One not heard from may
offer servers, and is told: after a relaunch, a question whose `PUT` is
sent again before the Mac's answer is back keeps the tools off rather than
run the tools the person turned off, so with Draw it goes with
`tools=none&draw=true` and without Draw as a plain run. A Mac's own chat is
the Mac's, and has no switch here.

A conversation stores the choice: `Conversation.toolsOff`, one optional
column that reads as on and is written only for a conversation that turned
the tools off, set by id with `updatedAt` left alone, as Thinking is (ADR
0009). It is sent from the one place a request is built, so a send, Retry
and a run's `PUT` sent again all carry it. Off, a question is a plain run
with no query, and one sent with Draw is put with `tools=none&draw=true`,
so it keeps the drawing tool and nothing else. On, every request is what it
was. A branch copies the choice; a move to another provider drops it, with
the Thinking choice and the image model, since it was made for the Mac
left.

The control is a toggle in the chat's top bar beside Thinking: a wrench,
filled while on and an outline while off, with "on" or "off" in its name.

What the Mac offers is shown read-only, as a list of the servers' names in
the server-status sheet, with a line saying they are chosen on the Mac.
Nothing there can be tapped. A per-server choice on the phone would be a
second place to decide what the Mac's own setting already decides, and the
two could disagree.

One cost is known. A conversation set off and sent with Draw to a gglib
that has the server list but not `none` is refused, and the question shows
the refusal with Retry. So is such a question put again after a relaunch
to a gglib that knows `draw` but not `none`, with the server list or
without it, since its answer is not back yet: a refusal is the safe
failure, where `tools=builtin` would run every server's tools. Turning the
tools on again, or updating gglib, is the way out.

## What would undo it

- People wanting a different set of servers per conversation, not all or
  none: then gglib needs a word for a subset, and the switch becomes a
  list, by a decision of its own.
- People wanting one choice for every conversation on a Mac: then a
  default per provider, which a conversation's own choice still overrides.
- gglib deciding per turn whether tools are worth offering: then this
  switch is the off switch beside that, and nothing more is added here.
