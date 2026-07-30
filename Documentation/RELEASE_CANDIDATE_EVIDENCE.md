# Release Candidate Evidence

Last reviewed: July 30, 2026

## Candidate

- Product: The Climb
- Version: `1.0`
- Build: `16`
- Branch: `main`
- Platform: iPhone, iOS 17.0 or later
- Local archive: `/tmp/TheClimb-RC-1.0.16-20260730-165433.xcarchive`

The local archive path is temporary evidence on the release Mac. It is not a version-controlled release artifact.

## Automated Verification

| Check | Result |
| --- | --- |
| Native unit tests | 33 of 33 passed |
| Xcode Release analyzer | Passed with no analyzer findings |
| Firebase Functions TypeScript build | Passed |
| Daily-plan validation fixtures | Passed |
| Repository security validation | Passed |
| Git whitespace validation | Passed |
| Static accessibility audit | Missing Profile action labels repaired |
| Firebase project | `the-climb0` reported ACTIVE |
| Deployed Firebase functions | 16 functions reported ACTIVE |

The npm security audit still reports seven moderate advisories in transitive Firebase/Google dependencies. The available forced remediation would introduce breaking dependency changes, so it was not applied to this release candidate.

## Archive Verification

- Archive completed with `** ARCHIVE SUCCEEDED **`.
- The archived app passes `codesign --verify --deep --strict`.
- The archive is signed with the local Apple Development identity.
- App version/build in archive metadata is `1.0 (16)`.
- A dSYM with an arm64 UUID is present for the app and each extension.
- First-party and third-party privacy manifests are present.
- The archive contains:
  - Widget and Live Activity extension
  - Shield Configuration extension
  - Shield Action extension
  - Device Activity Monitor extension
  - Device Activity Report extension
  - Safari Content Blocker extension
- The archive does not contain a watchOS app or Network Extension.

The remaining archive warnings are App Intents metadata-extraction skips on extensions that do not link App Intents. There is no ExtensionKit embedding warning.

## Distribution Export Result

App Store Connect export was attempted and correctly stopped at external signing setup:

- Xcode reports no signed-in Apple account for distribution.
- No iOS Distribution certificate is installed.
- Distribution profiles are missing for:
  - `com.jaydenlacy.theclimb.contentblocker`
  - `com.jaydenlacy.theclimb.deviceactivityreport`

Do not upload build `15`; it predates this release candidate. After the Apple account, certificate, capabilities, and profiles are available, archive build `16` again using App Store distribution signing before upload.

## Backend Scope

No Firebase Functions or Firestore Rules source changed as part of this release candidate. A deployment was therefore not performed. The deployed project and callable-function inventory were checked instead.

## Required Human Evidence

The following cannot be completed without the release owner's Apple account, App Store Connect access, or a physical iPhone:

1. Confirm all distribution App IDs, Family Controls approvals, App Group membership, and provisioning profiles.
2. Export or validate an App Store distribution archive.
3. Run the complete physical-device matrix, including Screen Time authorization, app shielding, Device Activity delivery, Safari extension enablement, restart recovery, notifications, widgets, authentication, App Check, account deletion, and accessibility.
4. Upload build `16` to TestFlight and complete a production smoke test.
5. Complete App Store Connect privacy, age rating, export compliance, screenshots, support URL, review contact, and review notes.
