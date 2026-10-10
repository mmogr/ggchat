# ADR 0011 — A picture is asked for with a switch, and a kept conversation keeps its own

- **Status:** Accepted
- **Date:** 2026-10-10
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

gglib draws. It runs an image model on the machine it is on, through
stable-diffusion.cpp, and offers the chat's model one tool for it,
`generate_image`. The chat model writes the prompt, calls the tool and says
what it drew. gglib's ADR 0016 says how a tool's image is kept there.

Four things in gglib's design decide what this app does.

A picture is never started by a model on its own. gglib offers the tool only
for a message that says `draw: true`, and the owner's rule is that a person
switches that on for one message. Without it the tool is in no tool list.

Whether a machine can draw is something it says: `GET /v1/images/drawing`
answers the image model that would draw, or a reason in words. A gglib from
before drawing has no such route, and refuses a turn that carries `draw` as
a key it does not know.

A picture takes a long time: about half a minute before the first sign, one
to two minutes for one family of models, about nine for another. gglib's
runs say how far it has got, as `tool_progress` and `waiting` events, and
send the latest look at the picture as a `preview` event that travels beside
the numbered events and is never logged.

And a conversation kept on this device can draw too. gglib takes a chat run
with its own tools, `PUT /v1/runs/{id}?kind=chat&tools=builtin&draw=true`,
whose body is the OpenAI request and whose events are an agent's. It keeps no
chat for such a run, so the picture it made is named by no chat of its own,
and it sweeps such an image at the daemon's next start once it is over a day
old. It starts such a run, and hands over its picture, only for a device it
has paired.

## Decision

**A picture is asked for with a Draw switch on the composer, pressed for one
message and off again once it is sent. A hub is asked whether it can draw and
is never sent the word when it cannot. What is shown while a picture is drawn
is held in memory and never kept. The picture a conversation kept here asked
for is read once and kept in this device's own store.**

The switch is the draft's (`Draft.draws`). The empty draft a send leaves has
it off, a draft the model refuses keeps it, and a draft a Mac gives back has
it as it was sent. It is not a setting of the chat, as Thinking is (ADR
0009), because the rule it serves is that each picture is asked for.

The hub is asked when a chat opens on it and each time its pipe comes up,
and only if it is a paired Mac. The answer is kept in memory, and forgotten
when the provider is moved to another Mac. A gglib reached by its address is
not asked: gglib would refuse it the run and the picture, so a conversation
on it has the switch dimmed, saying "Drawing needs a paired Mac." A hub that said it
can draw is sent `draw`; one that said it cannot, one that answered 404 and
one not heard from are sent the message without it. The switch is then
dimmed and stays off, and a press says the hub's reason: a phone has no
pointer to hover for it.

A Mac's chat says `draw: true` on the turn, beside the keys it already had,
and only then. Nothing about it is written here (ADR 0007).

A conversation kept here puts the run with the three words in its query and
its body unchanged. The run's answer says how its events are written
(`frames`), and that picks the decoder: `agent` is read with the decoder a
Mac's chat's run is read with, and absent is the chat route's chunks. Two
optional columns keep what a relaunch needs. `draws` on the question, so
Retry asks for the picture again while the hub can draw, and goes without,
unmarked, once it cannot. `runFrames` on a reply still being written, beside
its run's id and cursor, so a reply read on after the background uses the
decoder its run needs. Continue carries a partial reply on and never draws.
A question the hub refused to draw for, with `drawing_unavailable`, is
unmarked, so Retry does not ask the same hub the same thing. A run whose
answer names a way of writing events this build does not know is stopped and
given up with a sentence; its report still reads.

The picture such a run made is this device's, as the conversation is. Its
bytes are read from the hub by id when the tool finishes, before the frame
that names it is applied, checked against the id, and kept under the same
SHA-256 a question's image has (`ImageStore`). The reply's message names
it, and it goes with the last turn that names it, as a question's does. A
frame whose picture was lost on the way is not applied: the reply walks away
with its cursor at the frame before, and the next reading meets the frame
again. A picture the hub no longer has, or whose bytes are not its id's, is
named and not kept. A reply's picture is never sent back to the model: on
the wire a reply is its text.

Progress, a wait and the latest look are one value on the reply being
written (`ToolWork`), for both kinds of chat. A tool's progress and its look
go when that tool's call ends, a wait when anything else arrives, and all of
it when the run ends. The run reader reads a `preview` by its name, ahead of
the numbering: an event stream gives an event with no id the id of the one
before it, so read after the numbering it would be dropped as a frame
already read, and one that carried an id would move the cursor past frames
not yet read. The look is drawn from the frame as it came, larger and
smoothed.

gglib now starts a turn's run before it loads the model, so a refusal can
be how the run ends: failed, with `model_unavailable`, `unavailable` or
`conflict`, the three its own doc names (`hub_turn.rs`). For a Mac's chat,
a run that ends so, with nothing of a reply read, is a refused turn: the
draft goes back to the composer. `drawing_unavailable` and
`image_model_cannot_chat` are answers to the `PUT`, before any run; they
are taken the same way should a run ever end with one. For a conversation kept here the
code goes on the question, as any run's failure does.

gglib's model list names an image model with `image_generation`. It cannot
chat, and neither can one listed with `embeddings`: the model list offers
neither, and a provider with no model chosen takes the first that can chat.

Known costs. Whether a hub can draw is asked on opening and on its pipe
coming up, so an image model added or removed while a chat stays open is not
seen until one of those; the turn or the run is then refused with gglib's
own reason. A picture kept from a frame is in the store before the message
that names it is written, so it is left with no turn naming it when its
conversation is deleted in between, when the app is killed in between, and
when a frame names two pictures and the second is lost on the way: the first
is kept, and the frame is applied only on a later reading. gglib does not
read the request's sampling or max_tokens on such a run; the Thinking choice
is read. A provider whose saved default is an image model keeps it
until another is picked. And a run that draws for a conversation kept here
is read as agent events, which carry no "Reading N of M tokens" line.

## What would undo it

- The owner wanting pictures without a press: then gglib's rule changes
  first, and the switch becomes a setting of the chat, as Thinking is.
- gglib keeping a chat run's pictures for as long as the device that asked
  for them: then the bytes need not be copied here, and a kept reply's
  picture is read from the hub by id, as a Mac's chat's are.
- A look that needs to outlive the reply being written, say to show a
  picture that failed part-way: then a frame is kept, and gglib's rule that
  a preview is never stored is reopened with it.
