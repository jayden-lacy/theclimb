# Backend Security Tests

Run from the repository root:

```sh
npm ci --prefix firebase/functions --ignore-scripts
npm run test:security
```

Prerequisites: Node.js 22, Java 21, and Firebase CLI 15.29.0. The runner detects Homebrew's keg-only Node 22 and Java 21 installations without changing the user's shell or default runtime. CI installs those same major runtimes and the pinned Firebase CLI.

## Isolation

The runner uses `firebase.security-tests.json`, not the production Firebase configuration. Only the Auth and Firestore emulators start, bound to loopback. Tests refuse to run unless both emulator hosts are loopback and the project ID is exactly `demo-theclimb-security`. Cleanup deletes only fixture data in that disposable project.

No service-account file, Firebase login, OpenAI key, App Check debug token, or production account is needed. The test process starts the compiled, exported HTTP handlers in a local Express server. The real Firebase Admin SDK verifies tokens issued by the Auth emulator and writes to the Firestore emulator. There are no mocked authorization decisions or mocked database transactions.

Production App Check is not disabled. Normal authenticated fixture requests omit attestation only inside the isolated emulator process. Separate assertions enable enforcement and confirm that all 17 endpoints reject missing App Check. Successful physical-device attestation is still a release gate.

## Coverage

- Own-account profile and nested-state CRUD; rejection of cross-account access, identity replacement, and enumeration.
- Owner-filtered queries for missions, devotionals, journals, and progress; rejection of unscoped reads and owner changes.
- Denial of direct client mutations to community, leaderboard, scores, reports, reactions, and rate-limit state.
- Partner invite acceptance, member-only reads, valid check-ins, and rejection of forged ownership, membership, and counters.
- All 17 HTTP endpoints reject unauthenticated and non-POST requests.
- Missing/invalid authentication, missing enforced App Check, deleted accounts, and disabled accounts.
- Trusted leaderboard values independent of client-submitted OVR and user IDs.
- Backend post/group filtering, unique reactions under concurrency, server-derived reports, and author-only post deletion.
- Owner/admin/member group permissions and per-user mutation limits.
- Concurrent mission retries, cross-account document collision protection, authoritative terminal outcomes, and recovery prerequisites.
- Account-data cleanup and preservation of another account's records.

## Findings Fixed September 5, 2026

The first run had 56 passes and six failures. Those failures exposed:

1. A recursive Firestore wildcard also matching its parent profile, bypassing profile identity validation.
2. Repeated partner-link validation exceeding the rules expression budget on legitimate check-ins.
3. Client-supplied mission and journal IDs being written through Admin SDK without checking the existing document owner.
4. Client snapshot status overriding a server-recorded completion or failure.

The fixes narrow the recursive match, evaluate shared partner validation once, verify destination ownership in the scoring transaction, and restore terminal status from the server ledger. Token validation now checks revocation/disabled-account state explicitly, rather than relying on emulator-specific token behavior.

After fixes and two additional authentication/recovery regressions, all 64 tests passed on Node 22.23.2 with Java 21 and Firebase CLI 15.29.0. TypeScript compilation, offline daily-plan fixtures, and the repository security scan also passed. GitHub runs this suite on relevant pull requests and pushes; deployment remains a separate action.

## Limits

These tests do not prove Apple/Google OAuth UI behavior, physical-device App Check, Screen Time enforcement, production indexes, human moderation response, or successful account/provider revocation from the iOS app. Account-data cleanup tests cover the HTTP data-deletion contract; provider revocation and Firebase Auth deletion remain a separate client workflow.

Mission issuance and the claim that a real-world activity was completed still originate on the client. Denying direct score writes and preventing duplicate mission awards do not establish a cheat-proof leaderboard. Server-issued mission eligibility and per-day reward limits remain a separate hardening task before making stronger scoring-integrity claims.

The emulator is not a substitute for staging/load tests. It does not enforce every production quota or composite index requirement. See the [Firebase rules testing guide](https://firebase.google.com/docs/rules/unit-tests) and [emulator differences](https://firebase.google.com/docs/emulator-suite/connect_firestore#how_the_cloud_firestore_emulator_differs_from_production).
