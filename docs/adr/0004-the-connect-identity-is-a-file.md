# ADR 0004 — This device's endpoint key is a file, one per machine

- **Status:** Accepted
- **Date:** 2026-09-17
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

modelpipe's connecting side has an endpoint key: the name it answers to on
the network. Until now this app has never given it one, so `mpConnect` and
`mpPair` mint a key per process. Every launch of this app is therefore a new
device to the machine it dials.

That matters because of what the other end does with it. gglib mints one
credential per device at pairing and, since #1041 (on `main`, after v0.18.0),
records beside it the fingerprint of the endpoint that **redeemed the code**:
`gglib remote list` prints it as "paired from …" beside the row's last-seen
line. It says where a device paired from, not where it has been used since —
and with a key minted per process those are different endpoints from the
second launch onward, so the fingerprint names a peer that no longer exists
and cannot be compared with anything. A device keeping its key makes the two
the same endpoint, which is what the column is worth reading for.

Older gglib is not worse off: v0.18.0 has no such column, and nothing here
depends on the far side having one. The other thing a lasting identity is a
prerequisite for is modelpipe's `add_token_pinned`, whose own doc says a
device needs `ConnectOptions::identity` or every restart is an endpoint the
pin refuses. gglib does not pin today (it calls the unpinned `add_token`), and
the arc plan's Q4 says it should not; this is what would let that be
reconsidered.

The binding gives exactly one way to do it. `MpConnectOptions.identityPath`
names a file; modelpipe mints the key into it on first use, reads it back
afterwards, creates it `0600`, and refuses one that somebody else on the
machine can read. There is no way to hand it bytes instead — the whole of the
file handling, including the refusals, is inside the crate.

ADR 0003 is the reason that needs an entry of its own: this app keeps every
credential in the Keychain, `scripts/check_boundaries.sh` enforces that only
`Secrets.swift` may reach it, and 0003 was *rejected* rather than simply
shelved, on the reasoning that a device's credentials should stay on that
device. A secret arriving on disk deserves the same scrutiny.

## Decision

**Keep the endpoint key in a file, one per far machine, under Application
Support, excluded from the backup.**

Three things follow, and each is the part worth arguing.

**A file, not the Keychain.** The binding takes a path and writes the file
itself, so the alternative is to hold key bytes in the Keychain and
materialise them to a temporary file for each dial — which puts the same
secret on the same disk, adds a second copy, and adds a window in which the
file is present and nobody is responsible for removing it. It also invents a
format: this app would have to write a file modelpipe is willing to read,
which is precisely the duplication the pairing work has spent this release
deleting. The file stays, and `Secrets.swift` keeps its monopoly on the
Keychain because this is not a credential.

**It is not a credential, and the distinction is the point.** The endpoint
key admits nothing. What admits this device at the far edge is the bearer
token minted at pairing, which lives in the Keychain like every other secret
here; what the endpoint key does is let the far machine *recognise* this
device. Stealing it buys the ability to claim this device's name on the
network, not the ability to use its key — and anyone who can read it can read
the Keychain-held token too, because both are inside the app's container.
`gglib remote forget` remains the revocation, and it revokes the token.

**One file per far machine, not one for the app.** A key is an endpoint, and
an endpoint may hold one live connection: iroh's relay deactivates the older
connection when a second one registers the same endpoint id. This app holds a
session per pipe provider and dials them all when it comes back to the
foreground, so a single key would mean the second desktop quietly took the
relay path away from the first. Per machine also means a phone paired with
two desktops presents each a different fingerprint, and neither can tell it
is the same phone — a property worth having rather than an accident.

The file is named by `Ticket.digest`, the same non-secret fingerprint a
provider already stores. That is the digest of the whole ticket rather than
of the endpoint inside it, because reading an endpoint id out of a ticket is
modelpipe's parse, and this app deleted its copy of that parse on purpose in
the release before this one. The consequence: one machine re-added from a
ticket written another way is met as a new device. Nothing breaks — the far
side records fingerprints and does not pin them — and re-adding a machine
means re-pairing anyway.

**Out of the backup.** A restored phone is a different device and has to look
like one; two phones answering to one endpoint id is the one thing a key may
not allow. The Keychain items go the other way on purpose, so a restored
phone still holds the tokens that admit it and simply introduces itself
afresh.

## Consequences

- The fingerprint gglib records for a phone stops changing on every launch, so
  where a device paired from is where it is still dialling from, and two rows
  can be told apart by eye. Revocation is unaffected either way: `gglib remote
  forget <device>` is aimed by the device id it minted, which was always
  stable.
- There is a secret on this device's disk that was not there before, and the
  README says so. It is unreadable to other users, absent from backups, and
  useless without the token beside it in the Keychain.
- A key file this device cannot use is thrown away and the dial tried once
  more, because modelpipe's advice for that case — remove the file or choose
  another path — is not something a phone offers anybody. The cost is a
  changed fingerprint, which is what a relaunch used to cost every time.
- A **pairing** cannot do that: `MpPairError` folds every transport failure
  into one case carrying a sentence, so telling an unusable key from a
  machine that is switched off would mean matching on modelpipe's wording.
  A key half written is still healed, because both paths ask for the path the
  same way; anything else is healed by the next dial to that machine. If the
  ffi ever carries the identity arm through `MpPairError`, pairing can heal
  too.
- Two providers naming the **same** machine now share one key, where before
  each dial minted its own. That is the honest reading of "one device" — it
  is one phone holding two of that machine's keys, and the endpoint it
  reports against both roster rows is the same because it is the same
  device. Two costs, both recorded rather than designed around, because
  adding one machine twice is unusual:
  - **The relay.** While both pipes are up the relay keeps one connection per
    endpoint id and deactivates the older, promoting it back when the newer
    leaves. A direct path is untouched; whether the older connection is still
    there to promote after a spell on a relay-only path is iroh's business
    and is not measured here.
  - **The file.** A dial that throws an unusable key away removes a file the
    other provider may be dialling through. The resume pass dials
    sequentially, so the two do not overlap in the ordinary case, and the
    worst outcome is that the second dial mints a fresh key.

  Keying on the provider instead would avoid both by putting a provider id
  through `PipeConnector`, which is a seam this change does not otherwise
  touch.
- Removing a provider leaves its key file. It admits nothing, the token that
  does is deleted with the provider, and deleting the app deletes both.
- The mock connector in DEBUG builds keeps no key: it stands in for the far
  machine, and there is no endpoint on either side of it.
