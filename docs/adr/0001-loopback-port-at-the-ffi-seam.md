# ADR 0001 — A loopback port, not a request API, at the ffi seam

- **Status:** Accepted
- **Date:** 2026-09-06 (amended 2026-09-07 — the risk is the wrong shape and
  the reading cannot see it; see the notes in "Context" and "Kill criteria")
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

modelpipe's `connect` hands back a `ConnectHandle` whose `base_url()` is a
loopback address, `http://127.0.0.1:<port>/v1`. A future `modelpipe-ffi`
could expose that same shape to Swift, or it could expose a request API
(`send(request) -> stream of bytes`) and never open a local socket.

The app needs one chat path. If the seam is a base URL, the chat path is the
unchanged `OpenAICompatibleProvider` over URLSession, and a pipe provider is
literally `OpenAICompatibleProvider(baseURL: session.baseURL, apiKey: token)`.
If the seam is a request API, the app carries a second transport, and every
behaviour URLSession gives for free (backgrounding, cancellation, timeouts,
HTTP semantics) has to be rebuilt above the ffi.

~~The risk of a loopback port is iOS: when the app is suspended the listener
inside the ffi is suspended with it, and a request issued on resume may hit a
socket that is not yet accepting. That failure shows up as a transport error
immediately after foregrounding.~~

> **Amended 2026-09-07 — there is no "not yet accepting" state to hit.** The
> seam this repo wrote down has no warm-up window. `docs/ffi-seam.md` #2 says
> `connect` returns once the listener is up rather than once the peer is
> reached, #3 says the base URL is stable for the life of the session, and #6
> says that after `shutdown()` it must refuse connections rather than hang. A
> port is therefore bound before any caller holds the session, and stays bound
> until the session ends. Between those two moments there is nothing for a
> request to arrive too early for.
>
> That does not make the port free of risk on iOS; it makes the risk a
> different shape. A socket the system reclaims from a suspended process does
> not resolve itself on the next attempt — it is gone, and the answer is to
> dial again, not to retry. A paragraph that describes a transient is an
> argument for a delay or a retry; the failure it should have described is an
> argument for noticing the session is dead and redialling, which is a
> different piece of work and is not what this ADR costed.
>
> The two failures also look nothing alike in the code. Only a refused or
> dropped connection becomes `ProviderError.transport`
> (`OpenAICompatibleProvider.swift:69`, `+Streaming.swift:80` and `:95`); the
> far side being away while the pipe itself is up comes back as HTTP, which
> is what the note under "Kill criteria" is about.

## Decision

`PipeSession.baseURL` is a loopback URL. There is no pipe-specific chat code.
The seam is the two protocols in `Sources/GGChatCore/PipeConnector.swift`,
and `MockPipeConnector` implements them the way `ModelpipeConnector` will.

## Kill criteria

- ~~**Reading:** the count of `ProviderError.transport` failures that occur
  within five seconds of the app returning to the foreground, against the
  count of foreground resumes. Both are local counters in
  Settings › Diagnostics ("Transport errors after resume: N of M resumes"),
  kept by `Diagnostics` in `Sources/GGChatUI/Diagnostics.swift` and
  covered by `DiagnosticsTests`.~~

  > **Amended 2026-09-07 — the numerator excludes the failure this ADR is
  > about, and the denominator is not resumes.** Both counters exist and both
  > persist; neither reads what the criterion says it reads, and no choice of
  > window width fixes either.
  >
  > **The numerator.** `Diagnostics.recordStreamEnd` returns unless the error
  > is `.transport`:
  >
  > ```swift
  > guard case .transport? = error, let lastResume, now.timeIntervalSince(lastResume) < 5 else { return }
  > ```
  >
  > A pipe that is up while the far machine is away does not produce that.
  > `docs/ffi-seam.md` #7 says such a request returns modelpipe's JSON error
  > body — `tunnel_unavailable`, `bad_gateway` — with its documented status
  > code, and `OpenAICompatibleProvider.serverError` turns a non-2xx into
  > `ProviderError.server`; `ErrorTests.testServerErrorFromNonJSONBody` pins a
  > 502 to `.server(status: 502, code: nil, …)`. The exclusion is not an
  > oversight either: `DiagnosticsTests` passes a `.server` error one second
  > after a resume and asserts the count stays at one. So the reading is
  > blind, on purpose, to the way the peer being unreachable actually arrives.
  >
  > It is also blind to a resume whose symptom is a failed *dial* rather than
  > a failed stream. `recordStreamEnd` is called from one place,
  > `finish(_:finished:)` in `AppModel+Streaming.swift`. A `connectPipe` that throws goes to
  > `report(_:)`, which sets `lastError` and logs — it touches no counter.
  >
  > **The denominator.** `recordResume` is called from `didBecomeActive()`,
  > which `RootView` invokes on every `scenePhase` transition to `.active`.
  > `.active` is reached from `.inactive` as well as from `.background`, so
  > dismissing Control Center or the notification shade, and dismissing a call
  > banner, each add one to M without the app ever having been suspended. On
  > macOS the same scene phase follows window activation, so clicking back
  > into the window counts too. M is "times the scene became active", which is
  > a larger and differently-shaped number than "foreground resumes".
  >
  > **What would have to change to make this readable**, none of which is done
  > here: count `.server` with `bad_gateway`/`tunnel_unavailable` alongside
  > `.transport`, or count where-to-look `.connectingSide` instead of a case;
  > count failed dials as well as failed streams; and take the denominator
  > from a `.background` → `.active` transition rather than any `.active`.

- ~~**Threshold:** if resume failures exceed one in ten over a month of daily
  use on a real pipe, revisit this decision and cost a request API.~~

  > **Amended 2026-09-07.** One in ten of a denominator that counts Control
  > Center is not the ratio this threshold was written for, and the numerator
  > it would be divided into cannot rise for the reason the ADR cares about.
  > Until the reading above is fixed, a low ratio here is not evidence that
  > the loopback port is working — only that nothing was streaming and failing
  > with a dropped connection in the five seconds after the scene last became
  > active.

- Zeros are recorded with their denominator: "0 of 212 resumes".

  > **Amended 2026-09-07.** Worth keeping, and worth reading narrowly: with
  > the numerator as it stands a zero is close to guaranteed, so it says
  > almost nothing about the decision.
