# ADR 0011 — A picture is asked for with a switch, and a kept conversation keeps its own

- **Status:** Accepted
- **Date:** 2026-10-10 (amended 2026-10-11 — a chat chooses the image model
  its pictures are drawn with; amended 2026-10-12 — a drawn picture is fixed
  or drawn again; see the notes at the end of the decision; amended
  2026-10-26 — `tools=builtin` is gone, see ADR 0014)
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

> **Amended 2026-10-26 — `builtin` is gone.** A run now names, by id, the
> paired Mac's servers its conversation picked, `tools=3,7&draw=true`, or
> `tools=none&draw=true` with none picked, which leaves it the drawing tool
> alone; see [ADR 0014](0014-each-conversation-picks-which-of-the-macs-servers-it-uses.md).

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
code goes on the question, as any run's failure does; when the run reported
an error of its own first, that sentence goes there instead, with no code.

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

> **Amended 2026-10-11 — a chat chooses its image model, and says it with
> every message that draws.** gglib's answer about drawing now lists the
> machine's image models (`models`: id, name, family, whether complete and
> what is missing, the default, the one loaded), and a message that draws
> can name one: `image_model` beside `draw` in a Mac's turn, and
> `&image_model=<id>` in the query of a run for a conversation kept here.
> Absent means gglib's own rule, its default or else its only complete
> model. gglib keeps no such choice for a chat, on purpose, so the surface
> that sends the message remembers it.
>
> Pressing Draw is still per message. Which model draws is a setting of the
> chat, as Thinking is, because a chat is usually about one kind of picture
> and picking again for every one would be a chore. Where the Mac lists two
> image models or more, holding the Draw control opens them: "Default",
> naming the model the Mac's rule picks, then each in the Mac's order with
> its family, "loaded" for the one loaded now, and one that lacks a file
> dimmed with what it lacks. Picking one also presses Draw for the message
> being written, since that is what was just asked for, and sends nothing.
> With one image model or none the control is the switch it was.
>
> A conversation kept here stores the choice in one optional column
> (`imageModelID`) and a branch keeps it, as it keeps the Thinking choice.
> An id names a model on one machine, so a provider moved to another Mac
> takes the choice of each of its conversations with it. A Mac's chat holds
> the choice in memory with the chat open and nowhere else (ADR 0007), so a
> chat opened again has none: the Mac does not remember it for the phone, as
> it does Thinking.
>
> The word is sent only to a gglib whose answer carried `models`. One from
> before the list has no menu and is never sent it, since it refuses a turn
> with a key it does not know; a choice held from before is then not said,
> and its own rule draws.
>
> A chosen model the Mac cannot draw with is never swapped for another. The
> Mac is asked about a message that names the model chosen
> (`?image_model=<id>`), when it is picked and each time the Mac is asked
> about drawing, for the chat on screen; until it answers, its list is read.
> When either says no, the control is dimmed with the reason and the menu
> stays, the choice as it was. When the Mac refuses the message itself, with
> `model_not_found`, `not_an_image_model` or `image_model_incomplete`, the
> question keeps the refusal and stays one that draws, the draft of a Mac's
> chat comes back with Draw as it was, the choice is kept, and the Mac is
> asked again what it lists. Retry then names the same model. This is the
> one place a question marked as drawing is sent to a Mac this phone thinks
> will refuse: the other way is a picture from a model nobody chose.
>
> Known costs. The answer about a chosen model is as old as the last ask, as
> the list is. A Mac's chat forgets its choice when it is closed. A choice
> the list no longer has ticks no row in the menu. The menu is opened by
> holding the control, which nothing on screen says; VoiceOver is told.

> **Amended 2026-10-11 — a conversation kept here remembers how its picture
> was made.** The reply a run drew for was kept as its closing words and its
> picture, and sent back as the words alone, so on the next message the
> model read a chat in which nothing had been drawn and was apt to say it
> cannot make images (gglib issue 1387). The reply now also keeps each tool
> the run called and what it answered (the call's id, the tool's name, the
> arguments as JSON text, the answer word for word) in one optional column,
> `exchangesData`, and every later request says them ahead of the reply's
> words as an assistant `tool_calls` message and a `tool` message. gglib
> reads a call of `builtin:generate_image` answered "Drew …" as a chat that
> holds a drawn picture and adds its own note for the model; this phone
> writes no such note and only says what happened.
>
> They are sent to gglib alone, by the test that already decides what only
> gglib is sent (a paired Mac, or an address that answered the status
> probe). Any other server is sent the words alone, as before. Nothing new
> is drawn: the calls are a field of the reply, not messages of their own,
> so the transcript, the branching rules and the branch points read the
> rows they always did, and a branch's copy carries them as it carries the
> picture. The picture is still never sent to the model.
>
> Known costs. A reply drawn before this keeps no call, so its chat is sent
> as it was and the model may still deny the picture there. Words the model
> wrote before its call and after it are one text here, and all of it is
> sent after the tool's answer. The arguments are written again from the
> event's JSON with their keys sorted, so they are the model's values and
> not its bytes. A run that draws offers gglib's other tools too, and any
> it called is kept and sent the same way, however long its answer.

> **Amended 2026-10-12 — a Mac with no default asks which model, and the
> composer names the one that draws.** A Mac with several image models and no
> default refuses a message that names none. The control was dimmed, a
> press showed gglib's sentence with a command to type on the Mac, and the
> models were behind a hold nothing on screen mentioned.
>
> The control now asks. Where the Mac cannot draw, marks no default, lists
> two or more image models with all their files and the chat has chosen
> none, the control is not dimmed and a press opens the menu; the menu has
> no "Default" row, which would name nothing. Everywhere else a press is
> the switch and a hold the menu, as before. While Draw is on, a line over
> the field says "Drawing with" and the model's name: the one chosen, or
> the one the Mac said draws.
>
> A model picked on such a Mac can draw at once: until the Mac answers
> about it the list is read, and the list has it with all its files. The Mac's refusal was for want of a choice, which it now has.
>
> Known costs. gglib gives this refusal the code of every other, so it is
> read from the list. A Mac that lacks something else as well, an image
> runtime say, still opens the menu, and says what it lacks once it is
> asked about the model picked, or refuses the message. Not run on a device or a simulator.

> **Amended 2026-10-12 — a drawn picture is fixed or drawn again from
> itself, and joins its chat only on Keep.** gglib's `POST
> /v1/images/generations` now reads a picture to start from, a mask and a
> strength (gglib's ADR 0018, decision 20), and keeps a stored picture beside
> the one it was made from, on the same tool row (decision 21). A picture the
> drawing tool made, opened whole, has Fix or redo under it. Fix sends the
> picture and a mask of what was brushed, and Redo the picture alone; both
> send the words the picture was drawn from, as edited, and a strength.
>
> The phone draws, then keeps, as gglib's chat page does. The request knows
> nothing of chats. The result is held by the editor, in memory, until a
> person presses Keep; Discard, Try again and Stop store nothing anywhere. A
> Mac's chat then sends the picture to the Mac's store, as a turn's image is
> sent, and names it and its source to `POST /v1/chats/{id}/pictures`; the
> chat is read again, and nothing of it is written here (ADR 0007). A
> conversation kept here keeps the bytes in this device's store and names
> the picture on the same reply, after the pictures the reply has, with no
> new column: a reply's pictures were already a list.
>
> The mask is made from strokes kept in the picture's own pixels, painted on
> opaque black at the picture's own size, since gglib reads a mask's colour
> and not its alpha. The same strokes are what a person sees over the
> picture.
>
> Which picture the drawing tool made is read, not guessed. A Mac's chat
> reads it from its rows: a tool's row names the call it answers, and the
> reply's row before it the call's name and `prompt`. A conversation kept
> here reads it from the calls its reply keeps, and offers Fix or redo only
> where the reply holds exactly one call that drew. Only a PNG is offered
> it, in either chat, since gglib refuses any other picture.
>
> The editor is held by the app and shown from its root, not by the row
> that opened it, and it holds the picture's bytes from the moment it opens.
> The Mac is looked up each time it is asked to draw, store or link, never
> once at opening: the background hangs every pipe up, and the pipe dialled
> again answers at another address. While a render is under way an iPhone
> or iPad is kept from locking, since a lock sends the app to the
> background and the render's reader with it.
>
> Where this parts from gglib's chat page as first written: a Keep that
> fails leaves the drawn picture in the editor to be kept again, and the
> sheet cannot be dismissed while a render, a result or a Keep is in hand.
> A render takes minutes, and neither a lost answer nor a swipe should cost
> one. The image model starts at the chat's own choice; on a Mac with
> several image models and no default the editor asks for one first, as the
> Draw control does.
>
> Known costs. A conversation kept here does not record which call made
> which picture, so a reply with two calls that drew offers no Fix or redo,
> and a reply with one call that drew offers it on every PNG the reply
> holds, another tool's included. A reply drawn before the phone kept its
> calls offers none. A kept picture carries its source's words, not the
> words it was itself drawn from. The picture travels to the Mac as base64
> inside the request, whole, each time it is drawn again. A Mac whose gglib
> is from before this refuses the request in its own words, and nothing
> says so before it is asked. A render under way when the app goes to the
> background is not read on: the editor says the Mac is unreachable, and
> the picture is asked for again. A drawn picture not yet kept is held in
> memory and is gone if the app is.

## What would undo it

- gglib remembering a chat's image model, as it does Thinking: then a Mac's
  chat reads the choice from the opened chat and says it only on the turn
  that changes it, and the phone holds nothing between openings.

- The owner wanting pictures without a press: then gglib's rule changes
  first, and the switch becomes a setting of the chat, as Thinking is.
- gglib keeping a chat run's pictures for as long as the device that asked
  for them: then the bytes need not be copied here, and a kept reply's
  picture is read from the hub by id, as a Mac's chat's are.
- A look that needs to outlive the reply being written, say to show a
  picture that failed part-way: then a frame is kept, and gglib's rule that
  a preview is never stored is reopened with it.

> **Amended 2026-10-19 — the image model is chosen on the line over the
> field, not by holding Draw.** The menu of image models was behind a hold
> on the Draw control, which nothing on screen said, and which VoiceOver
> and Switch Control reach badly. Holding also made one control do two
> jobs with two lifetimes: a press was the message's, a hold the chat's.
>
> Draw is now the switch and nothing more. The line over the field, which
> already named the model while Draw was on, is the menu: "Drawing with
> flux" with a chevron, and the rows as before. Picking one sets the chat's
> choice and sends nothing; it no longer presses Draw, since the line is
> there only while Draw is on. Where the Mac lists several models and no
> default, pressing Draw turns it on as ever and the line reads "Choose an
> image model" until one is picked; a message sent before then is refused
> as it was. Where the chat's choice is one the Mac cannot draw with, the
> line says "Cannot draw with" and the model's name whatever Draw shows,
> so the menu is still there to pick another from, and the switch is
> dimmed with the reason as before. The picture editor's "Drawn with" menu
> was already this shape; the composer now matches it.
>
> Kill criterion: a chat whose Mac lists several image models and whose
> composer shows no way to pick one while Draw is on, read from the
> `draws-with` element in a UI walk.
