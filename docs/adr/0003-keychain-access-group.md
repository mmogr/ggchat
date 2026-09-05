# ADR 0003 — One Keychain access group for the iOS and macOS builds

- **Status:** Proposed (blocked on a signing team)
- **Date:** 2026-09-06
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

Local builds are unsigned today (`CODE_SIGNING_ALLOWED=NO` in CI), so the
group cannot be declared yet.

## Decision

When a signing team is set in `App/project.yml`, both platforms declare the
access group `$(TeamIdentifierPrefix)com.mattogrady.ggchat` and
`KeychainSecrets` is constructed with that group. Until then
`KeychainSecrets.accessGroup` is nil and items are per-build. Items use
`kSecAttrAccessibleAfterFirstUnlock` so a reconnect in the background can
read a token.

## Kill criteria

- **Reading:** a hand test, recorded in this ADR when run: add a provider
  on the Mac, open the app on the phone, note whether the provider's key
  is present. Date and outcome go in the table below.
- If sharing works but a user reports a credential appearing on a device
  they did not expect, drop the group and keep items per-build.

| date | Mac build | iPhone build | key present on phone |
|---|---|---|---|
| — | — | — | not yet run |
