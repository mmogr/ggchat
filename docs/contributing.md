# Contributing to ggchat

How the app is built, tested, laid out and released. The [README](../README.md)
says what it is; [what-is-true-today.md](what-is-true-today.md) lists what it
does, claim by claim, with the test for each.

## Building and testing

Requires Xcode 26 and Swift 6.2 or later. The iPhone Duo layouts are
compiled only by Swift 6.4 or later and run only on iOS 27.1, so they need
Xcode 27.1 or later; Xcode 27.0 has that compiler without the iOS 27.1 SDK
and cannot build the package. Every other layout is what CI, on Xcode 26.6,
builds and tests.

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

gglib's model library asks Hugging Face itself, through the Mac's slice of
its framework: a search, and a small repository's quantizations judged
against a phone's reading, with no download. Those tests skip themselves
unless `GGCHAT_LIVE_HF=1`, which only this sets, so neither `make ci` nor CI
reaches the network for them:

```sh
make test-live-library
```

gglib's own engine is served on the Mac's slice by `make test-live-engine`,
with tinygemma3, gglib's recorder's tiny model, in a scratch library: the
model is listed under the name it was added as, one reply streams through
the ordinary provider, the status walks to ready with that name at the
context the reply's usage reports, and the shutdown ends it on stopped.
`make record-phone-stream` records the reply `PhoneStreamContractTests`
replays, into `Tests/GGChatLocalTests/Fixtures`, with a note of the gglib,
the llama.cpp and the model that made it. Both need the folder holding
`tinygemma3-Q8_0.gguf` and gglib's own tool for adding it, since the binding
has no call that adds a file; neither is in `make ci`:

```sh
GGLIB_ENGINE_MODELS_DIR=~/models \
GGLIB_FFI_ADD_MODEL=~/src/gglib/target/debug/gglib-ffi-add-model \
make test-live-engine
```

The tool is built in a gglib checkout with `cargo build -p gglib-ffi
--features smoke --bin gglib-ffi-add-model`.

`make test-pipe` dials a real `modelpipe serve` on this machine through the
shipped connector, with discovery, port mapping and the public relays off, and
checks that a request crosses the pipe to the far edge and back. It needs the
`modelpipe` binary, built from crates.io at the version `MODELPIPE_CLI_VERSION`
names in `.github/workflows/pipe.yml`, the one the binding's modelpipe is at.
The test skips itself when `MODELPIPE_BIN` is unset, and this target refuses to
run without it, and fails if the test did not run and pass:

```sh
cargo install modelpipe-cli --version <MODELPIPE_CLI_VERSION> --locked --root /tmp/modelpipe
MODELPIPE_BIN=/tmp/modelpipe/bin/modelpipe make test-pipe
```

`make ci` runs what CI runs: `make fmt-check`, `make lint`, `make analyze`,
`make boundaries`, `make enforce`, `make build`, `make build-release`,
`make build-app`, `make build-app-release`, `make test`, `make unused`,
`make docs`. The UI-test legs are the exception; they need a booted
simulator and have their own targets below. `make bootstrap` installs the
Homebrew tools those need (xcodegen, swiftlint, periphery, actionlint).

gglib's Swift framework, and llama.cpp's framework that it links, come from
a gglib release, pinned in `Package.swift` by version and by each archive's
checksum on three lines that exist only to be rewritten, with the Swift
generated for them vendored in `Sources/GGLib`. Both are dynamic, and the
app embeds and signs both. A release is taken with

```sh
scripts/pin_gglib.sh 0.28.0-rc.2
```

which downloads its `SHA256SUMS` and its three archives, checks each archive
against its line, and only then rewrites the three lines and replaces
`Sources/GGLib` with the release's swift archive, `binding.json` included;
the two are committed together. `scripts/check_gglib_take.sh`, the last of
`make enforce` and of CI's enforcement job, downloads the pinned release's
swift archive and fails unless `Sources/GGLib` is that archive byte for byte
and the pinned checksums are the release's own. It refuses checksums of
zeros, which pin nothing.

To build against a gglib of your own, build its frameworks in that checkout
with its own make targets, `phone-llama` and then `ffi-xcframework`, take
them, and set `GGLIB_FFI_LOCAL_XCFRAMEWORK` for every build:

```sh
scripts/pin_gglib.sh --local ~/src/gglib
GGLIB_FFI_LOCAL_XCFRAMEWORK=1 make build test build-app
```

`--local` copies the checkout's `GglibFFI.xcframework` and the
`llama.xcframework` at its pin into `build/`, which git ignores, and replaces
`Sources/GGLib` with the Swift that build generated beside the framework;
`Package.swift` is left as it is, and `check_gglib_take.sh` fails until a
release is taken again. Flipping the switch calls for a fresh package
resolution: SwiftPM and Xcode cache what a manifest evaluated to and the
artifacts it named, and a cache that missed the flip builds against the
other framework without a word. After a flip, run `swift package reset`
before `swift build`, and Reset Package Caches in Xcode, or delete the
project's DerivedData, before an app build. Xcode sees the switch only in
the environment it was started from, as `xcodebuild` from that shell does.

`make analyze` runs the rules under `analyzer_rules` in `.swiftlint.yml`.
They are separate from `make lint` because they need the arguments the
compiler was given, so the target builds with `-v` first and hands
swiftlint that log.

`make build-release` compiles the package in its Release configuration and
then reads the symbols out of the objects it produced, failing if the
DEBUG-only mock pipe or mock engine is among them. A release build on its
own would not catch it: each mock compiles perfectly well in one. The check finds the
objects under either layout `swift build` writes, the native build
system's and, from Swift 6.4, swiftbuild's. `make build-app-release`
compiles the app target in Release and is the only thing that does, but it
goes through xcodebuild and leaves no package objects to read, which is
why both targets exist.

`make unused` builds the package and its tests once more, from nothing, in a
scratch path of its own with an index store switched on, and hands that store
to periphery: periphery's own build writes one only under the native build
system, a compiler writes a unit only for a file it compiles, so only a fresh
build's store describes the tree as it is, and a store shared with `make
build` and `make test` goes stale as soon as either recompiles a file without
it. It refuses to pass on an empty store.

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

`make phone` builds the app in Release, signed for a phone, and installs it
with `xcrun devicectl` on the one iPhone this Mac can reach, or on the one
`DEVICE` names; with none, or more than one, it refuses and says why. A
build signed by a free team stops opening when its provisioning profile runs
out, seven days after the profile was issued, so this is the refresh in one
command. Run it on or after the day Settings shows: a build made while the
old profile is still valid may keep its date.

A launch can be timed on the phone. Before the window draws anything,
ggchat opens its store and makes its model, and then, as the window's first
task, loads every conversation. Each step is a Points of Interest interval
of `com.mattogrady.ggchat`, in Release builds as well:

1. `make phone`, then open ggchat once and force-quit it, so the launch
   timed is a cold one over the conversations already on the phone.
2. In Instruments, choose the App Launch template and the phone, and add
   the Points of Interest instrument from the library, which the template
   does not hold.
3. Record ggchat's launch.
4. Read `Open the store`, `Make the model` and `Load the store` under
   Points of Interest, beside the time to the first frame.

A first launch, after deleting the app and installing it again, times an
empty store being made rather than a full one being read: worth timing as
well, but separately.

`make uitest-device-engine` walks gglib's own engine on the phone `DEVICE`
names, as Xcode names it: no simulator runs it, so no other walk can. Its
walk adds This iPhone at launch with the model `GGCHAT_LIVE_ENGINE_MODEL`
names, which must already be downloaded to the phone through the model
browser, under the name its model list shows; sends, and waits for the pill
to read Ready and the ring to rise; puts the app in the background, comes
back to a pill that reads Not loaded, and sends again:

```sh
DEVICE='My iPhone' GGCHAT_LIVE_ENGINE_MODEL=Qwen3-0.6B-Q4_K_M make uitest-device-engine
```

It is signed for the phone as `make phone` is, so the provisioning profile
must carry the increased memory limit the iOS app asks for. The walk takes
an `on-device-reply` screenshot of the reply; it is not in the table above,
since only a phone can take it.

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
halves of the live suite. The walk pastes the key into the provider form, so
a gglib that enforces one is reachable; before this it entered none and could
only pass against a gglib that enforced none. It pastes rather than types
because XCUITest writes typed text into `xcodebuild`'s output and the result
bundle, and it empties the pasteboard afterwards, since the Simulator can
share it with the Mac's. With neither variable set it falls back to probing
`127.0.0.1:8080` and skips when nothing answers, which is what keeps CI,
where no gglib runs, green. `xcodebuild` hands a test runner on a simulator
only the variables named `TEST_RUNNER_<NAME>`, so the Makefile and
`scripts/screenshots.sh` forward them under that prefix; setting the bare
names on an `xcodebuild` invocation of your own will not reach the walk.

The builds are signed ad-hoc, because an unsigned iOS app has no Keychain
access and this app keeps every credential there.

`make uitest-ipad` runs the same walk on an iPad, which is not a larger
iPhone: the root is a `NavigationSplitView`, so the sidebar and the
conversation are two columns rather than a stack, and Settings is on
screen instead of one screen back. It is the leg CI runs, and like CI it
leaves out the Reduce Transparency reading, which has been measured on
iPhones only. CI runs the walk on both families.

`make uitest-duo` runs it on an iPhone Duo, whose open inner display is the
iPad's two columns and whose closed outer display is the iPhone's stack.
`simctl` cannot set the pose, so the walk runs in whichever one the
simulator is in, closed when it boots, and the half-open poses are looked
at by hand in Xcode's Device Hub. It needs the iOS 27.1 runtime and Xcode
27.1, which the CI runners do not have, so no CI leg runs it. The walk was
written for taller screens and for a sidebar that is either a screen back
or on screen: the closed outer display is 678 points tall, which hides a
form's lower fields under the keyboard and scrolls a sheet's header away,
and the open inner display in portrait is regular width with the sidebar
behind a button, where the walks that tap the sidebar's Providers button
stop. On 2026-10-22, closed, nineteen of twenty-seven cases passed before
the sheet's Add and the Thinking switch were taught to the walk; the two
pastes, of a key with ⌘V and of a picture through the add-image menu, land
nothing there, and the branching walk cannot bring the reply's label clear
of the bars. The two live cases need a key for the server on port 8080.

`make uitest-dark` and `make uitest-contrast` run the same walk with the
device set to dark mode and to Increase Contrast. Both are settings on the
simulator rather than launch arguments, so each target sets one, checks
`simctl` reads it back, and restores it afterwards even if the walk fails.
Reduce Transparency has no `simctl` option and no working launch argument,
so its test sets it through Settings and measures the result instead.

## Layout

```
Sources/GGChatCore/   no SwiftUI; the provider protocol, wire types, SSE, the pipe and pairing seams, mocks
Sources/GGChatPipe/   the only target that links modelpipe-ffi; no UI framework either
Sources/GGChatLocal/  the only target that imports gglib's binding; no UI framework either
Sources/GGLib/        gglib's generated Swift, vendored from the release as it stands
Sources/GGChatUI/     SwiftUI; the app model, views, and SwiftData persistence
App/                  the xcodegen spec, the generated project, and a @main struct with assets
Tests/GGChatCoreTests XCTest; fixtures are real captures from gglib, but for the one named contract-*
Tests/GGChatPipeTests that the binding is linked and its statuses cross unchanged
Tests/GGChatLocalTests gglib's framework linked, its library and its engine over fakes, and a reply it recorded
Tests/GGChatUITests   the app model, streaming, the pipe, and the SwiftData store
App/ggchatUITests     XCUITest that drives the first-run flow on a simulator
docs/adr/             decisions, each with a kill criterion that names a reading
scripts/              the checks CI runs; `make ci` runs the same ones, and the app icon's source
```

## The seam

The pipe path stops at two protocols, `PipeConnector` and `PipeSession`.
[docs/ffi-seam.md](ffi-seam.md) states what `modelpipe-ffi` must
provide in their terms, and which tests already assert each behaviour
against the mock.

## Decisions

- [ADR 0001](adr/0001-loopback-port-at-the-ffi-seam.md): a loopback
  port, not a request API, at the ffi seam.
- [ADR 0002](adr/0002-an-in-flight-request-is-kept-not-re-sent.md): an
  in-flight request on reconnect is kept, not re-sent.
- [ADR 0003](adr/0003-keychain-access-group.md): rejected. Credentials
  stay on the device and build that saved them; each machine is paired, or
  has its key typed, once.
- [ADR 0004](adr/0004-the-connect-identity-is-a-file.md): this device's
  endpoint key is a file, one per machine — not a credential, and not in the
  Keychain, because the binding writes it itself.
- [ADR 0005](adr/0005-a-system-prompt-is-a-conversation-setting.md): a
  system prompt is a setting of the conversation, sent ahead of every request,
  not a turn in the transcript.
- [ADR 0007](adr/0007-a-hubs-chats-are-read-live-and-never-stored.md): a
  paired Mac's chats are read live and never stored; only the titles its list
  last showed, and when, are kept. Amended: a Mac's chat is carried on from
  here and the Mac writes the reply; only the run's id and chat are kept.
- [ADR 0008](adr/0008-the-ring-shows-gglibs-reading-never-an-estimate.md):
  the context ring draws the reading gglib reported, and is hidden rather
  than estimated when gglib reported no context size.
- [ADR 0009](adr/0009-thinking-is-a-conversation-setting.md): thinking
  is a setting of the conversation, offered only where gglib lists the model
  as one that thinks; a Mac's chat keeps its own, and this phone stores
  nothing of it.
- [ADR 0010](adr/0010-history-is-never-rewritten.md): a saved reply is
  never rewritten. A change that would discard or alter one copies the chat,
  as far as the change, into a new conversation of its family, by gglib's
  rules; a Mac's chat is changed by the Mac, and nothing of it is copied
  here.
- [ADR 0011](adr/0011-a-picture-is-asked-for-with-a-switch.md): a
  picture is asked for with a Draw switch, one message at a time, of a hub
  that said it can draw; what is shown while it is drawn is never kept, and
  the picture a conversation kept here asked for is kept in this device's
  store. Amended: a drawn picture is fixed or drawn again from itself, and
  joins its chat only on Keep.
- [ADR 0012](adr/0012-a-reply-in-flight-is-per-conversation.md): a
  reply in flight is per conversation, so a send in one never waits for a
  reply in another; gglib queues the second request.
- [ADR 0013](adr/0013-tools-are-a-conversation-switch.md): whether a
  question may call a paired Mac's tools is a switch of the conversation,
  on until turned off; which MCP servers the Mac offers is chosen on the
  Mac and only read here. Superseded in part by ADR 0014.
- [ADR 0014](adr/0014-each-conversation-picks-which-of-the-macs-servers-it-uses.md):
  each conversation picks, by id, which of the paired Mac's offered MCP
  servers it uses, under a stored master switch, and a new one picks none;
  the wrench is badged while the Mac offers a server the conversation has
  not shown, until a change is made from its menu.
- [ADR 0015](adr/0015-the-on-device-engine-is-foreground-only.md):
  this iPhone's engine runs in the foreground only; it is served when a
  conversation on it opens or a send needs it, loads a model with the first
  request that names one, and is put down on the way to the background,
  after the replies, and on a memory warning while no reply goes through
  it.

## Releases

Versions come from [release-please](https://github.com/googleapis/release-please):
conventional commit titles on `main` accumulate into a release PR, and
merging it tags the version and rewrites `Config/Version.xcconfig`.
Documentation is built with DocC and published to
<https://mmogr.github.io/ggchat/> by every push to `main`, so the site
describes the code on `main` rather than the last release. That build is
not the one `make docs` and CI's Docs job run -- only it passes
`--transform-for-static-hosting` and a hosting base path -- so a change
that breaks the published form is caught by the commit that made it.
`GGChatCore` and `GGChatUI` are published; `GGChatPipe` and `GGChatLocal`
are not, so a doc comment behind either seam is compiled by `make docs` but
does not reach the site.

Dependabot proposes Swift package and GitHub Actions updates once a week.
To update the Swift packages now, run Actions → Update dependencies → Run
workflow, or
`gh workflow run update-deps.yml -R mmogr/ggchat` (add
`-f package=modelpipe-ffi` for one pin): it runs `swift package update` and
opens a PR listing each pin it moved, or says there is nothing to update.
gglib's frameworks are no package dependency, and neither moves them: a
gglib release is taken with `scripts/pin_gglib.sh`, as Building and testing
says.

## House rules

- Commit messages and PR titles say what the system now does, as a
  sentence: `feat(chat): the composer keeps its draft across a provider switch`.
- Every sentence in this README is true, and where a claim can be tested a
  test keeps it. `scripts/check_readme_claims.sh` checks that every marker
  above names a test that exists.
- One writer for the pipe status: `pipeStatuses` is written only by
  `setPipeStatus(_:for:cutShort:)`, which is also where the last-heard mark,
  the haptic and a send waiting for the pipe hear of a change, so a close the
  app shows is one they all hear about.
  `scripts/check_one_status_writer.sh` refuses any other write.
- No credential in any log line, ever.
- Time is an argument: nothing in `GGChatCore` reads the clock except
  `Clock.swift`.

