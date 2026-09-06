# ADR 0002 — An in-flight request on reconnect is kept, not re-sent

- **Status:** Accepted
- **Date:** 2026-09-06 (amended 2026-09-07 — the decision stands; both of its
  counters miss the case it was written for, see "Kill criteria")
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
> reading in "Kill criteria" is not: it counts the status transition, so it
> counts one of these causes and not the others.

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
second line.

## Kill criteria

- ~~**Reading:** two local counters in Settings › Diagnostics: "Pipe closed
  mid-reply: N of M closes" and "Continue pressed: K times", kept by
  `Diagnostics` and covered by `DiagnosticsTests` and
  `AppModelPipeTests.testForceClosedIsCountedAndReconnectDialsAgain`.~~

  > **Amended 2026-09-07 — N and M count one narrow event, and K counts
  > something wider than N.** The counters are real and persist correctly.
  > What they are counting is not "a reply was interrupted".
  >
  > **N and M see only an observed `closed` transition.**
  > `Diagnostics.recordClosed` is called from one place,
  > `AppModel+Pipe.observe(_:for:)`, and only when a value arriving on the
  > session's status stream is `.closed` and the previous one was not. Two
  > common ways a reply stops therefore never reach it:
  >
  > - *The far machine goes away while the pipe stays up.* By
  >   `docs/ffi-seam.md` #7 that is an HTTP error on the request, not a status
  >   change, so the stream ends with a `ProviderError` and the status stays
  >   `direct`. `finish(_:finished:)` marks the message partial and the
  >   transcript offers Continue — the decision works — and N does not move.
  > - *A deliberate teardown.* `disconnectPipe(for:)` cancels
  >   `statusTasks[providerID]` **before** awaiting `session.shutdown()`, and
  >   `MockPipeSession.shutdown()` sends `.closed` and then finishes the
  >   stream. The value is emitted into a stream nobody is reading any more.
  >   Measured against the mock: `closedTransitions` is 0 after
  >   `disconnectPipe`, and still 0 after a `reconnectPipe`, which is a
  >   disconnect and a dial.
  >   `AppModelPipeTests.testForceClosedIsCountedAndReconnectDialsAgain` does
  >   not catch this — it asserts N is 1 after `forceClosed()` and then
  >   reconnects without asserting N again.
  >
  > So `M` is "closes the app watched arrive", not "closes", and `N` is the
  > subset of those seen while a reply streamed. That is the mock's
  > `forceClosed()`, and whatever a real ffi reports for a session that ends
  > under it.
  >
  > **K is not a subset of N.** `recordContinue` fires on the Continue button,
  > which `MessageRow` shows for any last assistant message with
  > `isPartial` — set whenever a stream ends unfinished, including the
  > server-error and user-stopped cases N cannot see. A ratio of K to N is
  > therefore not "how often a close was followed by a Continue"; K can exceed
  > N without either counter being wrong.
  >
  > **And a suspension mid-reply is recorded nowhere.** `LiveReply` is
  > in-memory state on `AppModel`, and the only path that writes it into a
  > conversation is `finish(_:finished:)` at the end of the stream. `RootView`
  > acts on `scenePhase == .active` and on nothing else, so a process
  > suspended while streaming loses the partial text outright: no partial
  > message, no Continue button, no counter. On a phone that is the case this
  > ADR most wants to know about.

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
