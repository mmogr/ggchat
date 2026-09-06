# Local parity with CI: `make ci` runs what the workflow runs.
SWIFT_SOURCES := Sources Tests Package.swift $(wildcard App/ggchat/*.swift) $(wildcard App/ggchatUITests/*.swift)

.PHONY: project bootstrap fmt fmt-check lint boundaries enforce build test test-live uitest unused docs ci

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

# Drives the app on a booted iPhone simulator. The live half of the test
# runs only when something is listening on 127.0.0.1:8080.
uitest:
	xcodebuild test -project App/ggchat.xcodeproj -scheme ggchat \
		-destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
		-only-testing:ggchatUITests CODE_SIGNING_ALLOWED=NO -quiet

unused:
	periphery scan --quiet --strict

docs:
	mkdir -p .build/docs
	swift package --allow-writing-to-directory .build/docs generate-documentation \
		--target GGChatCore --warnings-as-errors --output-path .build/docs/GGChatCore
	swift package --allow-writing-to-directory .build/docs generate-documentation \
		--target GGChatUI --warnings-as-errors --output-path .build/docs/GGChatUI

ci: fmt-check lint boundaries enforce build test unused docs
