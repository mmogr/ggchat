#!/usr/bin/env bash
# Regenerates the screenshots in the README from a UI test run, so they are
# pictures of the app as it is rather than as it once was.
#
# Usage: scripts/screenshots.sh [simulator-name]
#
# Start gglib first: two of the three images below are taken only by the live
# walks. If yours enforces an API key, set GGCHAT_LIVE_BASE_URL and
# GGCHAT_LIVE_API_KEY too, or those walks reach a server that refuses them.
# Each image is an attachment a test takes by name; if a test stops taking
# one, this says so rather than leaving a stale picture in place.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMULATOR="${1:-iPhone 17 Pro}"
OUT="$ROOT/docs/screenshots"
BUNDLE="$(mktemp -d)/ui.xcresult"

# attachment name -> file name in docs/screenshots. Only pipe-connected is
# hermetic; the other two come from the live walks and need a server.
WANTED="04-reply-complete-live:iphone-reply pipe-connected:iphone-pipe-connected proxy-status-pane:iphone-server-status"
LIVE_ONLY="04-reply-complete-live proxy-status-pane"

cd "$ROOT"
# A test runner on a simulator is handed only the variables named
# TEST_RUNNER_<NAME>, with the prefix stripped, so the live walks can read
# these only if they are forwarded that way. Unset forwards as empty, which
# the walks read as unset: they then probe 127.0.0.1:8080 and run if gglib is
# there, which is what this script has always relied on.
TEST_RUNNER_GGCHAT_LIVE_BASE_URL="${GGCHAT_LIVE_BASE_URL-}" \
    TEST_RUNNER_GGCHAT_LIVE_API_KEY="${GGCHAT_LIVE_API_KEY-}" \
    xcodebuild test -project App/ggchat.xcodeproj -scheme ggchat \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    -resultBundlePath "$BUNDLE" -only-testing:ggchatUITests \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES -quiet

EXPORT="$(mktemp -d)"
xcrun xcresulttool export attachments --path "$BUNDLE" --output-path "$EXPORT" >/dev/null

status=0
for pair in $WANTED; do
    attachment="${pair%%:*}"
    target="${pair##*:}"
    file=$(python3 -c "
import json, sys
manifest = json.load(open('$EXPORT/manifest.json'))
for test in manifest:
    for a in test.get('attachments', []):
        if a.get('suggestedHumanReadableName', '').startswith('$attachment'):
            print(a['exportedFileName']); raise SystemExit
")
    if [ -z "$file" ]; then
        echo "no test took a screenshot named $attachment" >&2
        case " $LIVE_ONLY " in
            *" $attachment "*)
                echo "  that one is taken only by the live walk: start gglib, and if it wants a key set" >&2
                echo "  GGCHAT_LIVE_BASE_URL and GGCHAT_LIVE_API_KEY before running this" >&2
                ;;
        esac
        status=1
        continue
    fi
    cp "$EXPORT/$file" "$OUT/$target.png"
    sips -Z 620 "$OUT/$target.png" >/dev/null
    echo "$target.png"
done

echo "macos-chat.png is taken by hand; the UI tests only drive the simulator"
exit $status
