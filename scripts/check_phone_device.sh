#!/usr/bin/env bash
# `make phone` installs on the one iPhone devicectl can reach, or on DEVICE,
# and refuses with a sentence when there is none or more than one. The
# picking is scripts/phone_device.sh; this runs it against listings saved
# from `xcrun devicectl list devices --json-output`, in scripts/devicectl,
# so it is checked with no phone attached and on Linux. The install is never
# run here: that is a phone's business.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pick="$ROOT/scripts/phone_device.sh"
samples="$ROOT/scripts/devicectl"
status=0
fail() { echo "phone: $*" >&2; status=1; }

# A listing that should name one device, with DEVICE as given.
picks() {
    local sample="$1" device="$2" want="$3" got
    if ! got=$(DEVICE="$device" "$pick" "$samples/$sample" 2> /dev/null); then
        fail "$sample with DEVICE='$device' refused; it should pick $want"
    elif [ "$got" != "$want" ]; then
        fail "$sample with DEVICE='$device' picked '$got'; it should pick $want"
    fi
}

# A listing that should be refused, with words the refusal must say.
refuses() {
    local sample="$1" words="$2" got said
    if got=$(DEVICE= "$pick" "$samples/$sample" 2> /dev/null); then
        fail "$sample picked '$got'; it should refuse"
        return
    fi
    said=$(DEVICE= "$pick" "$samples/$sample" 2>&1 > /dev/null || true)
    case "$said" in
        *"$words"*) ;;
        *) fail "$sample refused saying '$said'; it should say '$words'" ;;
    esac
}

# An iPad and a phone devicectl calls unavailable are passed over.
picks one-iphone.json '' 6A1B2C3D-0000-4000-8000-000000000001
refuses no-iphone.json 'no iPhone is connected'
# Wired and on the network count alike, and both are named.
refuses two-iphones.json 'more than one iPhone is connected (Sample iPhone, Second iPhone)'
# DEVICE is taken as it is, even where the listing alone would refuse.
picks two-iphones.json 'Second iPhone' 'Second iPhone'
picks no-iphone.json 00008150-0000000000000001 00008150-0000000000000001

[ $status -eq 0 ] && echo "phone: ok"
exit $status
