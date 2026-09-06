# ADR 0001 — A loopback port, not a request API, at the ffi seam

- **Status:** Accepted
- **Date:** 2026-09-06
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

The risk of a loopback port is iOS: when the app is suspended the listener
inside the ffi is suspended with it, and a request issued on resume may hit a
socket that is not yet accepting. That failure shows up as a transport error
immediately after foregrounding.

## Decision

`PipeSession.baseURL` is a loopback URL. There is no pipe-specific chat code.
The seam is the two protocols in `Sources/GGChatCore/PipeConnector.swift`,
and `MockPipeConnector` implements them the way `ModelpipeConnector` will.

## Kill criteria

- **Reading:** the count of `ProviderError.transport` failures that occur
  within five seconds of the app returning to the foreground, against the
  count of foreground resumes. Both are local counters in
  Settings › Diagnostics (arrives with the pipe flow; recorded from the
  first build that has a pipe).
- **Threshold:** if resume failures exceed one in ten over a month of daily
  use on a real pipe, revisit this decision and cost a request API.
- Zeros are recorded with their denominator: "0 of 212 resumes".
