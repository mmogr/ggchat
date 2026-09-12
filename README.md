# ggchat

![tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmmogr%2Fggchat%2Fbadges%2Ftests.json)
![coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fmmogr%2Fggchat%2Fbadges%2Fcoverage.json)

A native Apple chat client for OpenAI-compatible model servers, built so
that a server on your desk at home is reachable from your phone
anywhere, with no port forwarding, no VPN, no account, and no cloud in the
path. That reach comes from [modelpipe](https://github.com/mmogr/modelpipe).
The app is generic: any OpenAI-compatible provider works.
[gglib](https://github.com/mmogr/gglib) is the provider it is built around.

## What it looks like

| Streaming from gglib | A pipe, connected | gglib's server status |
|---|---|---|
| ![A finished reply on an iPhone](docs/screenshots/iphone-reply.png) | ![The model pill beside a status pill reading Direct](docs/screenshots/iphone-pipe-connected.png) | ![Slots, context used, and recent requests](docs/screenshots/iphone-server-status.png) |

![The macOS window, with a conversation open](docs/screenshots/macos-chat.png)

These are photographs of the app, not mock-ups. The three iPhone ones are
attachments the UI tests take as they walk through it, and `make
screenshots` regenerates them from a test run, so a picture cannot quietly
go stale. The first is a real reply from gglib.

## Status

Each release is on the [releases page](https://github.com/mmogr/ggchat/releases),
with what it changed. What exists today is the core package (the provider
protocol, the OpenAI-compatible implementation, the SSE parser, ticket
shape validation, pairing, the pipe seam with its mock) and the app shell:
a sidebar of conversations persisted with SwiftData, a providers sheet
that adds a server by address or a pipe by its pairing string, and
settings. The transcript streams replies as markdown with copyable code
blocks and collapsed reasoning, with a stop button and, when a reply stops
early, a Continue button. A server added by address lists its models and
streams; against gglib, a server status pane shows slots, context in use
and recent requests, and it is hidden for servers that do not answer that
endpoint. The app has been run: the screens above are photographs of it,
not mock-ups. A pipe provider is added by pasting the `ticket-code` string
the other machine showed for it (`gglib remote enable --invite` for the
first device, `gglib remote invite` for each one after that), or on iOS by
scanning its QR code: the six-digit code is spent once, through the pipe
itself, for a key minted for this device alone, so no key is ever read off
one screen and typed into another. A bare ticket, with no code, is for a
device that already holds its key. Connecting goes through
`PipeConnector`: a release build dials with `ModelpipeConnector`, and a
DEBUG build uses a mock that walks idle → relayed → direct. The status pill
follows the session, reads "Reconnect" when the pipe closes, and stays
pressable in every state but a dial in flight, because a connected status
can be stale. Going
to the background hangs up every pipe and puts down the reply in flight,
and coming back dials again. A provider's row opens its settings, so a
machine that has stopped admitting this device, or whose endpoint identity
was deleted, is re-paired in place and keeps its conversations. Settings
shows the readings the ADRs name, each with its denominator. In DEBUG
builds a mock provider streams canned replies without a server.

**A shipped build now dials for real.** `GGChatPipe` is a target of its own
that links `modelpipe-ffi`, and it is the only place the boundary check
permits `import Modelpipe`; `ModelpipeConnector` behind it validates a ticket,
dials, and hands back a session whose loopback URL is the far machine. The
mock stays on the DEBUG side of `PipeConnectorFactory` rather than being
replaced, because it is what the Settings screen's "Force closed" control and
twenty-odd app-model tests are written against. It is absent from a release
build, not merely unchosen: `MockPipeConnector` and `MockPipeSession` are
declared inside an `#if DEBUG`, and `make build-release` fails if either
symbol is in the release objects.

## What is true today

Each claim names the test that keeps it true.

- A stream captured from a running gglib parses to the same events whether
  it arrives whole or one byte at a time.
  <!-- test: SSEParserTests.testFeedingOneByteAtATimeGivesTheSameItems -->
- gglib's first chunks carry no `choices` key; reasoning arrives as
  `reasoning_content`; the usage chunk has empty `choices`. All three decode.
  <!-- test: WireTests.testFirstChunkHasNoChoicesKeyAndStillDecodes -->
  <!-- test: WireTests.testReasoningArrivesAsReasoningContent -->
  <!-- test: WireTests.testUsageChunkHasEmptyChoicesAndCachedTokens -->
- A server's error sentence is shown verbatim, and every code modelpipe and
  gglib write says which machine to look at, that the request itself was
  refused, or that the answer is to wait. The side named is the side that
  wrote the refusal, which is not always the side you are sitting at. The
  codes are an enum, so the mapping is exhaustive by the compiler rather
  than by a list someone remembers to extend.
  <!-- test: ErrorTests.testServerMessageIsRenderedVerbatim -->
  <!-- test: ErrorTests.testEveryDocumentedCodeNamesWhereToLook -->
  <!-- test: ErrorTests.testTheSideNamedIsTheSideThatWroteTheRefusal -->
  <!-- test: ErrorTests.testAMachineThatIsMerelyBusySaysToWaitRatherThanNamingASide -->
- A ticket's shape is validated without decoding it: `pipe` prefix in any
  ASCII case, base32 body, no padding, between 67 and 1643 characters, and
  non-ASCII is rejected before any case folding. 67 is modelpipe's minimal
  ticket — one endpoint id and nothing else — and a real ticket from
  `modelpipe serve` is 81 characters and is accepted in either case.
  <!-- test: TicketTests.testTheShapeARealTicketHas -->
  <!-- test: TicketTests.testATicketTooShortToCarryAnEndpointIdIsRefused -->
  <!-- test: TicketTests.testLongestPossibleTicketIsAcceptedAndOneMoreIsNot -->
  <!-- test: TicketTests.testNonASCIIIsRejectedBeforeCaseFolding -->
- A pairing string comes apart the way gglib's does: on the last `-`, with
  a six-digit code after it, and the whole thing uppercased is what the
  printed QR carries. A suffix that is not six digits is named as the
  problem rather than swallowed.
  <!-- test: PairingStringTests.testTheOneStringGGLibPrintsIsAccepted -->
  <!-- test: PairingStringTests.testASuffixThatIsNotSixDigitsIsNamedAsTheProblem -->
- Pairing is a step before the seam, not a third parameter on it: the
  ticket is dialled, the code is redeemed through that pipe as both the
  bearer and the body, the pipe is hung up, and the key that comes back is
  the provider's token. A refused code leaves no provider behind, and the
  form stops asking for a token once it has a code to fetch one with.
  <!-- test: PipePairingTests.testPairingDialsRedeemsThroughThatPipeAndHangsUp -->
  <!-- test: PairingTests.testTheCodeTravelsAsTheBearerAndInTheBody -->
  <!-- test: AppModelPairingTests.testARedeemedCodeBecomesTheProvidersTokenAndThePipeConnects -->
  <!-- test: AppModelPairingTests.testARefusedCodeAddsNoProviderAndSaysWhy -->
  <!-- test: ScreenGalleryUITests.testAPairingCodeIsRedeemedInsteadOfAskingForAToken -->
- The name typed for this device travels in the redeem's body as `name`,
  beside the code. A name that is blank once trimmed is not sent at all:
  the key is left out, not sent empty. The app model never sends the
  provider's name, which names the other machine, in its place.
  <!-- test: PairingTests.testADeviceNameTravelsInTheBodyAsName -->
  <!-- test: PairingTests.testABlankDeviceNameIsNotSentAtAll -->
  <!-- test: PipePairingTests.testTheDeviceNameRidesTheRedeem -->
  <!-- test: AppModelPairingTests.testTheNameTypedForThisDeviceIsWhatTheRedeemCarries -->
  <!-- test: AppModelPairingTests.testWithNoDeviceNameTheProvidersNameIsNotSentInItsPlace -->
- The modelpipe binding is linked and answers across the boundary: a string
  that is not a ticket comes back as an `MpError` with a sentence in it. The
  xcframework is a binary fetched at resolve time and checked against a uniffi
  checksum only on first use, so a mismatched pair traps on a device rather
  than failing a build — something has to call across the boundary on every
  run, and this is it. Its four statuses cross into the app's own unchanged.
  <!-- test: BindingTests.testTheBindingIsLinkedAndAnswersAcrossTheBoundary -->
  <!-- test: BindingTests.testEveryPipeStatusCrossesUnchanged -->
  <!-- test: BindingTests.testARelayedPipeCountsAsConnected -->
- A real connector validates before it dials, so a ticket of the wrong shape
  and an empty token each cost nothing — which matters because pairing dials
  with the six-digit code as the token, and `PipePairing` does no shape check
  of its own.
  <!-- test: ModelpipeConnectorTests.testATicketOfTheWrongShapeIsRefusedWithoutDialling -->
  <!-- test: ModelpipeConnectorTests.testAnEmptyTokenIsRefusedEvenThoughTheBindingWouldNotWantIt -->
- A failure from the transport reaches the person as a sentence, never as the
  binding's own debug rendering, and says whether dialling again is worth it.
  <!-- test: ModelpipeConnectorTests.testATransportErrorArrivesAsASentenceAndNotADebugRendering -->
  <!-- test: ModelpipeConnectorTests.testABadTicketIsNotWorthDiallingAgain -->
  <!-- test: ModelpipeConnectorTests.testTheBindingDecidesWhatIsWorthRepeating -->
- A pipe that dies on its own still says `closed`. The binding ends its status
  sequence on any close, and nothing above the seam writes a status when a
  stream merely finishes, so the session writes it before finishing.
  <!-- test: ModelpipeSessionTests.testAPipeThatDiesOnItsOwnStillSaysClosed -->
- `relayed` is held back for a moment in case a direct path is behind it, and
  shown when nothing better follows. A hole punch commonly reaches a relay
  first, and a pill that flashes "Relayed" reads as a warning about a
  connection that is still being made.
  <!-- test: ModelpipeSessionTests.testRelayedDoesNotFlashWhenDirectIsAMomentBehindIt -->
  <!-- test: ModelpipeSessionTests.testRelayedIsShownWhenNothingBetterFollows -->
- A pipe's base URL has to be loopback with a port, not merely something
  `URL(string:)` accepted — it parses strings with spaces and no scheme at all.
  <!-- test: ModelpipeSessionTests.testAnAddressOffLoopbackIsRefused -->
- A dial the person asked for says why it failed; one they did not — the
  resume dials every pipe it is holding none of — says nothing and leaves the
  pill as the way back. A machine that is asleep would otherwise raise an
  alert on every return to the foreground, carrying only the last provider's
  sentence.
  <!-- test: AppModelQuietDialTests.testADialSomebodyAskedForSaysWhatWentWrong -->
  <!-- test: AppModelQuietDialTests.testAResumeThatFindsTheMachineAsleepSaysNothing -->
- A dial cancelled by the view going away complains to nobody, because the
  composer dials inside a task SwiftUI cancels on every provider switch.
  <!-- test: AppModelQuietDialTests.testADialCancelledByTheViewGoingAwaySaysNothing -->
- A pipe that dies quietly is forgotten, so the next resume dials it again
  instead of finding a dead session installed and refusing.
  <!-- test: AppModelQuietDialTests.testASessionThatEndedIsForgottenSoAResumeCanDialAgain -->
  <!-- test: AppModelQuietDialTests.testAnOldSessionEndingDoesNotRemoveTheOneThatReplacedIt -->
- Pairing waits for the far machine before spending the code. `connect`
  returns once the local port is bound, not once the peer answers, and a
  redeem sent into that gap is answered `502` by the tunnel's own edge — which
  spends the one-time code on nothing and needs a fresh `gglib remote invite`.
  <!-- test: PipePairingTests.testAPipeThatNeverReachesTheFarMachineDoesNotSpendTheCode -->
- The mock pipe walks idle → relayed → direct, can be forced closed, and a
  late subscriber gets the current status first.
  <!-- test: MockPipeTests.testStatusWalksIdleRelayedDirectThenClosedOnDemand -->
- A pipe that goes away without being asked says which side to look at. The
  binding reports a shutdown and a failed listener and nothing else, so a peer
  that simply stopped answering closes with no reason recorded — and that
  silence, not an open pipe, is what it is read as.
  <!-- test: PipeCloseReasonTests.testEveryReasonThatWasNotAskedForHasASentenceNamingASide -->
  <!-- test: ModelpipeSessionTests.testAPeerThatSimplyVanishesIsSaidToHaveVanished -->
  <!-- test: AppModelCloseReasonTests.testAPeerThatVanishesLeavesAReasonBesideTheStatusAndOneSentence -->
- A close the app asked for — the background, a reconnect, a provider deleted
  — explains nothing and says nothing, because it is something the person just
  did.
  <!-- test: PipeCloseReasonTests.testAHangUpThisAppAskedForIsNotWorthASentence -->
  <!-- test: AppModelCloseReasonTests.testAHangUpTheAppPerformedExplainsNothingAndSaysNothing -->
- Settings shows what each live pipe says about itself: its path, the loopback
  port it bound, and what its endpoint spent on relays.
  <!-- test: ModelpipeSessionTests.testTheReadingsCrossTheSeamInTheAppsOwnVocabulary -->
- The mock is DEBUG-only. A build without one refuses a perfectly good
  ticket with a sentence about the build, instead of mocking a pipe that
  is not there.
  <!-- test: UnavailablePipeTests.testABuildWithNoPipeRefusesAGoodTicketInsteadOfMockingOne -->
  <!-- test: UnavailablePipeTests.testTheRefusalIsASentenceThatBlamesTheBuildAndNotTheUser -->
- A bearer token is sent on every request and never reaches a log line.
  <!-- test: OpenAICompatibleProviderTests.testNoCredentialEverReachesALogLine -->
- gglib's proxy status endpoint decodes when it answers and is `nil` on 404.
  <!-- test: OpenAICompatibleProviderTests.testProxyStatusIsNilOn404AndDecodesOn200 -->
- An unterminated code fence, as seen mid-stream, renders as a code block.
  <!-- test: MarkdownTests.testUnterminatedFenceIsStillACodeBlock -->
- A `ProviderConfig` holds no credential; a pipe config carries only a
  digest of its ticket.
  <!-- test: ProviderConfigTests.testPipeProviderRoundTripsAndHoldsOnlyADigest -->
- A pasted address becomes a base URL: a bare host gets `/v1`, a trailing
  slash is dropped, anything that is not http or https is refused.
  <!-- test: BaseURLNormalizationTests.testBareHostGetsV1AndTrailingSlashIsDropped -->
- Conversations, their messages in order, and providers survive a round
  trip through SwiftData; deleting a conversation cascades to its messages.
  <!-- test: SwiftDataStoreTests.testConversationsRoundTripWithMessagesInOrder -->
- Sending streams the reply, with reasoning kept separately, into the
  conversation; a dropped stream keeps the partial reply on screen and
  Continue extends that same message rather than starting a new one.
  <!-- test: AppModelStreamingTests.testSendStreamsAReplyIntoTheConversation -->
  <!-- test: AppModelStreamingTests.testADroppedStreamKeepsThePartialAndContinueCarriesOn -->
- Exactly three custom glass surfaces exist, all in one file inside one
  `GlassEffectContainer`; `scripts/check_glass_sites.sh` counts them, and
  `scripts/check_no_hand_drawn_glass.sh` refuses any material or
  translucent fill elsewhere, so Reduce Transparency and Increase Contrast
  are the system's to honour — and the test measures the glass going flat
  rather than trusting the setting, because the launch arguments that look
  like it are accepted and change nothing. Symbol effects and the streaming
  animation switch off under Reduce Motion, and the pills stack at
  accessibility type sizes.
  <!-- test: ReduceTransparencyUITests.testGlassGoesFlatWhenTransparencyIsReduced -->
- With `GGCHAT_LIVE_BASE_URL` set, the app model adds that server by URL,
  lists its models, streams a complete reply and probes the status endpoint.
  <!-- test: LiveAppModelTests.testAddByURLListModelsStreamAndProbeStatus -->
- Connecting a pipe provider walks the status to direct, fires the one
  haptic once, records the ticket's digest, and streams through the
  session's loopback URL with the token as the key; a forced close is
  counted and reconnecting dials again without counting the ticket twice.
  <!-- test: AppModelPipeTests.testConnectWalksToDirectAndStreamsThroughTheSessionURL -->
  <!-- test: AppModelPipeTests.testForceClosedIsCountedAndReconnectDialsAgain -->
- A dial that lands after its provider was hung up or deleted closes itself
  instead of installing a pipe nothing on screen can reach any more, two
  dials in flight at once leave one connection rather than two, and a
  provider that has left the list is not dialled at all.
  <!-- test: AppModelDialTests.testADialThatLandsAfterADisconnectHangsUpInsteadOfInstallingItself -->
  <!-- test: AppModelDialTests.testRemovingAProviderMidDialLeavesNoConnectionBehind -->
  <!-- test: AppModelDialTests.testTwoOverlappingDialsLeaveExactlyOneConnection -->
  <!-- test: AppModelDialTests.testAProviderThatIsNoLongerOnTheListIsNotDialled -->
- A dial that is refused leaves a closed pill to press rather than no pill at
  all, and the next resume dials it again — one machine that was asleep is not
  a provider you have to relaunch the app to reach. A dial refused after it
  was called off says nothing instead.
  <!-- test: AppModelFailedDialTests.testAFailedDialLeavesAPillToPressAndAResumeThatDialsAgain -->
  <!-- test: AppModelFailedDialTests.testARefusalThatArrivesAfterItsDialWasCalledOffSaysNothing -->
- Going to the background hangs up every pipe and writes the reply that was
  in flight into the conversation as a partial rather than losing it; coming
  back dials again, and only the pipes the app already had.
  <!-- test: AppModelLifecycleTests.testGoingToTheBackgroundHangsUpEveryPipeAndComingBackDialsAgain -->
  <!-- test: AppModelLifecycleTests.testGoingToTheBackgroundKeepsThePartialReplyInsteadOfLosingIt -->
  <!-- test: AppModelLifecycleTests.testComingBackDoesNotDialAPipeTheAppNeverOpened -->
- When the network under the device changes while the app is open, every
  pipe it holds is told, so its endpoint looks at the network again then,
  whether or not iroh's own watch on the routing socket noticed the move.
  A pipe already hung up is not told, and watching starts as the app
  launches rather than on its first return to the foreground.
  <!-- test: AppModelNetworkChangeTests.testAChangeToTheNetworkTellsEveryLivePipe -->
  <!-- test: AppModelNetworkChangeTests.testAPipeThatWasHungUpIsNotTold -->
  <!-- test: AppModelNetworkChangeTests.testLoadingStartsWatchingTheNetworkOnce -->
- Every close the app shows is a close it counts, whoever wrote it down: ADR
  0002's denominator moves for a background and for a refused dial, not only
  for a close a live session reported. A close is counted once — a background
  after a refused dial adds nothing — and a hang-up that leaves no pill at
  all, from a delete or a reconnect, is not counted as one.
  <!-- test: AppModelLifecycleTests.testEveryBackgroundCountsTheCloseItPutsOnTheScreen -->
  <!-- test: AppModelFailedDialTests.testABackgroundAfterARefusedDialAddsNoSecondClose -->
  <!-- test: AppModelPipeTests.testAHangUpThatLeavesNoPillIsNotCountedAsAClose -->
- A close counts as mid-reply when it is what ended the reply — whether the
  far machine went away or the app put the reply down on its way to the
  background. Either leaves a partial with a Continue button under it, so
  long as any of the reply had arrived; a background before the first token
  counts the close and leaves nothing to continue. ADR 0002 struck the
  threshold that fraction was meant to answer, and the counters outlived it.
  <!-- test: AppModelPipeTests.testAPipeThatGoesAwayMidReplyIsCountedAsAMidReplyClose -->
  <!-- test: AppModelLifecycleTests.testABackgroundThatCutsAReplyShortCountsAMidReplyClose -->
- A provider's row opens its settings, and its name and credentials are
  edited in place, keeping the id — so a machine that invites this device
  again with `gglib remote invite` keeps its conversations.
  A blank credential keeps the one stored, an edit that will not save puts
  back what it found, and a new ticket is dialled rather than saved and
  ignored.
  <!-- test: ScreenGalleryUITests.testAProviderRowOpensItsSettingsAndTheEditSticks -->
  <!-- test: AppModelProviderTests.testEditingAPipesCredentialsKeepsItsIdAndSoItsConversations -->
  <!-- test: AppModelProviderTests.testAnEmptyCredentialKeepsTheOneAlreadyStored -->
  <!-- test: AppModelProviderTests.testAnEditThatWillNotSaveLeavesTheOldCredentialsInPlace -->
  <!-- test: AppModelProviderTests.testRePairingRedeemsTheNewCodeAndDialsTheNewTicket -->
  <!-- test: AppModelProviderTests.testARefusedCodeLeavesTheProviderPairedWithTheMachineItHad -->
  <!-- test: AppModelProviderTests.testEditingAProviderThatIsGoneSaysSoRatherThanSavingNothingQuietly -->
- Removing a provider deletes its durable record before its credentials, so
  a delete that fails leaves the provider whole rather than resurrecting one
  on the next launch that can never connect.
  <!-- test: AppModelProviderTests.testAProviderWhoseRecordWillNotDeleteKeepsItsCredentials -->
  <!-- test: AppModelProviderTests.testRemovingAProviderTakesItsRecordAndItsCredentialsTogether -->
- The Diagnostics readings survive a relaunch, and only a transport error
  within five seconds of a resume increments the "Transport errors after
  resume" reading; see ADR 0001's amended kill criteria for why that
  reading is not a health signal.
  <!-- test: DiagnosticsTests.testReadingsPersistWithTheirDenominators -->
- A first-time user can add a provider, start a conversation, send a
  message and watch the reply stream in, driven through the real app on a
  simulator. The same walk runs against the server `GGCHAT_LIVE_BASE_URL`
  names, typing `GGCHAT_LIVE_API_KEY` into the form; with neither set it
  falls back to a server on `127.0.0.1:8080` and skips when none is there.
  <!-- test: FirstRunUITests.testFirstRunWithTheMockProvider -->
  <!-- test: FirstRunUITests.testFirstRunAgainstAServerOnThisMachine -->
- Which server a live walk drives is resolved from those two variables: one
  named outright is used as given and never probed, so an unreachable one
  fails rather than skipping, and an unset one falls back to the loopback
  only when something answers there.
  <!-- test: LiveServerTests.testANamedServerIsUsedAsGivenAndIsNotProbed -->
  <!-- test: LiveServerTests.testAnUnnamedServerFallsBackToTheLoopbackThatAnswers -->
  <!-- test: LiveServerTests.testNothingNamedAndNothingListeningIsASkip -->
- A credential that will not save takes the provider with it, rather than
  leaving one that fails later, and the reason names the credential.
  <!-- test: AddProviderFailureTests.testACredentialThatWillNotSaveLeavesNoHalfAddedProvider -->
  <!-- test: AddProviderFailureTests.testTheKeychainErrorSaysWhichCredentialAndWhy -->
- Saving a credential updates the Keychain item and adds one only when
  there was none to update, so the first save of a token and every save
  after it both land. Any other status is reported rather than retried as
  an add. The `SecItem` calls sit behind a seam a test can stand in for,
  because reaching the real Keychain needs a signed build carrying the
  entitlement.
  <!-- test: KeychainSecretsTests.testAnItemThatIsAlreadyThereIsUpdatedAndNeverAdded -->
  <!-- test: KeychainSecretsTests.testAnItemThatIsNotThereIsAddedOnlyAfterTheUpdateMisses -->
  <!-- test: KeychainSecretsTests.testAnUpdateThatFailsForAnyOtherReasonIsNotRetriedAsAnAdd -->
- The screens the first-run walk never reaches are visited and photographed
  too: the provider form and what it says about a bad address or ticket, a
  pipe connecting and its status pill, the providers list, and the
  diagnostics readings.
  <!-- test: ScreenGalleryUITests.testAPipeConnectsAndTheStatusPillWalks -->
  <!-- test: ScreenGalleryUITests.testTheProviderFormExplainsABadTicket -->
- gglib's server status pane fills in from a real server, and is not
  offered at all by a provider that does not report one.
  <!-- test: RemainingScreensUITests.testTheServerStatusPaneAgainstARealServer -->
  <!-- test: RemainingScreensUITests.testTheStatusPaneIsHiddenForAServerThatDoesNotReport -->
- A closed pipe turns its status pill into a reconnect, and pressing it
  brings the pipe back. The pill is a way back in every state but one — a
  dial already in flight — so a status that has gone stale is still
  something you can press.
  <!-- test: RemainingScreensUITests.testAClosedPipeOffersAReconnect -->
  <!-- test: AppModelDialTests.testOnlyADialInFlightWithholdsTheWayBack -->
- Text grows at the largest accessibility size, and the test measures it,
  so a launch argument that silently changes nothing cannot pass for a
  Dynamic Type check.
  <!-- test: RemainingScreensUITests.testTheAppAtAnAccessibilityTypeSize -->
- Reopening the app returns you to the conversation you left.
  <!-- test: SwiftDataStoreTests.testAppModelKeepsSelectionAndPersistsThroughTheStore -->
- A block quote's `>` marker and a list item's indentation stay out of the
  rendered text.
  <!-- test: MarkdownTests.testListsHeadingsQuotesAndRules -->

## Building and testing

Requires Xcode 26 and Swift 6.2 or later.

```sh
swift build && swift test
```

Against a running gglib (or any OpenAI-compatible server) the live tests
list models, stream one short reply, and drive the same thing through the
app model:

```sh
GGCHAT_LIVE_BASE_URL=http://127.0.0.1:8080/v1 make test-live
```

Set `GGCHAT_LIVE_API_KEY` as well to point it at a server that wants a
bearer token, which is how it runs against a modelpipe pipe. Every live
test skips itself when `GGCHAT_LIVE_BASE_URL` is unset, so `make test-live`
refuses to run without it rather than passing having exercised nothing.

`make ci` runs what CI runs: `make fmt-check`, `make lint`, `make analyze`,
`make boundaries`, `make enforce`, `make build`, `make build-release`,
`make build-app`, `make build-app-release`, `make test`, `make unused`,
`make docs`. The UI-test legs are the exception; they need a booted
simulator and have their own targets below. `make bootstrap` installs the
Homebrew tools those need (xcodegen, swiftlint, periphery, actionlint).

`make analyze` runs the rules under `analyzer_rules` in `.swiftlint.yml`.
They are separate from `make lint` because they need the arguments the
compiler was given, so the target builds with `-v` first and hands
swiftlint that log.

`make build-release` compiles the package in its Release configuration and
then reads the symbols out of the objects it produced, failing if the
DEBUG-only mock pipe is among them. A release build on its own would not
catch it: the mock compiles perfectly well in one. `make build-app-release`
compiles the app target in Release and is the only thing that does, but it
goes through xcodebuild and leaves no `.build/release` objects to read,
which is why both targets exist.

The app target is generated from `App/project.yml` by xcodegen
(`make project`) and committed. Open `App/ggchat.xcodeproj` in Xcode, or
build both platforms with `make build-app`:

```sh
xcodebuild build -project App/ggchat.xcodeproj -scheme ggchat -destination 'platform=macOS'
xcodebuild build -project App/ggchat.xcodeproj -scheme ggchat -destination 'generic/platform=iOS Simulator'
```

The app icon is drawn rather than stored: `scripts/make_app_icon.swift` is
the source and `make icon` writes the eleven PNGs the asset catalogue names.
The mark is a lowercase g whose descender leaves the letterform and ends on
a dot -- the bowl is the conversation, the tail is the pipe, the dot is the
machine at the other end of it. It centres itself on its own measured
bounding box, so moving a curve does not mean re-tuning eleven sizes by hand.

`make build-app-device` compiles the app for the `iphoneos` SDK, which
nothing else does: every other app build targets a simulator or macOS, and
those share the host's frameworks and can fall back to x86_64. A problem
specific to a real device would otherwise first appear during an archive.
Signing is off there rather than ad-hoc, because the iOS SDK refuses an
ad-hoc identity outright and a real one needs a provisioning profile; what it
proves is the compile and the link.

`make build-app-release` compiles the same two destinations with
`-configuration Release`. Nothing else compiles the app target that way:
the scheme's run and test actions are Debug, `xcodebuild build` with no
`-configuration` takes the run action's, and the Release archive action is
not run here. That is what it is for -- the app target, its generated
project and its signing settings, built the way a shipped one is. The
`#else` arms all live in `Sources`, and `make build-release` compiles
those.

`make uitest` drives the app on a booted iPhone simulator: the first-run
flow, and a walk through the screens that flow never reaches. It always
runs against the DEBUG mock provider, and also against a live server:

```sh
GGCHAT_LIVE_BASE_URL=http://127.0.0.1:8080/v1 GGCHAT_LIVE_API_KEY=sk-... make uitest
```

The same two variables as `make test-live`, so one recipe configures both
halves of the live suite. The walk types the key into the provider form, so
a gglib that enforces one is reachable; before this it typed none and could
only pass against a gglib that enforced none. With neither variable set it
falls back to probing `127.0.0.1:8080` and skips when nothing answers, which
is what keeps CI, where no gglib runs, green. `xcodebuild` hands a test
runner on a simulator only the variables named `TEST_RUNNER_<NAME>`, so the
Makefile and `scripts/screenshots.sh` forward them under that prefix; setting
the bare names on an `xcodebuild` invocation of your own will not reach the
walk.

The builds are signed ad-hoc, because an unsigned iOS app has no Keychain
access and this app keeps every credential there.

`make uitest-ipad` runs the same walk on an iPad, which is not a larger
iPhone: the root is a `NavigationSplitView`, so the sidebar and the
conversation are two columns rather than a stack, and Settings is on
screen instead of one screen back. It is the leg CI runs, and like CI it
leaves out the Reduce Transparency reading, whose bands are fractions of
an iPhone's screen. CI runs the walk on both families.

`make uitest-dark` and `make uitest-contrast` run the same walk with the
device set to dark mode and to Increase Contrast. Both are settings on the
simulator rather than launch arguments, so each target sets one, checks
`simctl` reads it back, and restores it afterwards even if the walk fails.
Reduce Transparency has no `simctl` option and no working launch argument,
so its test sets it through Settings and measures the result instead.

## Layout

```
Sources/GGChatCore/   no SwiftUI; the provider protocol, wire types, SSE, ticket, pairing, pipe seam, mocks
Sources/GGChatPipe/   the only target that links modelpipe-ffi; no UI framework either
Sources/GGChatUI/     SwiftUI; the app model, views, and SwiftData persistence
App/                  the xcodegen spec, the generated project, and a @main struct with assets
Tests/GGChatCoreTests XCTest; fixtures are real captures from gglib
Tests/GGChatPipeTests that the binding is linked and its statuses cross unchanged
Tests/GGChatUITests   the app model, streaming, the pipe, and the SwiftData store
App/ggchatUITests     XCUITest that drives the first-run flow on a simulator
docs/adr/             decisions, each with a kill criterion that names a reading
scripts/              the checks CI runs; `make ci` runs the same ones, and the app icon's source
```

## The seam

The pipe path stops at two protocols, `PipeConnector` and `PipeSession`.
[docs/ffi-seam.md](docs/ffi-seam.md) states what `modelpipe-ffi` must
provide in their terms, and which tests already assert each behaviour
against the mock.

## Decisions

- [ADR 0001](docs/adr/0001-loopback-port-at-the-ffi-seam.md): a loopback
  port, not a request API, at the ffi seam.
- [ADR 0002](docs/adr/0002-an-in-flight-request-is-kept-not-re-sent.md): an
  in-flight request on reconnect is kept, not re-sent.
- [ADR 0003](docs/adr/0003-keychain-access-group.md): rejected. Credentials
  stay on the device and build that saved them; each machine is paired, or
  has its key typed, once.

## Releases

Versions come from [release-please](https://github.com/googleapis/release-please):
conventional commit titles on `main` accumulate into a release PR, and
merging it tags the version and rewrites `Config/Version.xcconfig`.
Documentation is built with DocC. The static-hosting build runs on every
push to `main`, so a change that breaks it is caught by the commit that
made it rather than by the release; the deploy step still runs only for a
published release or a manual dispatch. Nothing is served yet: GitHub
Pages is not enabled on this repository -- a repository setting, not
something a workflow can turn on -- so the Pages URL 404s until someone
enables it.

## House rules

- Commit messages and PR titles say what the system now does, as a
  sentence: `feat(chat): the composer keeps its draft across a provider switch`.
- Every sentence in this README is true, and where a claim can be tested a
  test keeps it. `scripts/check_readme_claims.sh` checks that every marker
  above names a test that exists.
- One writer for the pipe status: `pipeStatuses` is written only by
  `setPipeStatus(_:for:cutShort:)`, which is where a close is counted, so a
  close the app shows is a close ADR 0002 hears about.
  `scripts/check_one_status_writer.sh` refuses any other write.
- No credential in any log line, ever.
- Time is an argument: nothing in `GGChatCore` reads the clock except
  `Clock.swift`.
