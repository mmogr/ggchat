# ADR 0006 — A send through a pipe that is not connected waits for it

- **Status:** Accepted
- **Date:** 2026-09-29
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

The machine at home is often asleep while its owner is away. A send through
a pipe that was not connected was refused at once, "home is not connected
yet", and one through a pipe still looking went out and came back
`tunnel_unavailable`. Either way the question had to be asked again later.

## Decision

A send, Retry or Continue through a pipe that is not connected waits until it
reads direct or relayed, then streams. It joins a dial already in flight for
that provider, or starts one, once. The reply row reads "Waiting for home ·
last heard 08:12" with Stop. The wait ends when the pipe connects; when the
dial is refused, whose sentence goes on the question and not into an alert;
and on Stop, the background or the provider's removal, which leave Retry and
no failure, or on the conversation's deletion. There is no time limit. A dial
the wait started goes on after Stop, so the pipe is up for the next send.

Nothing is stored or counted. The wait lives in memory, as the reply in
flight does, and the time it shows is the last-heard time the pipe already
keeps. A close while a send waits is not a close mid-reply under ADR 0002.

## What would undo it

- Sends left waiting for hours on a machine that does not wake, with no one
  pressing Stop: then the wait gets a limit, or a send refuses again.
- A refusal from a dial the owner never started, a resume, landing on his
  question and confusing him: then a send joins only a dial it started.
- A pipe coming up after Stop that nobody wanted: then Stop calls off the
  dial the wait started.
