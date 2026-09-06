# What modelpipe-ffi must provide

ggchat stops at a seam. This is the seam, stated as the two Swift
protocols the app already compiles against, plus the behaviours the mock
has and the real thing must match. When `modelpipe-ffi` ships, a
`ModelpipeConnector` that satisfies this replaces both arms of the
`#if DEBUG` in `Sources/GGChatUI/PipeConnectorFactory.swift` — the mock in
a debug build, `UnavailablePipeConnector` in every other — and nothing
above it changes.

## The protocols (verbatim from `Sources/GGChatCore/PipeConnector.swift`)

```swift
public protocol PipeConnector: Sendable {
    func connect(ticket: String, token: String) async throws -> any PipeSession
}

public protocol PipeSession: Sendable {
    var baseURL: URL { get }                      // http://127.0.0.1:<port>/v1
    var status: AsyncStream<PipeStatus> { get }   // current value first, then changes
    func shutdown() async
}

public enum PipeStatus: String { case idle, direct, relayed, closed }
```

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
   why this is a URL and not a request API, and for the reading that
   would overturn it.
4. **`status` yields the current value first**, then every change, to
   every subscriber, however late it subscribes. Equal consecutive values
   may be delivered. The stream ends only after `shutdown()`.
5. **`closed` is recoverable by dialling again.** The app calls
   `shutdown()` on the old session and `connect` anew; the ffi must not
   require process restart. A `closed` seen while a reply streams is
   counted (ADR 0002).
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
- iOS suspends the app, and with it the listener. ADR 0001's reading
  counts transport errors within five seconds of a resume.
- The Keychain holds the ticket and token under the provider's id; the
  config holds only a digest, used to count distinct tickets (the app's
  kill criterion, shown in Settings).

## What is out of scope until then

The hole-punching spike from a carrier NAT on a real iPhone belongs to
the ffi work, not this repo. Nothing here links Rust or iroh, and the
boundary check fails the build if something does.
