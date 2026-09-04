# Release Candidate Evidence

Last reviewed: September 4, 2026

## Candidate

- Product: The Climb
- Version: `1.0`
- Build: `17`
- Branch: `main`
- Frozen release source: `9ff8ef4`
- Platform: iPhone, iOS 17.0 or later
- Local archive: `/tmp/TheClimb-RC-1.0.17-20260903-220857.xcarchive`

The archive path is temporary evidence on the release Mac. It is not a version-controlled release artifact.

## Automated Verification

| Check | Result |
| --- | --- |
| Native unit tests | 50 of 50 passed |
| Debug simulator build | Passed |
| Release simulator build | Passed |
| Xcode Release analyzer | Passed with no analyzer findings |
| Firebase Functions TypeScript build | Passed |
| Daily-plan validation fixtures | Passed |
| Repository security validation | Passed |
| Git whitespace validation | Passed |
| Website validation | Passed |
| Live legal/support/AASA endpoints | `/`, `/privacy`, `/terms`, `/download`, and AASA returned HTTP 200 |
| Firebase deployment | Rules, indexes, and all 16 Gen 2 functions deployed to `the-climb0` |
| Deployed AI source comparison | `generateDailyPlan` deployed source matched local release source |
| Unauthenticated backend smoke tests | AI, community post, mission completion, and account deletion rejected with HTTP 401 |

A fresh live npm audit reports seven moderate transitive advisories and no high or critical advisories. The high-severity `brace-expansion` advisory was removed by updating to the patched release. The remaining findings are in Firebase/Google Cloud's dependency chain; npm's proposed forced remediation is a breaking Firebase downgrade and was not applied.

## Archive Verification

- Archive completed with `** ARCHIVE SUCCEEDED **`.
- The archived app passes `codesign --verify --deep --strict`.
- The archive is signed with the local Apple Development identity.
- App version/build in archive metadata is `1.0 (17)`.
- The main app and every extension have an arm64 dSYM.
- First-party and relevant third-party privacy manifests are present.
- The archive contains:
  - Widget and Live Activity extension
  - Shield Configuration extension
  - Shield Action extension
  - Device Activity Monitor extension
  - Device Activity Report extension
  - Safari Content Blocker extension
- The archive contains no watchOS app or Network Extension.

## App Store Screenshot Evidence

The current screenshot set was regenerated from the build 17 debug-only fixture and visually inspected:

- `App Store Previews - 1284x2778/01-protected-focus.png`
- `App Store Previews - 1284x2778/02-daily-growth.png`
- `App Store Previews - 1284x2778/03-progress-badges.png`

Each image is exactly 1284 x 2778 pixels. The fixture is compiled only in Debug and does not create Firebase data or alter Release behavior.

## Distribution Export Result

App Store export was attempted and stopped at Apple distribution signing:

- Xcode has no signed-in Apple account available to the command-line export.
- No Apple Distribution certificate is installed.
- Distribution profiles are missing for:
  - `com.jaydenlacy.theclimb.contentblocker`
  - `com.jaydenlacy.theclimb.deviceactivityreport`

The development archive is valid evidence but cannot be uploaded to TestFlight. Sign in to the release Apple account in Xcode, create or download an Apple Distribution certificate, and resolve profiles for all seven bundle identifiers before creating the upload archive.

## Backend Deployment

The current Firestore rules, indexes, and Cloud Functions were deployed to project `the-climb0`. The deployment includes authenticated AI generation, App Check enforcement, server-owned scoring, account deletion cleanup, and backend-enforced community/group mutations.

## Required Human Evidence

The following still require the release owner's Apple account, App Store Connect access, or a physical iPhone:

1. Confirm all App IDs, Family Controls distribution approvals, App Group membership, and distribution profiles.
2. Export and validate an Apple Distribution archive.
3. Run the complete physical-device matrix, including Screen Time authorization, app shielding, Device Activity delivery, Safari extension enablement, restart recovery, notifications, widgets, authentication, App Check, account deletion, and accessibility.
4. Upload build `17` to TestFlight and complete a production smoke test.
5. Complete App Store Connect privacy, age rating, export compliance, screenshots, support URL, review contact, and review notes.
