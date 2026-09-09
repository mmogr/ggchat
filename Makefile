# Local parity with CI: `make ci` runs what the workflow runs, except the
# UI-test legs, which need a booted simulator -- `make uitest` and friends run
# those.
SWIFT_SOURCES := Sources Tests Package.swift $(wildcard App/ggchat/*.swift) $(wildcard App/ggchatUITests/*.swift)

.PHONY: icon build-app-device screenshots project bootstrap fmt fmt-check lint analyze boundaries enforce build build-release build-app build-app-release test test-live uitest uitest-ipad uitest-dark uitest-contrast unused docs ci

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
	# ours means the analyzer had nothing to look at.
	for module in GGChatCore GGChatPipe GGChatUI; do \
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
# proven; installing on a phone is Xcode's job and needs the profile.
build-app-device:
	xcodebuild build -project App/ggchat.xcodeproj -scheme ggchat \
		-configuration Release -destination 'generic/platform=iOS' \
		CODE_SIGNING_ALLOWED=NO -quiet

build-release:
	swift build -c release -Xswiftc -warnings-as-errors
	scripts/check_no_mock_in_release.sh

test:
	swift test --parallel

# Against a running gglib: GGCHAT_LIVE_BASE_URL=http://127.0.0.1:8080/v1 make test-live
# The filter names both live suites: LiveGGLibTests in the core tests and
# LiveAppModelTests in the UI tests. Naming only the first, as this did, could
# never select the second, so the README's recipe ran two of the three live
# cases and never the end-to-end one. Every live test skips itself when the
# base URL is unset, so without the guard the target passes having exercised
# nothing at all.
test-live:
	@[ -n "$$GGCHAT_LIVE_BASE_URL" ] \
		|| { echo 'test-live: set GGCHAT_LIVE_BASE_URL first, or every live test skips and this passes having run nothing' >&2; exit 1; }
	swift test --filter 'Live[A-Za-z]*Tests'

# Which simulator the UI test targets drive. Override on the command line:
# `make uitest SIMULATOR='iPhone 16'`.
SIMULATOR ?= iPhone 17 Pro

# Where the live walks point, and the key they type. A test runner on a
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

# The udid of the simulator named $(SIMULATOR), newest runtime first. A
# display setting has to be applied to the same device the walk then runs on,
# and `name=` never says which device that was. Sorted on a tuple of integers
# because sorting the runtime keys as strings puts iOS-18-4 above iOS-26-5.
udid = $$(xcrun simctl list devices available --json | python3 -c "import json,re,sys;d=json.load(sys.stdin)['devices'];v=lambda k:tuple(map(int,re.findall(r'\d+',k)));print(next(x['udid'] for k in sorted((k for k in d if 'iOS' in k),key=v,reverse=True) for x in d[k] if x['name']=='$(SIMULATOR)'))")

# Drives the app on a booted iPhone simulator. The live half runs against
# GGCHAT_LIVE_BASE_URL when it is set, typing GGCHAT_LIVE_API_KEY into the
# form; with neither set it falls back to 127.0.0.1:8080 and runs only when
# something is listening there:
#
#   GGCHAT_LIVE_BASE_URL=http://127.0.0.1:8080/v1 GGCHAT_LIVE_API_KEY=sk-... make uitest
uitest:
	$(UITEST) -destination 'platform=iOS Simulator,name=$(SIMULATOR)'

# Which iPad. The layout is the point rather than the model: the root is a
# NavigationSplitView, a stack on an iPhone and two columns here.
IPAD ?= iPad Pro 13-inch (M5)

# The iPad leg CI runs, which is the whole walk without the Reduce
# Transparency reading. That one is a measurement, not a walk: its bands are
# fractions of an iPhone's screen, so on an iPad both of them are mostly
# background and it fails on the shape of the picture. `make uitest` pointed
# at an iPad runs it and fails there, which is why this target exists rather
# than a note in the README.
uitest-ipad:
	$(UITEST) -skip-testing:ggchatUITests/ReduceTransparencyUITests \
		-destination 'platform=iOS Simulator,name=$(IPAD)'

# Dark and Increase Contrast are settings on the device, not launch
# arguments, so the device is booted and set first. `simctl ui` prints what it
# reads, so the setting is checked and not assumed, and the trap puts the
# simulator back the way it was found even when the walk fails.
uitest-dark:
	udid=$(udid); xcrun simctl boot "$$udid" || true; xcrun simctl bootstatus "$$udid" -b; \
	trap 'xcrun simctl ui "$$udid" appearance light' EXIT; \
	xcrun simctl ui "$$udid" appearance dark; \
	[ "$$(xcrun simctl ui "$$udid" appearance)" = dark ] || { echo 'the simulator stayed light' >&2; exit 1; }; \
	$(UITEST) -destination "id=$$udid"

uitest-contrast:
	udid=$(udid); xcrun simctl boot "$$udid" || true; xcrun simctl bootstatus "$$udid" -b; \
	trap 'xcrun simctl ui "$$udid" increase_contrast disabled' EXIT; \
	xcrun simctl ui "$$udid" increase_contrast enabled; \
	[ "$$(xcrun simctl ui "$$udid" increase_contrast)" = enabled ] || { echo 'increase contrast did not take' >&2; exit 1; }; \
	$(UITEST) -destination "id=$$udid"

# Refreshes docs/screenshots from a UI test run.
screenshots:
	scripts/screenshots.sh '$(SIMULATOR)'

unused:
	periphery scan --quiet --strict

docs:
	mkdir -p .build/docs
	swift package --allow-writing-to-directory .build/docs generate-documentation \
		--target GGChatCore --warnings-as-errors --output-path .build/docs/GGChatCore
	swift package --allow-writing-to-directory .build/docs generate-documentation \
		--target GGChatPipe --warnings-as-errors --output-path .build/docs/GGChatPipe
	swift package --allow-writing-to-directory .build/docs generate-documentation \
		--target GGChatUI --warnings-as-errors --output-path .build/docs/GGChatUI

ci: fmt-check lint analyze boundaries enforce build build-release build-app build-app-release build-app-device test unused docs
