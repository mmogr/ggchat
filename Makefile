# Local parity with CI: `make ci` runs what the workflow runs.
SWIFT_SOURCES := Sources Tests Package.swift $(wildcard App/ggchat/*.swift) $(wildcard App/ggchatUITests/*.swift)

.PHONY: screenshots project bootstrap fmt fmt-check lint boundaries enforce build test test-live uitest uitest-dark uitest-contrast unused docs ci

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

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test --parallel

# Against a running gglib: GGCHAT_LIVE_BASE_URL=http://127.0.0.1:8080/v1 make test-live
test-live:
	swift test --filter LiveGGLibTests

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

ci: fmt-check lint boundaries enforce build test unused docs
