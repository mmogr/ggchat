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

## The protocols (from `Sources/GGChatCore/PipeConnector.swift` and `PipeStatus.swift`)

```swift
public protocol PipeConnector: Sendable {
    func connect(ticket: String, token: String) async throws -> any PipeSession
}

public protocol PipeSession: Sendable {
    var baseURL: URL { get }                      // http://127.0.0.1:<port>/v1
    var status: AsyncStream<PipeStatus> { get }   // current value first, then changes
    var closeReason: PipeCloseReason? { get }     // nil while still open
    var readings: PipeReadings { get }            // the port, and the relay counters
    func notifyNetworkChange() async              // the network under the device moved
    func shutdown() async
}

public enum PipeConnectError: Error, Sendable, Equatable, LocalizedError {
    case invalidTicket(message: String)           // refused before anything is dialled
    case missingToken                             // refused before anything is dialled
    case unavailable                              // nothing in this build can dial
    case dialFailed(message: String, retryable: Bool)
}

// PipeStatus.swift
public enum PipeStatus: String, Sendable, Codable, CaseIterable, Equatable {
    case idle, direct, relayed, closed
}
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
> Two things the heading got wrong were left for the pass that closes
> issue #8, and that pass was made on 2026-09-12. `PipeStatus` is now quoted
> from `PipeStatus.swift`, where it lives, with the conformances it has, and
> `PipeConnectError` is in the block.

## Behaviours the app relies on

Each is what `MockPipeConnector` and `MockPipeSession` do today and what
`AppModelPipeTests` and `MockPipeTests` assert.

1. **`connect` has modelpipe read the ticket before it dials.** The call is
   `mpReadPairing`, the same one the form reads what is typed with, and it
   is synchronous — one C call — so there is a per-keystroke answer as well
   as a per-dial one. A string it refuses, and a string that carries a
   pairing code, are refused with `PipeConnectError.invalidTicket`, whose
   payload is modelpipe's sentence rather than a reason this app named; an
   empty token is refused with `missingToken`. A code is spent through
   `pair`, which validates nothing here either: modelpipe reads the whole
   string, so one that is not a pairing string comes back as
   `MpPairError.BadPairingString` with its own sentence.

   Above the seam this is the `PairingReader` protocol in `GGChatCore`,
   implemented by `ModelpipePairingReader` in `GGChatPipe` and handed to
   `AppModel` by `PipeConnectorFactory` — the real one in every build,
   DEBUG included, because the mock stands in for the far machine and not
   for modelpipe's parser. `MockPipeConnector`, which cannot call the
   binding from `GGChatCore`, therefore reads no tickets at all: it refuses
   a blank one and accepts everything else.
2. **`connect` returns once the listener is up**, not once the peer is
   reached. The session starts at `idle`; the walk to `relayed` or
   `direct` happens afterwards and the app shows it on the status pill.
   Anything that has to reach the far machine waits for that walk. Pairing
   learned this on a phone (#55): it redeemed the code the moment `connect`
   returned, the tunnel's edge answered `502` in the gap before the peer
   was reached, and the one-time code was spent on nothing. The wait is
   now modelpipe's: `mpPair` calls `wait_reachable` before it presents the
   code, and `relayed` counts as reached there as it does here.
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
   status codes. The app maps every code modelpipe and gglib write,
   gglib's `device_not_paired` included, to a where-to-look hint
   (`ProviderError.whereToLook(forCode:)`). The codes are an enum, so a new
   one does not compile without an answer.
8. **No credential in any log line.** The ffi's logging, if it surfaces
   through the app's `LogSink`, must never include the ticket or the
   token. The binding sends nothing to `LogSink` itself; its one
   diagnostic line, for an upstream variant it does not know, goes to
   stderr. What of its output reaches `LogSink` goes through `AppModel`:
   `MpError.message()` in the dial-failure lines (`AppModel+Pipe.swift`,
   `AppModel.report`), and the loopback URL in "pipe up for … at …".
   modelpipe-ffi's `no_error_renders_the_ticket` keeps the ticket out of
   its errors, and the token never reaches the binding:
   `ModelpipeConnector` dials with the ticket alone. The app's redaction
   test (`OpenAICompatibleProviderTests.testNoCredentialEverReachesALogLine`)
   covers `OpenAICompatibleProvider`'s lines only, so nothing tests the
   lines `AppModel` writes.

## Pairing is inside the seam

The first connection to a machine trades a six-digit code for a key of
this device's own, and the route that does it is reachable only *through*
the pipe. It was built above the seam once, out of the two protocols
above: `connect(ticket:token:)` with the code as the token, a POST to
`session.baseURL`, `shutdown()`, and the key handed back to be stored and
dialled with. That asked nothing extra of the ffi, and it cost a second
dial for every first pairing.

**Amended 2026-09-16.** modelpipe-ffi 0.2.0 brought `mpPair`, which does
all of it — parse, dial, wait for the far machine, present the code, check
the answer names the ticket's endpoint — and hands back the key *and* the
pipe, still up. So `PipeConnector` has a third requirement now:

```swift
func pair(pairing: String, deviceName: String?) async throws -> PairedPipe
```

What the ffi owes here, beyond the two protocols above:

- **The whole pairing string goes in.** `ticket-code`, in either ASCII
  case, because the two halves are one argument to whatever dials.
- **The code is not presented before the far machine is reached**, for
  #2's reason. A redeem sent into that gap is answered `502` by the
  tunnel's edge and the one-time code is spent on nothing.
- **The pipe comes back up**, and becomes the provider's first session.
  Hanging it up to dial again would cost a second hole punch, and ~~without
  a lasting connect identity a second endpoint identity as well — so the
  fingerprint the far machine recorded as it minted the key would never be
  the one this device then chats from.~~

  > **Amended 2026-09-17 — the second half of that is no longer the
  > reason.** A dial and a pairing both carry an identity now (below), so a
  > redial would report the same device. Keeping the pipe still saves the
  > hole punch, which is what `mpPair` returns it for.

- **Somewhere to keep this device's endpoint key**, which is
  `MpConnectOptions.identityPath`, the one field of that record this app
  sets. Without it modelpipe mints a key per process, and the endpoint a
  serving machine records beside this device's token stops existing the
  moment the app is quit. The file is modelpipe's to write and to refuse;
  what this side owes is a path — one per far machine, because a relay allows
  one live connection per endpoint id — and the judgement to throw a key
  away when it is the thing refusing a dial.
  [ADR 0004](adr/0004-the-connect-identity-is-a-file.md) is why it is a file
  at all, in an app whose other secrets are in the Keychain.
- **The key is the only thing that must be kept**, and it goes to the
  Keychain as the provider's token. `PairedPipe` spells it `token` so that
  `scripts/check_log_calls.sh` catches a log line that reads it, and prints
  it as `<redacted>` so that one interpolating the whole value carries
  nothing either. `Paired` and the `OpenAICompatibleProvider` the key is
  handed to print it the same way, and `ReadPairing` prints its ticket as
  the ticket's digest.
- **Every failure is a sentence.** `MpPairError.message()`, never
  `localizedDescription`, which uniffi generates as `String(reflecting:)`.
  `Refused` keeps a case of its own above the seam, because it is the one
  pairing failure with somewhere to send the person.

The route itself is modelpipe's `POST /modelpipe/pair`, not gglib's old
`/v1/remote/pair`: a phone on this build pairs with gglib G1 and later,
and not with gglib 0.18.

> **Amended 2026-09-18: what this build does with a desktop on gglib
> 0.18.0, which serves modelpipe 0.5.** A key this device already holds
> still dials it. The binding moved from modelpipe 0.5 to 0.6 for
> dialling as well as for pairing, but the connect side's half of the
> wire did not change between them. It parses no HTTP, and its
> forwarder, framing, ticket format and ALPN are the same at both tags.
> The one new thing on the wire is the lasting endpoint id above.
>
> That was measured, not inferred (#112). modelpipe 0.6's connect side
> was run against a modelpipe 0.5 edge configured as gglib v0.18.0
> configures its tunnel: with a key file and without one, and over a
> relay alone. This app's own `ModelpipeConnector` and
> `OpenAICompatibleProvider` then dialled the same edge twice, streaming
> a reply each time. Not covered: gglib 0.18's real proxy behind the
> edge (a backend enforcing its gate's rules stood in); a phone's own
> network (the harness's connect side ran with port mapping off); iOS
> suspension; and an upgraded install's own Keychain, which was read
> rather than run: `Secrets.swift` is the same at v0.2.4 and v0.3.1.
>
> Pairing with that desktop does not work, and it costs the code. Its
> edge admits the code as a one-time grant, spends it on this request,
> and hands the request to a proxy with no such route. The form then
> says the other machine's answer was not a pairing answer (#113).
> Update the desktop first: gglib pairs with this build from
> `61e06b57` (gglib #1087) on, a commit no gglib release carried on
> 2026-09-18.

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
  >
  > **Answered 2026-09-12, by not asking it.** The app hangs up every
  > provider's pipe on its way to the background and dials again when it
  > comes back (`AppModel+Lifecycle.swift`), and since 2026-09-16 the two
  > passes take turns rather than racing, so none of them outlives a
  > suspension, and the ffi never has to say whether a listener was
  > reclaimed. The one exception is a pairing dial, which belongs to the
  > connector rather than the model and is not hung up on the way out; it
  > ends when the pairing does, and the pipe it leaves up is installed by
  > the same guard every other dial goes through — so one that lands after
  > the hang-up pass is hung up rather than kept.
  >
  > **Amended 2026-09-17 — that held only where the pairing reached the
  > install.** A pairing whose key or whose provider would not save returns
  > before it, and the pipe it left up was then absent from `pipeSessions` —
  > the list the background pass and the network watcher walk — so nothing
  > in the app could reach it, and it alone could outlive a suspension. It is
  > hung up on that path now, which is the rule the pairing carried for
  > itself before it moved behind the connector.
- The Keychain holds the ticket and token under the provider's id; the
  config holds only a digest, used to count distinct tickets (the app's
  kill criterion, shown in Settings).

## What was out of scope

The hole-punching spike from a carrier NAT on a real iPhone belonged to
the ffi work, not this repo. It has been run: on 2026-09-09 an iPhone on
cellular, with wifi off, reached a model on a Mac over a direct path
through carrier-grade NAT (gglib's ADR 0012, fourth reading).

> **Amended 2026-09-09 — the binding is linked; the connector is not written.**
> `Sources/GGChatPipe` is a target of its own that depends on
> `modelpipe-ffi`, and `scripts/check_boundaries.sh` now permits
> `import Modelpipe` there and nowhere else, rather than banning it outright.
> What has not changed is what a build does with a ticket:
> `PipeConnectorFactory` still returns the mock in DEBUG and
> `UnavailablePipeConnector` everywhere else, so everything below still
> describes behaviour a shipped build does not have.

> **Amended 2026-09-12 — and then it was.** #51 wrote the connector the
> same day, and #53 made a release build use it: `PipeConnectorFactory`
> returns `ModelpipeConnector()` in every build but DEBUG, which keeps the
> mock. The note above is kept as the record of the step between the two;
> the top of this document says what a shipped build does now.
