# Local parity with CI: `make ci` runs what the workflow runs, except the
# UI-test legs, which need a booted simulator -- `make uitest` and friends run
# those.
# Every target's sources but Sources/GGLib, which is gglib's generated Swift,
# vendored as released and held to the release by check_gglib_take.sh rather
# than formatted here.
SWIFT_SOURCES := $(filter-out Sources/GGLib,$(wildcard Sources/*)) Tests Package.swift \
	$(wildcard App/ggchat/*.swift) $(wildcard App/ggchatUITests/*.swift)

.PHONY: icon build-app-device phone screenshots project bootstrap fmt fmt-check lint analyze boundaries enforce build build-release build-app build-app-release test test-live test-live-library test-live-engine test-pipe record-phone-stream uitest uitest-device-engine uitest-ipad uitest-duo uitest-dark uitest-contrast unused docs ci

project:
	cd App && xcodegen generate --quiet

# The app icon is drawn by a script rather than stored as art nobody can
# regenerate: `scripts/make_app_icon.swift` is the source, and this writes the
# eleven PNGs the asset catalogue names straight into it. Rerun it after
# changing a curve; the mark centres itself on its own bounding box, so the
# sizes do not need re-tuning by hand.
icon:
	swift scripts/make_app_icon.swift App/ggchat/Assets.xcassets/AppIcon.appiconset

bootstrap:
	brew install xcodegen swiftlint periphery actionlint

fmt:
	swift format format --in-place --recursive $(SWIFT_SOURCES)

fmt-check:
	swift format lint --strict --recursive $(SWIFT_SOURCES)

lint:
	swiftlint lint --strict --quiet
	actionlint

# SwiftLint's analyzer rules need the arguments the compiler was actually
# given, and only a verbose build prints them. `swiftlint lint` reads the
# source and nothing else, so it cannot run them: without this target the
# `analyzer_rules` block in .swiftlint.yml is a list no command reads.
ANALYZE_PATH = .build/analyze
ANALYZE_LOG = $(ANALYZE_PATH)/compile.log
ANALYZE_SOURCEKIT = $(ANALYZE_PATH)/sourcekit.log
analyze:
	# A warm scratch path recompiles nothing and so prints no compile
	# command for our targets, and swiftlint given such a log analyses no
	# files and exits 0 -- it passes a source it never looked at. The other
	# jobs cache .build, so this goes before anything else here.
	rm -rf $(ANALYZE_PATH)
	mkdir -p $(ANALYZE_PATH)
	swift build --build-tests --scratch-path $(ANALYZE_PATH) -v > $(ANALYZE_LOG) 2>&1 \
		|| { tail -40 $(ANALYZE_LOG) >&2; exit 1; }
	# The gate refuses to pass vacuously: no compile line for a target of
	# ours means the analyzer had nothing to look at. GGLib is gglib's
	# generated Swift, which .swiftlint.yml excludes.
	for module in GGChatCore GGChatPipe GGChatLocal GGChatUI; do \
		grep -q -- "-module-name $$module" $(ANALYZE_LOG) \
			|| { echo "analyze: no compile command for $$module, so it was not analysed" >&2; exit 1; }; \
	done
	# Violations go to stdout. sourcekit writes a compiler banner per file
	# and type-checks iOS-only sources against the macOS args they were not
	# built with, all on stderr, so that is kept in a file instead.
	swiftlint analyze --strict --quiet --compiler-log-path $(ANALYZE_LOG) 2> $(ANALYZE_SOURCEKIT) \
		|| { echo "analyze: sourcekit output is in $(ANALYZE_SOURCEKIT)" >&2; exit 1; }

boundaries:
	scripts/check_boundaries.sh

enforce:
	scripts/check_glass_sites.sh
	scripts/check_no_hand_drawn_glass.sh
	scripts/check_time_is_an_argument.sh
	scripts/check_one_status_writer.sh
	scripts/check_no_print.sh
	scripts/check_log_calls.sh
	scripts/check_file_size.sh
	scripts/check_readme_claims.sh
	scripts/check_test_counts.sh
	scripts/check_phone_device.sh
	# Last, because it needs the network and refuses a tree that pins no
	# release, which every check above can still be read on.
	scripts/check_gglib_take.sh

build:
	swift build -Xswiftc -warnings-as-errors

# The app target, which lives outside the package build. Ad-hoc signing, not
# none: an unsigned iOS app has no Keychain access, and the app keeps every
# credential there. Warnings-as-errors is set on the app target in
# App/project.yml, not here: on the command line it would also apply to the
# package dependencies, and swift-markdown compiles with warnings suppressed.
APP_BUILD = xcodebuild build -project App/ggchat.xcodeproj -scheme ggchat \
	CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES -quiet

# Debug, said out loud. `xcodebuild build` with no `-configuration` takes the
# scheme's run action, and that is now Release so that pressing Run in Xcode
# gives the app that dials rather than the one that mocks. Inheriting it here
# would have quietly stopped compiling the `#if DEBUG` arms in the app target
# -- the mock connector, the mock provider, the Force-closed control -- and
# made this target a duplicate of `build-app-release`.
build-app:
	$(APP_BUILD) -configuration Debug -destination 'platform=macOS'
	$(APP_BUILD) -configuration Debug -destination 'generic/platform=iOS Simulator'

# The app target in Release. Nothing else compiles it that way: the scheme's
# run and test actions are Debug, `xcodebuild build` with no -configuration
# takes the run action's, and the archive action that is Release is run by no
# target and no workflow. What it covers is the app target itself -- its
# generated project and its signing settings -- built as a shipped one is.
# The `#if DEBUG` arms are all in `Sources`; `build-release` below compiles
# those, and is the only one that leaves objects a checker can read.
build-app-release:
	$(APP_BUILD) -configuration Release -destination 'platform=macOS'
	$(APP_BUILD) -configuration Release -destination 'generic/platform=iOS Simulator'

# The Release configuration, and then what only a release build can be asked:
# whether the DEBUG-only types are really gone. `make build` never compiles the
# `#else` arm of an `#if DEBUG`, and the checker needs objects to read, so the
# two are one target. This is not in `enforce`: that job runs on Linux, and
# this one needs a Swift toolchain and the macOS SDK.
# The device SDK, which nothing else compiles. Every other app build targets
# a simulator or macOS, and those are x86_64-capable and share the host's
# frameworks -- so a problem that is specific to `iphoneos` and arm64 would
# first appear during an archive, after the signing work, to whoever was
# trying to ship.
#
# Signing is off rather than ad-hoc: `CODE_SIGN_IDENTITY=-` is refused
# outright by the iOS SDK, and a real identity would need a provisioning
# profile from Apple, which is not a thing a build check should reach for.
# What this proves is the compile and the link, which is what has never been
# proven; installing on a phone is `make phone`'s job and needs the profile.
build-app-device:
	xcodebuild build -project App/ggchat.xcodeproj -scheme ggchat \
		-configuration Release -destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=NO -quiet

build-release:
	swift build -c release -Xswiftc -warnings-as-errors
	scripts/check_no_mock_in_release.sh

# Builds the app in Release, as Xcode's Run does, signed for a phone, and
# installs it on the one iPhone this Mac can reach, or on DEVICE (a name, a
# UDID or devicectl's identifier): `make phone DEVICE='My iPhone'`. A build
# signed by a free team stops opening when its profile runs out, seven days
# after the profile was issued, so this is the refresh in one command.
# `-allowProvisioningUpdates` lets xcodebuild fetch a new profile when the
# last one has run out, through the Apple ID signed in to Xcode. The phone is
# picked first, so a missing one is said before minutes of compiling rather
# than after them.
PHONE_BUILD = .build/phone
phone:
	device=$$(scripts/phone_device.sh) || exit 1; \
	xcodebuild build -project App/ggchat.xcodeproj -scheme ggchat -configuration Release \
		-destination 'generic/platform=iOS' -derivedDataPath $(PHONE_BUILD) -allowProvisioningUpdates -quiet \
		&& xcrun devicectl device install app --device "$$device" $(PHONE_BUILD)/Build/Products/Release-iphoneos/ggchat.app

test:
	swift test --parallel

# Against a running gglib: GGCHAT_LIVE_BASE_URL=http://127.0.0.1:8080/v1 make test-live
# The filter names both live suites: LiveGGLibTests in the core tests and
# LiveAppModelTests in the UI tests. It also matches LiveLibraryTests, which
# skips itself here without GGCHAT_LIVE_HF (make test-live-library). Naming only the first, as this did, could
# never select the second, so the README's recipe ran two of the three live
# cases and never the end-to-end one. Every live test skips itself when the
# base URL is unset, so without the guard the target passes having exercised
# nothing at all.
test-live:
	@[ -n "$$GGCHAT_LIVE_BASE_URL" ] \
		|| { echo 'test-live: set GGCHAT_LIVE_BASE_URL first, or every live test skips and this passes having run nothing' >&2; exit 1; }
	swift test --filter 'Live[A-Za-z]*Tests'

# gglib's model library against Hugging Face itself, through the Mac's slice
# of the framework: a search, and a repository's quantizations judged against
# a phone's reading. Public repositories only, and no download. The suite
# skips itself unless GGCHAT_LIVE_HF=1, which this sets, so neither `make ci`
# nor CI reaches the network for it. Add GGLIB_FFI_LOCAL_XCFRAMEWORK=1 for a
# local gglib build, as for `make test`.
test-live-library:
	GGCHAT_LIVE_HF=1 swift test --filter LiveLibraryTests

# gglib's own engine, served on the Mac's slice with tinygemma3: the live
# test, and the recording PhoneStreamContractTests replays, written into
# Tests/GGChatLocalTests/Fixtures with a note of what made it. Both need
# GGLIB_ENGINE_MODELS_DIR, the folder holding tinygemma3-Q8_0.gguf, and
# GGLIB_FFI_ADD_MODEL, gglib's gglib-ffi-add-model, built in a gglib checkout
# with `cargo build -p gglib-ffi --features smoke --bin gglib-ffi-add-model`:
# the binding has no call that adds a file. Neither is in `ci`. The guard is
# `test-live`'s: unset, the test skips and the target would pass having run
# nothing.
LIVE_ENGINE_GUARD = [ -n "$$GGLIB_ENGINE_MODELS_DIR" ] && [ -n "$$GGLIB_FFI_ADD_MODEL" ] \
	|| { echo '$@: set GGLIB_ENGINE_MODELS_DIR and GGLIB_FFI_ADD_MODEL first, or the test skips and this passes having run nothing' >&2; exit 1; }

test-live-engine:
	@$(LIVE_ENGINE_GUARD)
	swift test --filter LiveGglibEngineTests

record-phone-stream:
	@$(LIVE_ENGINE_GUARD)
	GGCHAT_RECORD_PHONE_STREAM=1 swift test --filter PhoneStreamRecording

# ModelpipeConnector dialling a real `modelpipe serve` on this machine, with
# discovery, port mapping and the public relays off on both sides, and a
# request carried to the far edge and back. MODELPIPE_BIN names the binary,
# built with `cargo install modelpipe-cli --version <the binding's modelpipe>
# --locked`; .github/workflows/pipe.yml pins which. The guard is
# `test-live`'s, and GGCHAT_PIPE_REQUIRED=1 makes the test itself fail rather
# than skip, so neither can pass having dialled nothing. Not in `ci`: it
# needs a Rust toolchain, and the Pipe workflow runs it instead.
test-pipe:
	@[ -n "$$MODELPIPE_BIN" ] \
		|| { echo 'test-pipe: set MODELPIPE_BIN to a modelpipe binary first, or the test skips and this passes having run nothing' >&2; exit 1; }
	GGCHAT_PIPE_REQUIRED=1 swift test --filter RealPipeTests

# Which simulator the UI test targets drive. Override on the command line:
# `make uitest SIMULATOR='iPhone 16'`.
SIMULATOR ?= iPhone 17 Pro

# Where the live walks point, and the key they paste. A test runner on a
# simulator does not inherit this environment: xcodebuild hands it only the
# variables named TEST_RUNNER_<NAME>, with the prefix stripped, so the bare
# names are unreadable in the runner without this. Forwarded unconditionally,
# because an unset variable arrives as the empty string and the walk reads
# that as unset -- it then falls back to probing 127.0.0.1:8080 and skips when
# nothing answers, which is what it has always done and what keeps CI green.
LIVE_ENV = TEST_RUNNER_GGCHAT_LIVE_BASE_URL="$$GGCHAT_LIVE_BASE_URL" \
	TEST_RUNNER_GGCHAT_LIVE_API_KEY="$$GGCHAT_LIVE_API_KEY"

UITEST = $(LIVE_ENV) xcodebuild test -project App/ggchat.xcodeproj -scheme ggchat \
	-only-testing:ggchatUITests \
	CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES -quiet

# The udid of the simulator named $(SIMULATOR), and of the one named
# $(IPAD), each on the newest runtime that has it. `name=` looks only at the
# newest runtime installed, which need not have that device at all, and never
# says which device it chose; a display setting has to be applied to the
# same device the walk then runs on. scripts/simulator_udid.sh picks the
# device for every recipe here and for scripts/screenshots.sh. A name no
# installed runtime has is a sentence on stderr and an empty result, and each
# recipe below refuses an empty udid rather than handing xcodebuild `id=`.
udid = $$(scripts/simulator_udid.sh '$(SIMULATOR)')
ipad_udid = $$(scripts/simulator_udid.sh '$(IPAD)')

# Drives the app on a booted iPhone simulator. The live half runs against
# GGCHAT_LIVE_BASE_URL when it is set, pasting GGCHAT_LIVE_API_KEY into the
# form, since XCUITest writes typed text into its output and the result
# bundle; with neither set it falls back to 127.0.0.1:8080 and runs only when
# something is listening there:
#
#   GGCHAT_LIVE_BASE_URL=http://127.0.0.1:8080/v1 GGCHAT_LIVE_API_KEY=sk-... make uitest
uitest:
	udid=$(udid); [ -n "$$udid" ] || { echo 'uitest: no simulator udid' >&2; exit 1; }; \
	$(UITEST) -destination "id=$$udid"

# Which iPad. The layout is the point rather than the model: the root is a
# NavigationSplitView, a stack on an iPhone and two columns here.
IPAD ?= iPad Pro 13-inch (M5)

# The iPad leg CI runs, which is the whole walk without the Reduce
# Transparency reading. That one is a measurement, not a walk, and it has
# been measured on iPhones only. Its bands used to be fractions of an
# iPhone's screen, mostly background on an iPad, and it failed there on the
# shape of the picture; they now come from the composer's own frame, but
# nobody has read what an iPad's glass moves by. This target leaves it out
# until someone has, rather than a note in the README.
uitest-ipad:
	udid=$(ipad_udid); [ -n "$$udid" ] || { echo 'uitest-ipad: no simulator udid' >&2; exit 1; }; \
	$(UITEST) -skip-testing:ggchatUITests/ReduceTransparencyUITests -destination "id=$$udid"

# Which iPhone Duo. Open, its inner display is the iPad's layout; closed,
# its outer display is the iPhone's. simctl has no say over the pose, so the
# walk runs in whatever pose the simulator boots in and the other poses are
# looked at by hand in Device Hub. There is no CI leg: the runners' Xcode is
# 26.6, which has neither the iOS 27.1 runtime nor the device. The Reduce
# Transparency reading is left out for the iPad leg's reason.
DUO ?= iPhone Duo
duo_udid = $$(scripts/simulator_udid.sh '$(DUO)')

uitest-duo:
	udid=$(duo_udid); [ -n "$$udid" ] || { echo 'uitest-duo: no simulator udid' >&2; exit 1; }; \
	$(UITEST) -skip-testing:ggchatUITests/ReduceTransparencyUITests -destination "id=$$udid"

# gglib's own engine on a real iPhone, the walk OnDeviceLiveUITests takes on
# the phone named DEVICE, as Xcode names it, with GGCHAT_LIVE_ENGINE_MODEL
# naming a model already downloaded to it, as its model list names it:
#
#   DEVICE='My iPhone' GGCHAT_LIVE_ENGINE_MODEL=Qwen3-0.6B-Q4_K_M make uitest-device-engine
#
# Signed for the phone, as `make phone` signs, so the provisioning profile
# must carry the increased memory limit. No simulator runs gglib's engine and
# no CI leg has a phone, so this is in no other target.
uitest-device-engine:
	@[ -n "$$DEVICE" ] && [ -n "$$GGCHAT_LIVE_ENGINE_MODEL" ] \
		|| { echo 'uitest-device-engine: set DEVICE and GGCHAT_LIVE_ENGINE_MODEL first, or the walk skips' >&2; exit 1; }
	TEST_RUNNER_GGCHAT_LIVE_ENGINE_MODEL="$$GGCHAT_LIVE_ENGINE_MODEL" xcodebuild test -project App/ggchat.xcodeproj \
		-scheme ggchat -destination "platform=iOS,name=$$DEVICE" \
		-only-testing:ggchatUITests/OnDeviceLiveUITests -allowProvisioningUpdates -quiet

# Dark and Increase Contrast are settings on the device, not launch
# arguments, so the device is booted and set first. `simctl ui` prints what it
# reads, so the setting is checked and not assumed, and the trap puts the
# simulator back the way it was found even when the walk fails.
uitest-dark:
	udid=$(udid); [ -n "$$udid" ] || { echo 'uitest: no simulator udid' >&2; exit 1; }; xcrun simctl boot "$$udid" || true; xcrun simctl bootstatus "$$udid" -b; \
	trap 'xcrun simctl ui "$$udid" appearance light' EXIT; \
	xcrun simctl ui "$$udid" appearance dark; \
	[ "$$(xcrun simctl ui "$$udid" appearance)" = dark ] || { echo 'the simulator stayed light' >&2; exit 1; }; \
	$(UITEST) -destination "id=$$udid"

uitest-contrast:
	udid=$(udid); [ -n "$$udid" ] || { echo 'uitest: no simulator udid' >&2; exit 1; }; xcrun simctl boot "$$udid" || true; xcrun simctl bootstatus "$$udid" -b; \
	trap 'xcrun simctl ui "$$udid" increase_contrast disabled' EXIT; \
	xcrun simctl ui "$$udid" increase_contrast enabled; \
	[ "$$(xcrun simctl ui "$$udid" increase_contrast)" = enabled ] || { echo 'increase contrast did not take' >&2; exit 1; }; \
	$(UITEST) -destination "id=$$udid"

# Refreshes docs/screenshots from a UI test run.
screenshots:
	scripts/screenshots.sh '$(SIMULATOR)'

# Periphery reads an index store, and its own build writes one only under the
# native build system; from Swift 6.4 `swift build` defaults to swiftbuild,
# which writes a store only when asked. Asked for in a scratch path of its own,
# built from nothing each time, as `analyze` does with its compile log and for
# the same reason: a compiler writes a unit only for a file it compiles, so a
# warm path recompiles nothing and leaves the store describing an earlier
# tree, and a store shared with `build` and `test` goes stale the moment
# either recompiles a file without the flag. Periphery would then judge a
# source the store no longer describes. About half a minute cold.
# The gate also refuses to pass vacuously, as `analyze` does: periphery handed
# an empty store says "no unused code", so one source per module must have a
# unit in the store before it is asked. A unit is named after its object,
# `<File>.o-<hash>` under swiftbuild and `<File>.swift.o-<hash>` under the
# native build system, the same split as the release objects.
PERIPHERY_PATH = .build/periphery
PERIPHERY_STORE = $(PERIPHERY_PATH)/debug/index/store
unused:
	rm -rf $(PERIPHERY_PATH)
	swift build --build-tests --enable-index-store --scratch-path $(PERIPHERY_PATH)
	for unit in Ticket ModelpipeConnector GGLibBuild+GGLib RootView; do \
		find $(PERIPHERY_STORE) \( -name "$$unit.o-*" -o -name "$$unit.swift.o-*" \) -print -quit 2>/dev/null | grep -q . \
			|| { echo "unused: no index unit for $$unit, so periphery would scan nothing" >&2; exit 1; }; \
	done
	periphery scan --quiet --strict --index-store-path $(PERIPHERY_STORE)

# CPATH carries a module map naming GglibFFI by its header, which SwiftPM's
# native build system cannot otherwise show swift-symbolgraph-extract
# (scripts/docs_gglib_module.sh says why).
DOCC = CPATH="$$(scripts/docs_gglib_module.sh)" swift package --allow-writing-to-directory .build/docs generate-documentation

docs:
	mkdir -p .build/docs
	$(DOCC) --target GGChatCore --warnings-as-errors --output-path .build/docs/GGChatCore
	$(DOCC) --target GGChatPipe --warnings-as-errors --output-path .build/docs/GGChatPipe
	$(DOCC) --target GGChatLocal --warnings-as-errors --output-path .build/docs/GGChatLocal
	$(DOCC) --target GGChatUI --warnings-as-errors --output-path .build/docs/GGChatUI

ci: fmt-check lint analyze boundaries enforce build build-release build-app build-app-release build-app-device test unused docs
