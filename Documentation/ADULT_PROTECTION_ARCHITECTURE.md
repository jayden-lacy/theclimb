# Adult Protection Architecture

Product name: Permanent Protection

## Current Baseline

The current app can enable Apple's automatic adult web-content filter while a protected mission is active. It can also shield user-selected web-domain tokens. It does not currently provide permanent filtering, Safari extension health, network filtering, signed rule updates, or accountability locking.

The UI must not describe the current baseline as device-wide or impossible to bypass.

## Protection Modes

### Standard

- Apple automatic adult web-content filter
- user-selected high-risk apps and browsers
- user-selected web domains
- user-confirmed disable flow

### Strict

- continuous permanent policy
- delayed disable request
- typed reason
- high-risk browser/app review
- optional accountability summary

### Accountability

- server-issued approval challenge
- salted PIN verifier or approval token in Keychain/server, never plaintext
- expiry, replay protection, attempt rate limit, and audit event
- summary notifications without full URLs or search terms

### Guardian

- gated behind supported Apple guardian/child authorization
- requires separate legal, age, and product review
- must not be represented as active on an individually managed account

## Layered Enforcement

1. Family Controls app/category/domain shielding
2. Managed Settings automatic adult web-content filtering
3. Future Safari declarative content blocker
4. Future Network Extension only after Apple entitlement approval
5. Guided SafeSearch and Restricted Mode setup
6. Whole-app blocking for encrypted feeds that cannot be filtered reliably

## Local Rule Engine

Rules must support:

- normalized ASCII and internationalized domains
- exact and subdomain matches
- allow exceptions
- bundled baseline list with compatible license
- signed remote updates
- version, issue date, expiry, and rollback
- offline last-known-good rules
- duplicate removal

Raw browsing history is not a product input.

## Health

`Fully Protected` requires every enabled layer to report healthy.

Examples:

- Family Controls revoked: `Action Required`
- Safari extension disabled while configured: `Partially Protected`
- signed rules expired: `Action Required`
- network entitlement unavailable but not enabled: does not reduce Standard health

## Break Invariant

Normal focus breaks and rhythm pauses cannot disable Permanent Protection.

Only the explicit Permanent Protection disable flow can remove its source policy.

## Sensitive Data Rules

Never persist or transmit:

- full browsing history
- explicit search terms
- complete blocked URLs in analytics or crash logs
- full URLs in partner notifications

Permitted aggregate examples:

- attempts blocked today
- protection inactive duration
- permission health changed

## Capability Flags

- `permanentProtection`
- `safariContentBlocker`
- `networkProtection`
- `accountabilityProtection`
- `guardianProtection`

Unavailable layers remain hidden or clearly labeled as unavailable. No placeholder button may imply enforcement.
