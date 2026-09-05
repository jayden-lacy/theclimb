# Release Candidate Evidence

Last reviewed: September 5, 2026

## Candidate

- Product: The Climb
- Version: `1.0`
- Build: `19`
- Branch: `main`
- Binary source commit: `e4d6ba2`
- Platform: iPhone, iOS 17.0 or later
- Local archive: `~/Library/Developer/Xcode/Archives/2026-09-04/The Climb Stable 1.0 (19).xcarchive`

The archive path is temporary evidence on the release Mac. It is not a version-controlled release artifact.

## Automated Verification

| Check | Result |
| --- | --- |
| Native unit tests | 50 of 50 passed |
| Debug simulator build | Passed |
| Release simulator build | Passed |
| Xcode Release analyzer | Passed with no analyzer findings |
| Firebase Functions TypeScript build | Passed |
| Auth/Firestore security emulator suite | 64 of 64 passed September 5 on Node 22; see `Documentation/BACKEND_SECURITY_TESTS.md` |
| Independent backend CI | [GitHub run 33981083443](https://github.com/jayden-lacy/theclimb/actions/runs/33981083443) passed for backend commit `35f5e04` on September 5 |
| Daily-plan validation fixtures | Passed |
| Repository security validation | Passed |
| Git whitespace validation | Passed |
| Website validation | Passed |
| Repeatable archive validation | Passed for version, bundle inventory, entitlements, signing, privacy manifests, and first-party dSYMs |
| App Store toolchain | Xcode `26.6 (17F113)`, iOS SDK `26.5 (23F81a)` |
| Live legal/support/AASA endpoints | `/`, `/privacy`, `/terms`, `/download`, and AASA returned HTTP 200 |
| Firebase deployment | Rules, indexes, and all 17 Gen 2 functions deployed to `the-climb0` |
| Deployed AI source comparison | `generateDailyPlan` deployed source matched local release source |
| Unauthenticated backend smoke tests | AI, community post/reaction/report, mission completion, and account deletion rejected with HTTP 401 |

A fresh live npm audit reports seven moderate transitive advisories and no high or critical advisories. The high-severity `brace-expansion` advisory was removed by updating to the patched release. The remaining findings are in Firebase/Google Cloud's dependency chain; npm's proposed forced remediation is a breaking Firebase downgrade and was not applied.

## Archive Verification

- Archive completed with `** ARCHIVE SUCCEEDED **`.
- The archived app passes `codesign --verify --deep --strict`.
- The archive is signed with the local Apple Development identity.
- App version/build in archive metadata is `1.0 (19)`.
- The main app and every extension have an arm64 dSYM.
- First-party and relevant third-party privacy manifests are present.
- `npm run validate:archive -- <archive> 1.0 19 development 17F113 iphoneos26` passes against the archived product.
- The archive contains:
  - Widget and Live Activity extension
  - Shield Configuration extension
  - Shield Action extension
  - Device Activity Monitor extension
  - Device Activity Report extension
  - Safari Content Blocker extension
- The archive contains no watchOS app or Network Extension.

The archive does not include dSYMs for the precompiled `FirebaseFirestoreInternal`, `absl`, `grpc`, `grpcpp`, and `openssl_grpc` frameworks. First-party dSYMs match their binaries. These missing third-party symbols may still produce upload warnings and should be rechecked on the final distribution archive.

## App Store Screenshot Evidence

The current screenshot set was regenerated from the build 17 debug-only fixture and visually inspected. Build 19 changes only the bundle build number and legal attribution copy, so the screens remain representative:

- `App Store Previews - 1284x2778/01-protected-focus.png`
- `App Store Previews - 1284x2778/02-daily-growth.png`
- `App Store Previews - 1284x2778/03-progress-badges.png`

Each image is exactly 1284 x 2778 pixels. The fixture is compiled only in Debug and does not create Firebase data or alter Release behavior.

## App Store Upload Result

Build 17 was uploaded from Xcode 27 beta and must not be selected for review. Build 19 supersedes build 18 and was rebuilt from binary source commit `e4d6ba2` using release Xcode `26.6 (17F113)` and the iOS `26.5` SDK.

- App Store upload completed successfully September 4, 2026 at 12:26 PM Central.
- Current processing/compliance status was not reverified September 5 because App Store Connect requires sign-in again.
- All seven App Store profiles are present, use team `BLH227B4U7`, contain the shared App Group, and disallow debugging.
- Family Controls is present in the App Store profiles for the app, shield configuration, shield action, Device Activity monitor, and Device Activity report.
- Upload emitted symbol warnings only for the precompiled Firebase/gRPC frameworks listed above; the export itself succeeded.

Do not select build 17 or superseded build 18 for review. After build 19 finishes processing, answer export compliance, enable it for internal TestFlight testing, and then perform the physical-device smoke test.

## Backend Deployment

The current Firestore rules, indexes, and Cloud Functions were deployed to project `the-climb0`. The deployment includes authenticated AI generation, App Check enforcement, server-owned scoring, account deletion cleanup, backend-enforced community/group mutations, server-verified reports, one Amen per user and post, and per-user mutation limits. TTL cleanup is active for `aiUsage`, `aiDailyPlans`, and `actionRateLimits` expiration fields.

September 5: redeployed the security fixes to Firestore rules and all 17 functions successfully. Indexes were unchanged from the September 4 deployment. Production POST smoke checks for `generateDailyPlan`, `completeMission`, `failMission`, `completeRecoveryMission`, `syncLeaderboard`, `createCommunityPost`, `reportCommunityPost`, and `deleteAccountData` all rejected missing authentication with HTTP 401. These checks did not mutate production user data or call OpenAI. Build 19's iOS binary was not changed by this backend release.

Spending-alert setup is tracked separately in `Documentation/SPENDING_ALERTS.md`; a provider-specific alert is not evidence of combined Firebase/OpenAI monitoring.

## Required Human Evidence

The following still require the release owner's Apple account, App Store Connect access, or a physical iPhone:

1. Refresh build `19` processing/compliance status, answer any outstanding export compliance, and enable it for internal TestFlight testing.
2. Run the complete physical-device matrix, including Screen Time authorization, app shielding, Device Activity delivery, Safari extension enablement, restart recovery, notifications, widgets, authentication, App Check, account deletion, and accessibility.
3. Complete App Store Connect privacy, age rating, export compliance, screenshots, support URL, review contact, and review notes.
4. Select only build `19` for review and retain the TestFlight smoke-test evidence.

## Remaining Technical Gate

Server-owned score writes are implemented, but mission eligibility still comes from client-synchronized mission records. Add server-issued eligibility and per-day reward limits before treating leaderboard integrity as complete. The 64-test suite validates the documented authorization boundaries, not proof that a real-world activity occurred.
