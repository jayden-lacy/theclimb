# Screen Time Migration Roadmap

Last reviewed: September 4, 2026

This roadmap reflects the `1.0 (17)` Screen Time release candidate. It does not treat source code, simulator behavior, unit tests, or a development-signed archive as proof that Apple framework enforcement works on a physical device.

## Status Legend

- `[x]` Implemented and verified locally by source inspection, compilation, or unit tests.
- `[~]` Implemented in source but incomplete or still requires physical-device, signing, entitlement, backend, or product verification.
- `[ ]` Not implemented or not yet verified.
- `[-]` Intentionally unavailable in the current production feature set.

## Current Verification Snapshot

| Evidence | Result |
| --- | --- |
| Repository | `/Users/jaydenlacy/Documents/The Climb` |
| Branch and release source | `main`; build `17` release source is committed and pushed |
| Debug and Release simulator compile | Current integrated Xcode scheme passed September 3, 2026 |
| Native unit tests | 50 of 50 passed September 3, 2026 |
| Release analysis | Passed September 3, 2026 with no analyzer findings |
| Current Release archive | `1.0 (17)` development-signed archive succeeded September 3, 2026; repeatable archive validation, matching first-party dSYMs, deep code-sign verification, and all six extensions are confirmed |
| Current worktree TestFlight upload | Not performed |
| Family Controls on physical iPhone | Not verified |
| Safari extension on physical iPhone | Not verified |
| Developer portal entitlements and distribution profiles | App Store export is blocked until Xcode has an Apple account, an iOS Distribution certificate, and profiles for the Safari content blocker and Device Activity report |
| Backend state | Firestore rules, indexes, and all 17 callable functions were deployed September 4, 2026; unauthenticated callable smoke checks correctly returned `401` |

The previously uploaded `1.0 (15)` build predates this Screen Time upgrade. It is not evidence for the new sessions, rhythms, boundaries, permanent protection, or Safari extension.

## Running Checklist

### Phase 0 - Audit

- [x] Architecture and target inventory
- [x] Feature preservation map
- [x] Capability parity matrix
- [x] Screen Time architecture
- [x] Adult-protection architecture
- [x] Data migration plan
- [x] Known iOS limitations
- [x] Initial risk register

### Phase 1 - Shared Infrastructure

- [x] Versioned Screen Time domain models
- [x] Production feature flags
- [x] App Group policy store
- [x] Idempotent policy migration runner
- [x] Policy resolver with overlap precedence
- [x] Authorization provider protocol and Apple adapter
- [x] Protection health model
- [x] Launch and foreground reconciliation
- [x] Existing mission-path integration
- [x] Unit coverage for precedence, migration, corruption recovery, and health truthfulness
- [~] Extension heartbeat and stale-state behavior; source exists, physical lifecycle behavior is unverified

### Phase 2 - Core Focus

- [x] General-purpose focus-session domain model
- [x] Purpose, duration, custom-purpose, and end-time controls
- [x] Protected-time history and aggregate attention reports based on The Climb records
- [x] Focus Rhythm model and cross-midnight evaluator
- [x] Cross-midnight unit test
- [~] Immediate Focus runtime and active-session UI; enforcement requires physical-device verification
- [~] Essential Apps selection and allow-list enforcement; requires physical-device safety and emergency-access review
- [~] Focus Rhythm scheduling and extension reapplication; source exists, operating-system delivery is unverified
- [~] Mission, prayer, devotional, and habit protected-launch integration; source exists, Apple enforcement is unverified
- [x] Rhythm Pause with explicit rest, schedule-change, travel, or vacation reason and automatic resume
- [~] Time-zone and daylight-saving rescheduling evidence; date-boundary and cross-midnight unit coverage passes, but operating-system schedule delivery still requires physical-device verification

### Phase 3 - Boundaries

- [x] App Boundary domain model, daily and weekly cadence, reset time, and warning-threshold model
- [x] Boundary evaluation and Device Activity event construction
- [~] App/category time-boundary setup and scheduling; source exists, threshold delivery is unverified
- [~] Weekday-specific limits; supported through active-day selection, but a dedicated weekday/weekend editing flow is not present
- [~] Warning notifications; extension callbacks exist, but physical delivery is unverified
- [x] Intentional-break domain behavior and permanent-protection precedence tests
- [~] Intentional-break enforcement and automatic reapplication; physical behavior is unverified
- [x] Flexible, intentional, and locked early-exit rules with unit coverage
- [-] Exact app-open boundaries; the production feature flag is off because public APIs do not provide reliable universal app-open counts
- [~] Device Activity Report extension, app embedding, private aggregate storage, and app-side range controls compile; authorized device data remains unverified

### Phase 4 - Permanent Protection

- [x] Permanent-protection domain model and separate policy source
- [x] Standard and Strict configuration modes
- [x] Strict-mode 24-hour disable-delay model and unit tests
- [x] Domain normalization, block/allow precedence, local rule storage, and signed-envelope validation model
- [x] Protection-health model that distinguishes Screen Time, Safari, and unavailable network layers
- [~] Continuous Managed Settings policy application; source exists, restart and revocation behavior is unverified
- [~] Explicit disable flow with reason selection and strict typed confirmation; physical enforcement still requires review
- [~] Local user-added domain block flow; Safari and Managed Settings enforcement are unverified
- [x] User-facing false-positive review flow with normalized domains and time-limited local exceptions
- [ ] Production signature verifier, trusted public-key configuration, and remote signed-rule delivery channel
- [~] Safari content-blocker target, structured block/allow rules, status, and reload handling; source compiles, but the extension has not been enabled and tested on a physical device
- [-] Accountability Lock; the production feature flag is off and no production backend approval or secure credential flow is connected
- [-] Guardian Mode; the production feature flag is off pending supported Apple authorization plus legal and product review
- [-] Network-level filtering; there is no Network Extension target or entitlement

### Phase 5 - Faith and Community Integration

- [x] Stewardship Score engine kept separate from OVR and labeled as behavioral evidence rather than spiritual worth
- [x] Stewardship Score presentation based on recorded focus, mission, and reflection evidence
- [x] Protected-time recording for general sessions and protected mission outcomes
- [~] Protected mission, prayer, devotional, and habit flows; source integration exists, but device enforcement is unverified
- [~] Weekly stewardship pulse, transparent factor breakdown, and on-device Screen Time report are integrated; the final combined narrative review remains incomplete
- [ ] Opt-in accountability summaries for protection or focus behavior
- [x] Evidence-constrained Attention Assist recommendation engine
- [~] Attention Assist settings, App Group preferences, quiet-hour validation, delivery history, launch reconciliation, and local-notification scheduling; integrated for upcoming rhythms and protection-health evidence, but not covered by dedicated runtime tests or physical notification evidence
- [ ] Device-usage Attention Assist signals; the report is integrated, but its aggregates are not yet used to schedule recommendations

### Phase 6 - Product Design

- [x] Focus-first information architecture and control center
- [x] Permission and protection-health states
- [x] Focus setup and active-session states
- [x] Existing-user, resumable Screen Time upgrade flow
- [~] Permanent Protection setup, Safari instructions, and disable states; present but not physically verified
- [x] Protected-time reporting based only on The Climb session records
- [~] Device Activity Report extension and visible Today/7D/4W/3M app report compile; physical data access and presentation remain unverified
- [~] Static accessibility audit completed and missing action labels repaired; full VoiceOver, Dynamic Type, Reduce Motion, high-contrast, and color-independent-status physical-device audit remains
- [ ] Localization audit

### Phase 7 - Hardening

- [x] Debug simulator compile for the currently integrated Xcode scheme
- [x] 50 native unit tests passing
- [x] Migration idempotency and corrupt-envelope recovery fixtures
- [x] Policy overlap, strict-delay, intentional-exit, and capability-truth unit coverage
- [x] Optimized Release analysis and development-signed `1.0 (17)` archive for the current worktree
- [ ] Physical-device Screen Time matrix
- [ ] Extension termination, app termination, and device-restart recovery
- [~] Date-boundary and cross-midnight tests pass; physical time-zone and daylight-saving rescheduling remains unverified
- [ ] Family Controls revocation and reauthorization tests
- [ ] Safari enable, disable, reload, and false-positive tests
- [~] Static security threat model documented; physical-device, moderation-operations, billing-alert, and App Store disclosure evidence remains
- [~] Sensitive logging and local-storage audit; secret and tracked-backup scans pass, adult-protection and Safari domain-rule records migrate to protected App Group files, and archive privacy manifests are verified, but final third-party SDK disclosure review remains
- [~] Static accessibility audit completed; physical assistive-technology matrix remains
- [~] Release analyzer passed; extension-memory, background-work, launch-time, and battery evidence still requires physical-device profiling

### Phase 8 - Release Preparation

- [x] App Store entitlement checklist
- [x] App Review notes draft
- [x] Privacy disclosure implementation map
- [x] Age-rating review
- [x] Support and troubleshooting guide
- [x] Rollback plan
- [x] Physical-device test matrix document
- [x] Known iOS limitations document
- [-] Subscription checklist; The Climb is free and the repository contains no StoreKit product, paywall, in-app purchase, or subscription
- [~] Apple Developer portal entitlement and distribution-profile evidence; development signing resolves, but App Store distribution export does not
- [ ] App Store Connect privacy, age-rating, encryption, support, and review metadata confirmation
- [x] Current worktree included in the build `17` release-candidate commits
- [x] Development-signed Release archive containing all intended extensions
- [x] Repeatable archive validator covers version, bundle inventory, entitlements, privacy manifests, code signing, and first-party dSYM UUIDs
- [ ] New TestFlight upload for the current release candidate
- [ ] New TestFlight physical-device evidence

## Release Gate

The automated release candidate is complete, but the build is not ready to submit for review. Release remains blocked until:

1. Xcode is signed into the release owner's Apple Developer account and an iOS Distribution certificate is installed.
2. Family Controls distribution entitlements and provisioning profiles are confirmed for every participating bundle ID, including the Device Activity report and Safari content blocker.
3. The physical-device matrix passes for authorization, shielding, schedules, boundaries, breaks, restart recovery, Safari, notifications, widgets, authentication, App Check, and account deletion.
4. App Store Connect disclosures and review notes match the exact archived binary.
5. A new TestFlight build containing this worktree passes smoke testing.

## Sequencing Rules

1. Do not promote Apple enforcement capabilities from `[~]` to `[x]` without physical-device evidence.
2. Keep usage charts and averages grounded only in the authorized Device Activity Report extension; never synthesize missing device data.
3. Do not describe filtering as device-wide; Safari protection applies only to Safari and no Network Extension exists.
4. Do not enable Accountability Lock or Guardian Mode until secure authorization, backend enforcement, abuse controls, and legal review are complete.
5. Keep existing faith, mission, community, authentication, account deletion, widget, and AI behavior operational throughout the migration.
6. Preserve legacy App Group keys and existing Firebase schemas until at least one production upgrade cycle is complete.
