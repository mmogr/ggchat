# ADR 0003 — One Keychain access group for the iOS and macOS builds

- **Status:** Proposed (blocked on a signing team — and, per the 2026-09-07
  note under "Decision", on two other things this ADR did not know about)
- **Date:** 2026-09-06 (amended 2026-09-07 — the stated blocker is not the
  only blocker, the premise about CI is false, and the entitlement it
  proposes is already half-declared under a different name)
- **Supersedes:** nothing
- **Superseded by:** nothing

## Context

Credentials (API key, ticket, token) live in the Keychain under the
provider's id; `ProviderConfig` holds nothing secret. The same person will
run the app on a Mac and a phone. With iCloud Keychain, an item created in a
shared access group by one build is visible to the other, so a provider
added on the Mac could appear on the phone without retyping a token. That
needs both builds to declare the same `keychain-access-groups` entitlement,
which needs a team identifier prefix, which needs the project to be signed.

~~Local builds are unsigned today (`CODE_SIGNING_ALLOWED=NO` in CI), so the
group cannot be declared yet.~~

> **Amended 2026-09-07 — both halves of that sentence are false.**
>
> Nothing here passes `CODE_SIGNING_ALLOWED=NO`. Every place that builds the
> app passes `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
> CODE_SIGNING_ALLOWED=YES` — the `Makefile`'s `UITEST`,
> `scripts/screenshots.sh`, and `.github/workflows/ci.yml`. That is *ad-hoc*
> signing, chosen deliberately and for this ADR's own subject: the workflow's
> comment says "Ad-hoc signing, not none: an unsigned iOS app has no Keychain
> access, and the app keeps every credential there", and
> `KeychainError.reason` renders `errSecMissingEntitlement` as "this build is
> not signed, so it has no Keychain access". The repo had already worked this
> out; the ADR describes the setting it was changed away from.
>
> And the group is not undeclarable — it is already declared, on one platform.
> `App/ggchat/ggchat-iOS.entitlements` carries
> `keychain-access-groups` = `$(AppIdentifierPrefix)com.mattogrady.ggchat`,
> wired in by `App/project.yml` for both `iphoneos` and `iphonesimulator`.
> `App/ggchat/ggchat-macOS.entitlements` declares app-sandbox and
> network-client and no keychain group at all. So the asymmetry this ADR
> proposes to remove already exists in the entitlements as an asymmetry
> between the two files, which is a smaller and more concrete piece of work
> than "when a signing team is set".

## Decision

When a signing team is set in `App/project.yml`, both platforms declare the
access group ~~`$(TeamIdentifierPrefix)com.mattogrady.ggchat`~~ and
`KeychainSecrets` is constructed with that group. Until then
`KeychainSecrets.accessGroup` is nil and items are per-build. Items use
`kSecAttrAccessibleAfterFirstUnlock` so a reconnect in the background can
read a token.

> **Amended 2026-09-07 — this decision, implemented literally, would share
> nothing.** Two things are wrong with it; the third note below is the part
> that stands.
>
> **It names the wrong variable.** The shipped entitlement uses
> `$(AppIdentifierPrefix)`, not `$(TeamIdentifierPrefix)`. Xcode expands the
> two from different sources, and an entitlement declaring one group while
> the code queries the other shares nothing. Whichever is right, the ADR and
> `ggchat-iOS.entitlements` have to agree, and today they do not.
>
> **An access group is not iCloud Keychain.** A shared group makes an item
> reachable to another *build on the same device*. Propagating it to a second
> device is `kSecAttrSynchronizable`, and `KeychainSecrets` never sets it:
> `setSecret` writes only `kSecValueData` and
> `kSecAttrAccessibleAfterFirstUnlock`, so every item is created
> non-synchronizable, and `baseQuery` omits the attribute too, so a read
> would not match a synchronizable item even if one existed. The Context's
> "with iCloud Keychain, an item created in a shared access group by one
> build is visible to the other" needs that attribute to be true of this app,
> and it is not. The accessibility class already chosen is not in the way —
> `kSecAttrAccessibleAfterFirstUnlock` is not a `…ThisDeviceOnly` class — so
> what is missing is the attribute itself, on both the write and the query.
>
> **Signing is still needed**, and that part stands: a real (not ad-hoc)
> signature is what makes an entitlement mean anything. It is one of three
> blockers rather than the blocker.

## Kill criteria

- **Reading:** a hand test, recorded in this ADR when run: add a provider
  on the Mac, open the app on the phone, note whether the provider's key
  is present. Date and outcome go in the table below.

  > **Amended 2026-09-07 — the right reading, and its answer is currently
  > fixed.** The hand test is the correct one to keep: it measures the thing
  > the decision is for, on the two devices that matter, and it cannot be
  > faked by a counter. But run against the code as it stands it can only
  > come back "not present", and would do so for a reason that has nothing
  > to do with the access group: no item is synchronizable, so nothing
  > reaches the second device to be found. Running it before
  > `kSecAttrSynchronizable` is set would produce a row in the table below
  > that reads like evidence against the decision and is evidence of
  > nothing.

- If sharing works but a user reports a credential appearing on a device
  they did not expect, drop the group and keep items per-build.

| date | Mac build | iPhone build | key present on phone |
|---|---|---|---|
| — | — | — | not yet run |
