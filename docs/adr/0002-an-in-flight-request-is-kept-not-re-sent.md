# ADR 0002 — An in-flight request on reconnect is kept, not re-sent

- **Status:** Accepted
- **Date:** 2026-09-06 (amended 2026-09-07 — the decision stands; what its
  counters count is not "a reply was interrupted", see "Kill criteria";
  amended 2026-09-13 — a request refused before anything arrived has no
  partial to keep, so the question gets a Retry, see "Decision"; amended
  2026-09-29 — the background detaches from a run, it does not cancel it,
  see "Decision")
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

A pipe can drop mid-reply: the serving machine sleeps, the phone changes
network, the relay path is renegotiated. ~~`PipeStatus` walks to `closed` and
back.~~ The half-reply on screen is the user's; what happens to it is a
product decision, not a transport one.

> **Amended 2026-09-07 — not for the first of those three.** `closed` is
> what the ffi reports when the session itself ends. A serving machine that
> goes to sleep does not end the session: by `docs/ffi-seam.md` #7 a pipe
> that is up while the far side is not answers requests with modelpipe's HTTP
> error body, so that drop arrives as a `ProviderError.server` on the reply
> with the pill still reading "Direct" and no status transition at all.
>
> The product decision below is unaffected — a half-reply is a half-reply
> however it stopped, and the transcript treats all of them alike. The
> reading in "Kill criteria" is not: it counts a write of `.closed`, so it
> counts the causes that leave one and not the causes that leave none. A
> serving machine that goes to sleep leaves none.

Options considered:

1. **Re-send automatically.** Repeat the request on reconnect and replace
   the partial reply. Costs a second generation, and a reasoning model may
   take a different path, so the user watches their answer change.
2. **Keep the partial, offer Continue.** The partial reply stays on screen,
   marked partial. Continue re-sends the conversation with the partial
   assistant text as the last message, and the model carries on from it.
3. **Discard.** Drop the partial and show the error alone.

## Decision

Option 2. `Message.isPartial` is set when a stream ends with an error or is
stopped by the user, the transcript shows the text with a Continue button,
and nothing is sent until the user presses it. gglib's error sentences are
shown verbatim beneath the partial text, with the `WhereToLook` hint as a
second line. (A reply to gglib is not ended by a background or a dropped
connection since 2026-09-29; see the amendment of that date below.)

> **Amended 2026-09-13 — when nothing arrived, the question gets a Retry.**
> A request refused before its first token leaves no partial for Continue
> to sit under, and through 0.2.3 it drew nothing at all:
> `finish(_:finished:)` appended no message, and the sentence was kept only
> in memory, handed to a last message that was the user's own and so never
> drawn (ggchat #72). The failure is now kept on the message that ended the
> turn, the question when nothing arrived and the partial when some of it
> did, so it is drawn and it outlives a relaunch. An unanswered question,
> the last message with nothing under it, has a Retry, which sends the same
> conversation again and adds no second copy of the question. The second line under either is the code's own
> sentence where it has one, `invalid_api_key` so far, and the
> `WhereToLook` hint otherwise.
>
> This is not option 1. Nothing is sent until the user presses Retry, and
> there is no generation to replace, so nothing the user was reading can
> change under them. Retry is deliberately not counted in K. K asks whether
> a half-reply is worth resuming; Retry answers a different question,
> whether an unanswered question is worth asking again. If that ever needs
> a reading, it is a counter of its own beside K, not an addition to it. A
> stop or a background before the first token is still not a failure: the
> question keeps its Retry, and no sentence. (A background before the first
> token of a run leaves the run's placeholder instead, since 2026-09-29.)

> **Amended 2026-09-29 — the background detaches from a run; it does not
> cancel it.** A reply to gglib, a pipe or a server that answered the status
> probe, is now a run the hub owns: `PUT runs/{id}` with an id minted on the
> phone. Going to the background, or a connection dropping while the app is in
> front, stops reading and leaves the run going. What has arrived is written
> with the run's id and the number of the last event read, an empty reply
> included, and coming back, a launch or the pipe coming up reads on after that
> number, so no event is applied twice or skipped. Only Stop, or deleting the
> conversation or its provider, cancels the run. While the hub is still writing
> it the reply offers neither Continue nor Retry, either of which would start a
> second reply beside it, and says it is still being written on that machine.
> It ends as the run did: whole, with the run's failure, or stopped. When the
> hub no longer has the run the partial stays with Continue and a sentence
> saying so, which is option 2 again. A hub with no runs route is sent the
> request as before, and is not asked again while the app runs.
>
> This is still not option 1: nothing is sent twice, and the text on screen
> only grows. N still counts the close a background makes mid-reply. K cannot
> follow it, because no Continue is offered on a reply still being written.

## Kill criteria

- ~~**Reading:** two local counters in Settings › Diagnostics: "Pipe closed
  mid-reply: N of M closes" and "Continue pressed: K times", kept by
  `Diagnostics` and covered by `DiagnosticsTests` and
  `AppModelPipeTests.testForceClosedIsCountedAndReconnectDialsAgain`.~~

  > **Amended 2026-09-07 — N and M count the closes the app shows, and K
  > counts something wider than N.** The counters are real and persist
  > correctly. What they are counting is not "a reply was interrupted".
  >
  > **What N and M count is a pill going up, not a reply stopping.**
  > `Diagnostics.recordClosed` is called from one place,
  > `AppModel+Pipe.setPipeStatus(_:for:cutShort:)` — the only writer of
  > `pipeStatuses`, kept the only one by a gate,
  > `scripts/check_one_status_writer.sh` — and only when the status being
  > written is `.closed` and the one it replaces was not. So a close is
  > counted wherever the app puts a Closed pill up: from the session's status
  > stream, from a dial that came back refused, and from the hang-up on the
  > way to the background. The `previous != .closed` test is what makes it
  > once rather than twice — a background straight after a refused dial finds
  > the pill already up and adds nothing, which is deliberate and pinned by
  > `AppModelFailedDialTests.testABackgroundAfterARefusedDialAddsNoSecondClose`.
  >
  > What it does not count:
  >
  > - *The far machine goes away while the pipe stays up.* By
  >   `docs/ffi-seam.md` #7 that is an HTTP error on the request, not a status
  >   change, so the stream ends with a `ProviderError` and the status stays
  >   `direct`. `finish(_:finished:)` marks the message partial and the
  >   transcript offers Continue — the decision works — and N does not move.
  > - *A teardown that shows nothing.*
  >   `disconnectPipe(for:leaving:cutShort:)` counts what it leaves on the
  >   screen, so a hang-up that leaves no pill leaves no close: deleting a
  >   provider, and the disconnect half of a `reconnectPipe`.
  >   `closedTransitions` is 0 after either, pinned by
  >   `AppModelPipeTests.testAHangUpThatLeavesNoPillIsNotCountedAsAClose`.
  >   That exclusion is deliberate — the user asked for both, and neither
  >   interrupted a reply — but it is what M is.
  >
  > So `M` is "closes the app showed", not "sessions that ended", and `N` is
  > the subset of those that landed on a reply in flight.
  >
  > **K is not a subset of N.** `recordContinue` fires on the Continue button,
  > which `MessageRow` shows for any last assistant message with
  > `isPartial` — set whenever a stream ends unfinished, including the
  > server-error and user-stopped cases N cannot see. A ratio of K to N is
  > therefore not "how often a close was followed by a Continue"; K can exceed
  > N without either counter being wrong.
  >
  > **A suspension mid-reply is counted, and N does not say it was one.** It
  > used to be recorded nowhere: `RootView` acted on `scenePhase == .active`
  > and on nothing else, so a process suspended while streaming lost the
  > partial text outright. It acts on `.background` now.
  > `AppModel.didEnterBackground()` (since 2026-09-16 the hang-up pass of
  > `scene(_:)`; since 2026-09-29 it stops reading a run rather than
  > cancelling it, and the transcript offers no Continue until the run ends,
  > see "Decision") cancels the reply and awaits it before it
  > hangs anything up, so `finish(_:finished:)` writes the partial into the
  > conversation with `isPartial` set and the transcript offers Continue; the
  > hang-up then leaves `.closed` behind rather than nothing, which puts it
  > through `setPipeStatus(_:for:cutShort:)`, and `cutShort` is read before
  > the reply is put down. The case this ADR most wants to know about is now
  > the one it sees best: partial, Continue button, and — when the reply was
  > going over a pipe — a close in both N and M.
  >
  > Only once some of the reply has arrived, though (a run keeps an empty
  > placeholder, since 2026-09-29). `finish(_:finished:)`
  > appends nothing for an empty one, and Continue needs a message to sit
  > under, so a background before the first token leaves neither. `cutShort`
  > is read from `streamingProviderID`, which is set as soon as the reply is
  > live, so N and M move for that one anyway — a mid-reply close with no
  > reply to show and nothing for K to answer with.
  >
  > What it cannot see is which close that was. `recordClosed` takes one
  > flag, `whileStreaming`, so a background that cut a reply short and a
  > session that ended under one are the same event to N — and on a phone the
  > first is the commoner by a distance. They are not the same question:
  > whether a user comes back to a reply they walked away from is not whether
  > a user resumes one the far machine's session ended under. The threshold
  > below divides K by an N that mixes them.

- ~~**Threshold:** if, over a month, Continue is pressed after fewer than half
  of mid-stream closes, the button is not earning its place: users are
  re-asking instead. Revisit option 1 with an opt-in.~~

  > **Amended 2026-09-07.** K ÷ N is not that fraction, for the reason above:
  > the two counters have different populations, and a phone can produce a
  > Continue press with N still at zero. Read as written the threshold would
  > declare the button unearned on a month where it worked every time, or
  > divide by zero. It needs one event — "a reply stopped before it finished"
  > — counted once, wherever `isPartial` is set, with the presses measured
  > against that. Recording it is not done here.

- If Continue produces a reply that visibly restarts rather than continues
  on the models in use, record the model id alongside the press.
