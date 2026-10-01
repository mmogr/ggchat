#!/usr/bin/env bash
# The phone `make phone` installs on, as `xcrun devicectl --device` takes it.
#
# DEVICE wins when it is set, handed on as it is: a name, a UDID or the
# identifier `xcrun devicectl list devices` prints. Otherwise the answer is
# the one iPhone devicectl lists and does not call unavailable. None, or more
# than one, is a sentence on stderr, exit 1 and nothing on stdout, rather than
# a guess: an install on the wrong phone, or one that waits for a phone that
# is not there, is worse than a refusal that says what to set.
#
# A path in place of asking devicectl reads a listing saved with
# `--json-output`; scripts/check_phone_device.sh checks the picking that way,
# with no phone and no Xcode.
#
# Usage: scripts/phone_device.sh [listing.json]
set -euo pipefail

if [ -n "${DEVICE:-}" ]; then
    printf '%s\n' "$DEVICE"
    exit 0
fi

if [ $# -gt 0 ]; then
    listing="$1"
else
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' EXIT
    listing="$dir/devices.json"
    xcrun devicectl list devices --json-output "$listing" > /dev/null
fi

python3 - "$listing" <<'PY'
import json, sys

with open(sys.argv[1]) as listing:
    devices = json.load(listing).get("result", {}).get("devices", [])
phones = [
    device for device in devices
    if device.get("hardwareProperties", {}).get("deviceType") == "iPhone"
    and device.get("connectionProperties", {}).get("tunnelState") != "unavailable"
]
if not phones:
    sys.exit("phone: no iPhone is connected; plug one in, or set DEVICE to its name or UDID")
if len(phones) > 1:
    names = ", ".join(phone.get("deviceProperties", {}).get("name", phone["identifier"]) for phone in phones)
    sys.exit(f"phone: more than one iPhone is connected ({names}); set DEVICE to the one to install on")
print(phones[0]["identifier"])
PY
