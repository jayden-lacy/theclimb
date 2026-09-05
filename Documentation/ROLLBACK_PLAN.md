# Rollback Plan

Last reviewed: September 4, 2026

This plan covers release rollback for the Screen Time upgrade while preserving existing faith, account, community, and user data. Apple App Store binaries cannot be remotely replaced, and the current Screen Time feature flags are compiled into the app rather than controlled by a verified remote kill switch.

## Current Baseline

- Release candidate: `1.0 (19)` on `main`
- Current Screen Time upgrade: included in binary source commit `e4d6ba2`
- Superseded uploads: builds `15`, `17`, and `18`
- Current signed archive: development-signed build `19` archive verified locally
- Current release candidate: build `19`, uploaded to App Store Connect; current processing/compliance state requires a signed-in refresh
- Current release binary source: commit `e4d6ba2`

Before public distribution, keep build `19` limited to internal TestFlight testing until the required physical-device matrix passes.

## Rollback Principles

1. Protect user data before feature availability.
2. Never weaken Firestore security rules to restore client compatibility.
3. Never delete App Group migration source keys during the first production upgrade cycle.
4. Do not claim a remote disable capability that does not exist.
5. Use a new incremented build number for every replacement binary.
6. Preserve account deletion, sign-in, legal, support, mission, devotional, journal, community, and progress paths.
7. Communicate actual protection state; do not leave users believing a disabled layer is active.

## Release Stages

### Before TestFlight

If a release gate fails:

1. Stop the release.
2. Keep the current production/TestFlight build unchanged.
3. Record the failed matrix IDs and evidence.
4. Fix forward on a dedicated branch.
5. Re-run simulator tests, signed archive validation, and the full affected physical-device matrix.

### During Internal or External TestFlight

If a serious defect appears:

1. Stop inviting testers to the affected build.
2. Notify active testers of the affected capability and recovery steps.
3. Expire or remove the affected build from testing when appropriate.
4. Submit a corrected build with an incremented build number.
5. Do not ask testers to rely on uninstall/reinstall if it could discard unsynced local data.

### During App Store Phased Release

If phased release is enabled:

1. Pause the phased release.
2. Assess whether the issue affects data integrity, account security, protection truthfulness, or only presentation.
3. Prepare a hotfix or replacement build.
4. Resume only after the affected physical-device matrix passes.

### After Full App Store Release

For a severe incident:

1. Publish an in-app or support notice that states the affected layer accurately.
2. Submit an expedited corrected build when justified.
3. Remove the app from sale only when continued distribution creates greater user harm than temporary unavailability.
4. Keep backend authentication, account deletion, and data export/deletion support operational.

Apple does not permit re-uploading the same build. A rollback binary must use a higher `CURRENT_PROJECT_VERSION`, even when its code is based on an earlier known-good commit.

## Incident Severity

| Severity | Example | Required action |
| --- | --- | --- |
| Critical | Cross-user data exposure, account deletion corruption, entitlement misuse, protection shown active when definitively inactive | Stop rollout immediately; security incident process; hotfix |
| High | Permanent Protection unexpectedly clears, locked session cannot recover after expiry, widespread sign-in failure | Pause rollout; notify testers/users; hotfix |
| Medium | One schedule edge case, Safari reload issue with clear status, stale widget | Limit rollout if needed; fix in next build |
| Low | Copy, spacing, nonblocking animation, isolated cosmetic issue | Track and fix normally |

## Component Rollback

### Screen Time Sessions, Rhythms, and Boundaries

There is no verified remote flag service for these local features. If local enforcement is unsafe:

- stop the release before submission; or
- ship a replacement binary with the affected compiled feature flag disabled and accurate UI removed.

Do not leave a visible control that does nothing.

### Permanent Protection

If protection state is inaccurate:

- prioritize truthful health state;
- preserve the user's ability to recover through Apple Settings;
- do not shorten an existing Strict delay through a silent data rewrite; and
- ship a corrected binary.

If false positives are severe, pause rollout rather than weakening all users' protection through an unreviewed rule change.

### Safari Content Blocker

If the extension crashes, rejects rules, or causes unacceptable false positives:

1. Stop rollout.
2. Remove or correct the extension in a replacement build.
3. Keep the main app copy accurate about Safari status.
4. Preserve local rules so a later fixed build can recover them.

Removing Safari Protection does not create network-level protection; never substitute that claim.

### Backend and Firebase

Backend rollback must:

- use a known-good tagged or committed function/rules version;
- preserve deny-by-default Firestore ownership;
- preserve current and previous compatible request schemas;
- avoid deleting cached daily plans or user data unless required by an incident; and
- be followed by authenticated and unauthenticated smoke tests.

Do not deploy a permissive rule set as a temporary workaround.

### AI Generation

If OpenAI generation fails:

- keep deterministic fallback plans active;
- retain authentication, App Check, rate limits, and cost controls;
- disable only optional regeneration behavior if necessary; and
- avoid placing API keys or prompts in the client.

### Community

If moderation or backend ownership fails:

- disable new community writes at the backend if a safe server-side switch exists;
- preserve read access only when it does not expose removed or blocked content;
- keep report, block, and account deletion support available; and
- never allow direct client writes to server-owned collections.

## Data Compatibility

The Screen Time upgrade uses separate, versioned App Group envelopes and retains legacy keys. Rollback validation must prove:

- existing `AppStateSnapshot` still decodes;
- profile, streak, mission, journal, habit, group, partner, and achievement data remain;
- previous app versions ignore unknown local Screen Time keys safely;
- migration can run more than once without duplication;
- corrupted new envelopes fall back without deleting legacy values; and
- cloud schemas remain backward compatible.

## Recovery Verification

Before releasing a rollback or hotfix:

- [ ] Clean install passes.
- [ ] Upgrade from the last public build passes.
- [ ] Existing account data remains.
- [ ] Screen Time authorization denial and revocation are truthful.
- [ ] Expired restrictions clear without removing unrelated policies.
- [ ] Account deletion works.
- [ ] Firebase rules and functions smoke tests pass.
- [ ] Widgets and Live Activities do not show stale protection.
- [ ] Privacy manifests and entitlements match the replacement binary.
- [ ] App Review notes describe the replacement binary, not the withdrawn build.

## Communication Template

> We identified an issue affecting `[CAPABILITY]` in version `[VERSION]` build `[BUILD]`. `[STATE WHAT IS AND IS NOT WORKING]`. Your account and faith activity data are `[IMPACT]`. Until the corrected update is available, use `[SAFE RECOVERY STEP]`. Contact support@theclimbapp.org with your app version and iOS version. Do not send passwords or browsing history.

## Post-Incident

Within five business days:

1. Record root cause and detection gap.
2. Add a deterministic or physical-device regression test.
3. Update the parity matrix and known limitations.
4. Review whether a privacy-safe remote feature-control service is warranted.
5. Confirm no unsupported marketing claim remained live.
