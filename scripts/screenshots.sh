#!/usr/bin/env bash
# Regenerates the screenshots in the README from a UI test run, so they are
# pictures of the app as it is rather than as it once was.
#
# Usage: scripts/screenshots.sh [simulator-name]
#
# Start gglib first if you want the live ones. Each image below is an
# attachment a test takes by name; if a test stops taking one, this says so
# rather than leaving a stale picture in place.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMULATOR="${1:-iPhone 17 Pro}"
OUT="$ROOT/docs/screenshots"
BUNDLE="$(mktemp -d)/ui.xcresult"

# attachment name -> file name in docs/screenshots
WANTED="04-reply-complete-live:iphone-reply pipe-connected:iphone-pipe-connected proxy-status-pane:iphone-server-status"

cd "$ROOT"
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
        status=1
        continue
    fi
    cp "$EXPORT/$file" "$OUT/$target.png"
    sips -Z 620 "$OUT/$target.png" >/dev/null
    echo "$target.png"
done

echo "macos-chat.png is taken by hand; the UI tests only drive the simulator"
exit $status
