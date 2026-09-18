#!/usr/bin/env bash
# The udid of the available iOS simulator named $1, on the newest runtime
# that has one. `-destination 'platform=iOS Simulator,name=…'` looks only at
# the newest runtime installed (OS:latest), so a name that runtime lacks
# matches nothing even when an older one has it; an id names one device, and
# is also how a display setting reaches the device a walk then runs on.
#
# Sorted on a tuple of integers, because sorting the runtime keys as strings
# would put iOS-9-3 above iOS-18-4, and iOS-26-5 above iOS-26-10. A name no
# installed runtime has is a sentence on stderr, exit 1, and nothing on
# stdout, so a caller never hands xcodebuild `id=`.
#
# Usage: scripts/simulator_udid.sh 'iPhone 17 Pro'
set -euo pipefail

name="${1:?usage: scripts/simulator_udid.sh <simulator name>}"
xcrun simctl list devices available --json | NAME="$name" python3 -c "
import json, os, re, sys
name = os.environ['NAME']
devices = json.load(sys.stdin)['devices']
newest_first = sorted((k for k in devices if 'iOS' in k), key=lambda k: tuple(map(int, re.findall(r'\d+', k))), reverse=True)
udid = next((d['udid'] for k in newest_first for d in devices[k] if d['name'] == name), None)
print(udid) if udid else sys.exit(f'no available iOS simulator named {name}')
"
