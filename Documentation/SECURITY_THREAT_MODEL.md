# Security Threat Model

Last reviewed: September 4, 2026

This document covers The Climb `1.0 (17)` iPhone release candidate, its Firebase backend, AI generation, community features, Screen Time extensions, Safari content blocker, widgets, and public website. It records implemented controls and remaining launch evidence; it does not treat simulator behavior as proof of Apple framework enforcement.

## Protected Assets

- Firebase identity, profile, struggle, goals, journals, progress, missions, devotionals, and account-deletion state.
- Community posts, reports, groups, membership, reactions, partner links, and leaderboard scores.
- OpenAI credentials, generated-plan usage, rate-limit state, logs, and cost controls.
- Family Controls selections, adult-protection preferences, mission schedules, shared widget state, and Live Activity state.
- Legal/support pages, universal-link association, signing identities, provisioning profiles, and release artifacts.

## Trust Boundaries

- The iOS app and extensions are untrusted clients. They may request actions but may not assign authoritative scores, moderation outcomes, group authority, or report metadata.
- Firebase Authentication establishes user identity. App Check establishes app attestation for protected endpoints; neither is a substitute for server authorization.
- Cloud Functions own mission scoring, leaderboard writes, community/group mutations, reports, reaction uniqueness, AI use, and account cleanup.
- Firestore rules deny direct client writes to backend-owned collections and scope private records to their authenticated owner.
- Apple Family Controls, Device Activity, Managed Settings, Safari extensions, widgets, and Live Activities remain platform-controlled and require signed physical-device verification.

## Implemented Controls

| Risk | Control | Verification |
| --- | --- | --- |
| Cross-account private-data access | UID-scoped Firestore rules and authenticated repositories | Rules inspection and deployment |
| Forged OVR or leaderboard scores | Server-owned mission events and leaderboard writes | Client writes denied; authenticated smoke checks |
| Community impersonation or forged reports | Server derives user identity, post author, category, severity, and timestamps | `reportCommunityPost` deployed; direct report writes denied |
| Reaction inflation | Deterministic per-user/per-post reaction record | Duplicate calls are idempotent |
| Mutation abuse | Per-user, per-action Firestore rate limits | Backend enforcement before mutation handlers |
| Unsafe community content | Server-side text validation plus report/block/delete controls | Backend mutation path and UI flows |
| Group privilege escalation | Backend verifies owner/admin/member transitions | Direct group writes denied |
| Unauthorized AI use and cost spikes | Auth, App Check, daily usage limits, output cap, timeout, bounded retry, same-day cache, deterministic fallback | Functions build, fixtures, deployment, and logs |
| Secret or user-export leakage | Release security scan rejects tracked secrets, private keys, environment files, backups, and exports | `npm run validate:security` |
| Incomplete account deletion | Backend removes private data, leaderboard, community ownership/reactions, reports, AI usage, rate limits, and auth account | Source inspection; physical authenticated test remains |
| Local sensitive preference exposure | Screen Time and domain-rule state use protected App Group storage | Source inspection; device data-protection test remains |
| Supply-chain privacy mismatch | Pinned Swift packages, npm audit, privacy manifests, archive inspection | Build, audit, and archive validator |

## Residual Risks And Launch Gates

1. Complete the physical-iPhone matrix for Screen Time authorization, shields, Device Activity scheduling, Safari enablement, restart recovery, notifications, widgets, authentication, App Check, account deletion, accessibility, and unstable networks.
2. Obtain distribution signing and provisioning for all seven bundle identifiers, then validate the exact App Store archive.
3. Configure Firestore TTL for `aiUsage.expiresAt`, `aiDailyPlans.expiresAt`, and `actionRateLimits.expiresAt`.
4. Configure Firebase/Google Cloud and OpenAI budgets, spend alerts, function-error alerts, and a documented incident owner.
5. Define a human moderation response process for urgent reports, appeals, retention, and support escalation. Automated filtering is not complete moderation.
6. Confirm App Store privacy, age rating, export compliance, content rights, support, and review notes against the submitted binary.
7. Review Organizer symbol warnings for precompiled Firebase/gRPC frameworks. First-party executable and dSYM UUIDs must continue to match.

## Release Decision

The local source, deployed authorization model, automated tests, and development archive support release-candidate status. Production approval requires the distribution archive, physical-device evidence, operational controls, and App Store Connect disclosures listed above.
