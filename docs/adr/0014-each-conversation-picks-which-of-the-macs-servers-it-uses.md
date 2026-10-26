# ADR 0014 — Each conversation picks which of the Mac's servers it uses

- **Status:** Accepted
- **Date:** 2026-10-26
- **Supersedes:** in part, [ADR 0013](0013-tools-are-a-conversation-switch.md):
  the all-or-none Tools switch and "what the Mac offers is chosen on the
  Mac, never here" that it chose, and nothing else in it
- **Superseded by:** nothing

## Context

Under ADR 0013 a conversation had one switch: every server the paired Mac
opens to devices, or none. People wanted to choose per conversation, on the
fly, from what the Mac already allows: a web search in one chat, a file
server in another, neither in a third.

gglib now names servers by id on the device wire (its ADR 0026). Its
drawing answer lists each server open to devices as `{"id", "name"}`,
sorted by name then id and not deduplicated, and a chat run is
`PUT /v1/runs/{id}?kind=chat&tools=<T>[&draw=true][&image_model=N]`, where
`T` is `none` or the servers' ids in canonical decimal, sorted, each once,
joined by commas. `builtin` is gone. gglib refuses a malformed value with a
400 and drops a well-formed id it does not open, where servers start, so
the Mac stays the ceiling: the phone can only narrow what it allows.

## Decision

**Each conversation picks, by id, which of its paired Mac's offered servers
it uses, under a stored master switch. A new conversation picks none.**

- **Per conversation, by id.** `Conversation.toolChoice` is a
  `ToolChoice {off, picked, seen}`, the sets holding the servers' ids on the
  Mac. A pick survives a rename. A server deleted and added again on the
  Mac has a new id, so it comes back unpicked and unseen. Two servers of
  one name are two rows, each shown with its id after the name, `fs (3)`.
  Picks and the seen set are never pruned: an empty offer can be a read
  that failed, and ids are never reused.
- **A stored master switch.** A switch derived from "anything picked" would
  have to clear the picks to turn off, and turning on again could restore
  nothing. Stored, off keeps the picks and on restores them in one press.
  Off, a question is a plain run, and with Draw a run with the drawing tool
  alone (`tools=none&draw=true`).
- **A new conversation picks none**, and a server the Mac allows later is off
  in every conversation until picked. Nothing runs that the person did not
  choose in that conversation.
- **The wrench is a Menu of Toggles**: "Use tools", then a tick per offered
  server in the Mac's order, disabled while off. Toggles are the semantic
  multi-select. On iOS the menu stays open while picks are made
  (`menuActionDismissBehavior(.disabled)`); on macOS that modifier does not
  exist and the menu closes after each pick, and in an iPhone Duo's bar it
  closes after each pick too.
- **The badge.** While the Mac offers a server the conversation has never
  shown, the wrench carries the toolbar's own badge, "!", its name ends
  ", new tools available" (the badge is not read by VoiceOver), and the
  server's row says "New". On an open iPhone Duo on its side, where the
  wrench is in the panel, the panel's button carries the badge and its name
  says so.
- **What clears it.** A SwiftUI Menu says nothing of being opened: a spike
  on iOS 26.5 and on the Duo's iOS 27.1 found that `.onAppear` and `.task`
  on its content run once, when the toolbar lays it out, `.onDisappear`
  never runs, and a gesture on the Menu never fires. So a change made from
  the menu, the switch or any row, marks every offered server seen in the
  same write as the change; opening and closing with nothing changed leaves
  the badge. On the Duo the panel's tools rows coming on screen, or the
  offer changing while they are, mark them seen, so opening "This chat" for
  Thinking also clears the badge. A popover, which could say when it is
  shown and so clear the badge on open, was weighed and not taken: the
  badge clearing on the first change made from the menu is the decision.
- **"New".** In the menu, rows read "New" from the stored seen set, so on an
  iPhone, where the menu stays open, the marks go at the first pick. In the
  Duo's panel the servers that were new when the rows came keep "New" for
  as long as the rows stay.
- **The sheet stays read-only.** The server-status sheet lists the servers
  offered, says a server is opened on the Mac with
  `gglib mcp allow-remote <server>`, and that each conversation picks the
  ones it uses from its Tools control. This answers ADR 0013's worry that a
  choice on the phone would be a second place to decide what the Mac
  decides, and that the two could disagree: they cannot. The Mac decides
  what is offered, the phone picks among that, and gglib intersects every
  request with its own open set.
- **What a request names.** The picks the Mac still offers, when its offer
  is known; none from a Mac known to offer none, by address, or for a
  Continue. While the Mac has not been heard from (after a relaunch or an
  edit, before its answer is back), every request, a fresh send and a
  run's `PUT` sent again alike, names the picks as kept, and gglib drops any
  it no longer opens.
- **When a change applies.** From the next request built. A run in flight
  keeps what it was put with, and gglib keeps a re-PUT of a started run's
  tools.
- **Draw is independent.** Draw with no pick is `tools=none&draw=true`; with
  picks, their ids and `draw=true`.
- **What carries it.** A branch copies the whole choice, the seen set
  included. A move to another provider drops it, and so does an edit that
  points the provider at another Mac, re-pairing included, with the image
  model, in one write per conversation: an id names a server on one Mac
  alone.

## Known costs

- The offer is fetched only when a conversation is opened or its pipe comes
  back (`catchUp`), and after an image model is refused, and it is
  forgotten on an edit. A server the Mac opens mid-conversation shows at
  the next of those.
- Ids are per Mac. A database reset on the Mac can hand an old id to a new
  server; the damage is bounded by the Mac's ceiling, since only servers it
  opens to devices ever start.
- A Mac not heard from yet, with picks, is put an agent run while the wrench
  is hidden: it takes one of the Mac's agent slots and may answer 429
  `agent_busy`.
- Re-pairing drops the picks.
- Opening the wrench's menu and closing it without a change leaves the
  badge on.
- On the Duo, seen is marked when the rows are on screen, not on a tap.

## What would undo it

- People wanting per-tool choice rather than per server.
- The badge reading as noise: then it goes, and "New" in the rows is left.
- The badge that does not clear on open coming to read as broken: then a
  popover in place of the Menu, which can say when it is shown, would be
  taken up again by a decision of its own.
- gglib refusing a closed id instead of dropping it: then stale picks would
  need pruning against the offer, which this rules out today.
