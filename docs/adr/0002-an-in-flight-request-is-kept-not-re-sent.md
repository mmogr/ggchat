# ADR 0002 — An in-flight request on reconnect is kept, not re-sent

- **Status:** Accepted
- **Date:** 2026-09-06
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

A pipe can drop mid-reply: the serving machine sleeps, the phone changes
network, the relay path is renegotiated. `PipeStatus` walks to `closed` and
back. The half-reply on screen is the user's; what happens to it is a
product decision, not a transport one.

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

- **Reading:** two local counters in Settings › Diagnostics: "Pipe closed
  mid-reply: N of M closes" and "Continue pressed: K times", kept by
  `Diagnostics` and covered by `DiagnosticsTests` and
  `AppModelPipeTests.testForceClosedIsCountedAndReconnectDialsAgain`.
- **Threshold:** if, over a month, Continue is pressed after fewer than half
  of mid-stream closes, the button is not earning its place: users are
  re-asking instead. Revisit option 1 with an opt-in.
- If Continue produces a reply that visibly restarts rather than continues
  on the models in use, record the model id alongside the press.
