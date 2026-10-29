# ADR 0015 — The engine on this iPhone runs in the foreground only

- **Status:** Accepted
- **Date:** 2026-10-29
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

This phone is to run models itself, with gglib's engine in the app's own
process: gglib's proxy and its engine serve at a loopback port of their own
(ADR 0001), and a model's weights are read from a file under Application
Support. A model worth talking to takes one to a few gigabytes, a large
share of what iOS lets one app hold.

iOS does two things to an app in the background that a resident model runs
into. Under memory pressure it ends suspended apps without telling them,
the largest first, and an app holding a model is the largest there is, so
holding one through the background makes ggchat the first to go. And it
does not let an app in the background submit work to the GPU: Metal fails a
command buffer committed from there, so a decode cannot carry on anyway.
Nothing asks for a model while the app is away: every reply is already put
down on the way out (ADR 0002, ADR 0012), and every pipe hung up, for
TN2277's reason.

The engine as first added, with This iPhone, stayed up once served, through
the background, until its provider was removed; and a send that found it
not serving was refused with a sentence.

## Decision

**The engine on this iPhone runs only while ggchat is in the foreground. It
is served when a conversation on This iPhone opens or a send needs it, it
loads a model within the first request that names one, and it is put down
on the way to the background.**

- **Served when wanted.** Opening a conversation on This iPhone serves the
  engine: gglib's proxy at a port of its own, with a key of its own, and no
  model. The first request that names a model loads it; gglib holds the
  request until it has, and the reply streams after. Each serve reads this
  device's memory afresh, and the engine keeps that reading for as long as
  it serves, so every model it admits is fitted to one budget.
- **A send waits for it.** A send, Retry or Continue through This iPhone
  while the engine is not serving waits for it, as a send through a pipe
  waits for its pipe (ADR 0006): the wait serves the engine once, joining a
  serve already under way, and a serve that is refused puts the engine's
  sentence under the question rather than in an alert. Meanwhile the reply
  reads "Waiting for This iPhone to start its engine", with Stop.
- **Put down on the way out.** The background pass puts every reply down
  and waits for each, keeping what had arrived with Continue (ADR 0002,
  ADR 0012), and only then shuts the engine down, inside the same
  background assertion: the model is freed and both of its ports closed. A
  serve that lands after a shutdown has begun, or while the app is away,
  takes its own session down, since nothing else would; a generation stamp
  that every shutdown moves on, and the away flag, tell it so. If the app
  has come back before the pass reaches the engine, the engine is left up.
- **Coming back starts nothing.** The next opening of a conversation on
  This iPhone, or the next send, serves it again, and the next request
  loads the model again.
- **A memory warning** puts the engine down while no reply is going through
  it.
- **The pill says it.** The status pill beside the model, the slot a pipe's
  status has, says for This iPhone how the conversation's model is, with a
  memory chip: "Not loaded", "Loading 40%", "Ready", "Load again" once the
  engine could not load it, or "Too big" once the engine refused it as too
  big for this iPhone. Load again puts the engine down and serves it
  afresh, as Reconnect dials a pipe again, and asks the question again when
  it has no answer, which loads the model. Too big opens the model browser.
  The engine holds one model, so another model loaded reads as this one
  not loaded. Too big is learnt from the refusal and kept by model until
  the engine is next served, with the memory read again.

Nothing is stored. Downloads to this iPhone already pause on the way out
and resume on the way back.

## Known costs

- Every return pays a serve and a model load before the first token:
  seconds for a model of a few gigabytes, and the same after a two-second
  trip to another app.
- A reply in flight when ggchat leaves is cut short, as one through a pipe
  is, and carried on with Continue.
- Too big shows only once a question has been refused, and then for every
  conversation on that model until the next serve.

## What would undo it

- **Reading:** the lines ggchat logs as the engine loads a model, under the
  subsystem `com.mattogrady.ggchat` and the category `app`: "engine loading
  <model>" and then "engine ready with <model>, context <n>". They are
  info lines, which the phone keeps in memory only, so they are read live:
  the phone streamed in Console on a Mac, with Action › Include Info
  Messages on, while it is used. The time between the two after each
  return to the foreground, over the returns that sent something, is what
  a return costs. If that wait is what the owner notices most, the engine
  is kept through a short background instead, once the memory it holds
  there has been measured on the phone.
- **Reading:** the JetsamEvent reports the phone keeps (Settings › Privacy &
  Security › Analytics & Improvements › Analytics Data, `JetsamEvent-*`),
  which name each process the system ended for memory and the state it was
  in. One naming ggchat while in the background means the shutdown did not
  finish within the background grace: then the engine is put down earlier,
  at `.inactive`.
- **Reading:** an "engine could not load" line, or a reply's failure,
  saying Metal refused work from the background: then a decode is
  abandoned at `.inactive`, before `.background`.
- iOS offering an app a sanctioned way to keep GPU work and a large resident
  footprint through the background: then this is decided again.
