# What modelpipe-ffi must provide

ggchat stopped at a seam. This is that seam, stated as the two Swift
protocols the app compiles against, plus the behaviours the mock had and the
real thing had to match.

> **Amended 2026-09-09 — the seam is crossed, and one sentence below was
> wrong about how.** `ModelpipeConnector` does *not* replace both arms of the
> `#if DEBUG` in `Sources/GGChatUI/PipeConnectorFactory.swift`. It replaces
> the release arm; the mock stays in DEBUG. Following the original sentence
> literally would have stopped twenty-odd app-model tests compiling, along
> with the Settings screen's "Force closed" control, which downcasts to
> `MockPipeSession` and is the only way to exercise the reconnect UI by hand.
> A debug build that dialled for real would also need a machine serving a
> ticket before it could show a conversation at all.
>
> "Nothing above it changes" was also optimistic, and the way it was wrong is
> worth keeping. Six consumer paths did change, not because the seam moved but
> because a real dial reaches code a mock never did: it suspends, it can be
> cancelled, and it fails for reasons that are nobody's mistake. The list is in
> ggchat #52. The seam held; what had never been exercised was everything
> downstream of a dial that takes time and can go wrong.

The mock exists only on the debug side of that `#if`. `MockPipeConnector`
and `MockPipeSession` are themselves declared inside an `#if DEBUG` in
`Sources/GGChatCore/MockPipeConnector.swift`, so a release build contains
neither the types nor their symbols; `make build-release` compiles the
package in Release and fails if it finds either in the objects.

Everything below now describes behaviour a shipped build **has**.
`UnavailablePipeConnector` is still compiled, and still refuses, but nothing
returns it: it is the sentinel `scripts/check_no_mock_in_release.sh` looks for
to prove it really opened the release objects.

## The protocols (verbatim from `Sources/GGChatCore/PipeConnector.swift`)

```swift
public protocol PipeConnector: Sendable {
    func connect(ticket: String, token: String) async throws -> any PipeSession
}

public protocol PipeSession: Sendable {
    var baseURL: URL { get }                      // http://127.0.0.1:<port>/v1
    var status: AsyncStream<PipeStatus> { get }   // current value first, then changes
    var closeReason: PipeCloseReason? { get }     // nil while still open
    var readings: PipeReadings { get }            // the port, and the relay counters
    func notifyNetworkChange() async
    func shutdown() async
}

public enum PipeStatus: String { case idle, direct, relayed, closed }
```

> **Amended 2026-09-09 — `PipeSession` gained three members, and the heading
> above is not as true as it looks.** The pipe's own readings had nowhere to
> go: the binding exposes a close reason, a port and relay counters, and the
> seam stopped at a base URL and a status, so the app dropped all three.
>
> `PipeCloseReason` has **three** cases where the binding's `MpCloseReason`
> has two. modelpipe records a reason for a shutdown and for a failed
> listener; a pipe whose peer simply stopped answering ends with nothing
> recorded, and read straight off the binding that silence is
> indistinguishable from a pipe that is still open. `GGChatPipe` establishes
> that the sequence has ended and maps the remaining silence to
> `peerVanished` — the close a person most wants explained.
>
> The three are requirements rather than defaulted extras. A default here
> would let a session report a dead pipe as open with nothing failing.
>
> Two things the heading still gets wrong, left for the pass that closes
> issue #8: `PipeStatus` is quoted from `PipeConnector.swift` and does not
> live there — it is `Sources/GGChatCore/PipeStatus.swift`, and it has more
> conformances than shown — and `PipeConnectError`, which *does* live in the
> quoted file, is missing from this block entirely.

## Behaviours the app relies on

Each is what `MockPipeConnector` and `MockPipeSession` do today and what
`AppModelPipeTests` and `MockPipeTests` assert.

1. **`connect` validates before it dials.** A ticket whose shape fails
   `Ticket.validateShape` and an empty token are refused with
   `PipeConnectError`, whose cases are sentences. The ffi may add its own
   errors for a ticket that decodes badly; they must be `LocalizedError`
   with a sentence that names which side to look at.
2. **`connect` returns once the listener is up**, not once the peer is
   reached. The session starts at `idle`; the walk to `relayed` or
   `direct` happens afterwards and the app shows it on the status pill.
3. **`baseURL` is loopback, ends in `/v1`, and is stable for the life of
   the session.** The app builds `OpenAICompatibleProvider(baseURL:
   session.baseURL, apiKey: token)` and nothing else. See ADR 0001 for
   why this is a URL and not a request API, and — as amended 2026-09-07 —
   for why the reading that was to overturn it does not read that.
4. **`status` yields the current value first**, then every change, to
   every subscriber, however late it subscribes. Equal consecutive values
   may be delivered. The stream ends only after `shutdown()`.
5. **`closed` is recoverable by dialling again.** The app calls
   `shutdown()` on the old session and `connect` anew; the ffi must not
   require process restart. A `closed` that arrives while a reply streams is
   counted, as is a close the app writes itself (ADR 0002).
6. **`shutdown()` is idempotent and ends the status stream.** Calling it
   twice is fine. After it, the base URL must refuse connections rather
   than hang.
7. **Errors from the pipe arrive as HTTP.** When the pipe is up but the
   other side is not, requests to `baseURL` return modelpipe's JSON error
   body (`tunnel_unavailable`, `bad_gateway`, …) with the documented
   status codes. The app already maps every documented code to a
   where-to-look hint (`ProviderError.whereToLook(forCode:)`).
8. **No credential in any log line.** The ffi's logging, if it surfaces
   through the app's `LogSink`, must never include the ticket or the
   token. The app's redaction test greps for a distinctive token; extend
   it to the ffi's output when it lands.

## Pairing sits above the seam, not inside it

The first connection to a machine trades a six-digit code for that
machine's API key, and the route that does it (`POST /v1/remote/pair` on
gglib's proxy) is reachable only *through* the pipe. That did not become a
third parameter on `connect`. `PipePairing` builds the exchange out of the
two protocols above instead: `connect(ticket:token:)` with the code as the
token, a POST to `session.baseURL`, `shutdown()`, and the key handed back
to be stored and dialled with. So the ffi has nothing extra to implement
for pairing — and the token it is handed on a pairing dial is the code,
which modelpipe's `connect` ignores exactly as it ignores the token on
every other dial.

## Platform facts already in place

- `Info.plist` allows local networking only (`NSAllowsLocalNetworking`),
  which covers loopback. Nothing else is needed for the pipe's URL.
- iOS suspends the app, and with it the listener. ~~ADR 0001's reading
  counts transport errors within five seconds of a resume.~~

  > **Amended 2026-09-07 — do not build toward that reading.** ADR 0001's
  > kill criterion was struck on the same date and the counter behind it is
  > blind to the case it was written for. `Diagnostics.recordStreamEnd`
  > (`Sources/GGChatUI/Diagnostics.swift:37`) returns unless the error is
  > `ProviderError.transport`, and by #7 above a far side that is away
  > answers over a working pipe with modelpipe's HTTP error body, which
  > `OpenAICompatibleProvider.serverError` turns into `ProviderError.server`.
  > No window width fixes that. A zero on this counter is not evidence the
  > ffi is behaving under suspension; read ADR 0001's "Kill criteria" note
  > before treating it as a signal.
  >
  > What the seam does **not** yet say is what the ffi owes when the system
  > reclaims the listener from a suspended process. ADR 0001's amendment
  > argues such a session is dead rather than slow — the answer is to dial
  > again, not to retry — but nothing in this document obliges the ffi to
  > make the two distinguishable. The app's own counter cannot stand in: it
  > moves for a background whether or not the listener was reclaimed.
  > That is open work, named here so an implementer does not read the
  > struck criterion as the acceptance test.
- The Keychain holds the ticket and token under the provider's id; the
  config holds only a digest, used to count distinct tickets (the app's
  kill criterion, shown in Settings).

## What is out of scope until then

The hole-punching spike from a carrier NAT on a real iPhone belongs to
the ffi work, not this repo.

> **Amended 2026-09-09 — the binding is linked; the connector is not written.**
> `Sources/GGChatPipe` is a target of its own that depends on
> `modelpipe-ffi`, and `scripts/check_boundaries.sh` now permits
> `import Modelpipe` there and nowhere else, rather than banning it outright.
> What has not changed is what a build does with a ticket:
> `PipeConnectorFactory` still returns the mock in DEBUG and
> `UnavailablePipeConnector` everywhere else, so everything below still
> describes behaviour a shipped build does not have.
