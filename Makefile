# Local parity with CI: `make ci` runs what the workflow runs, except the
# UI-test legs, which need a booted simulator -- `make uitest` and friends run
# those.
SWIFT_SOURCES := Sources Tests Package.swift $(wildcard App/ggchat/*.swift) $(wildcard App/ggchatUITests/*.swift)

.PHONY: screenshots project bootstrap fmt fmt-check lint analyze boundaries enforce build build-app build-app-release test test-live uitest uitest-dark uitest-contrast unused docs ci

project:
	cd App && xcodegen generate --quiet

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
	grep -q -- '-module-name GGChatCore' $(ANALYZE_LOG) \
		|| { echo 'analyze: the build printed no compile commands, so nothing was analysed' >&2; exit 1; }
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

build-app:
	$(APP_BUILD) -destination 'platform=macOS'
	$(APP_BUILD) -destination 'generic/platform=iOS Simulator'

# The Release configuration, compiled. Nothing else compiles it: the scheme's
# run and test actions are Debug, `xcodebuild build` with no -configuration
# takes the run action's, and the archive action that is Release is run by no
# target and no workflow. So the `#else` arm of every `#if DEBUG` -- which is
# everything the shipped app does differently from a development build -- had
# never been handed to a compiler by any gate.
build-app-release:
	$(APP_BUILD) -configuration Release -destination 'platform=macOS'
	$(APP_BUILD) -configuration Release -destination 'generic/platform=iOS Simulator'

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

UITEST = xcodebuild test -project App/ggchat.xcodeproj -scheme ggchat \
	-only-testing:ggchatUITests \
	CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES -quiet

# The udid of the simulator named $(SIMULATOR), newest runtime first. A
# display setting has to be applied to the same device the walk then runs on,
# and `name=` never says which device that was. Sorted on a tuple of integers
# because sorting the runtime keys as strings puts iOS-18-4 above iOS-26-5.
udid = $$(xcrun simctl list devices available --json | python3 -c "import json,re,sys;d=json.load(sys.stdin)['devices'];v=lambda k:tuple(map(int,re.findall(r'\d+',k)));print(next(x['udid'] for k in sorted((k for k in d if 'iOS' in k),key=v,reverse=True) for x in d[k] if x['name']=='$(SIMULATOR)'))")

# Drives the app on a booted iPhone simulator. The live half of the test
# runs only when something is listening on 127.0.0.1:8080.
uitest:
	$(UITEST) -destination 'platform=iOS Simulator,name=$(SIMULATOR)'

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
		--target GGChatUI --warnings-as-errors --output-path .build/docs/GGChatUI

ci: fmt-check lint analyze boundaries enforce build build-app build-app-release test unused docs
