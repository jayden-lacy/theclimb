# Production Readiness

Use this checklist before shipping The Climb through TestFlight or the App Store.

Current 1.0 release decision: ship iPhone-only and submit iPhone screenshots only. The Xcode project sets `TARGETED_DEVICE_FAMILY = 1` for the app, widget, shield extensions, and DeviceActivity monitor. Do not upload iPad screenshots unless the project is intentionally moved back to universal and a full iPad QA pass is completed.

## Verified Local Baseline

Verified on September 3-4, 2026:

- Xcode 26.6 recognizes the iPhone app, widget, shield configuration, shield action, DeviceActivity monitor, and native unit-test targets. The release intentionally contains no watchOS target.
- Debug and optimized Release builds succeed, static analysis passes, and all 50 native tests pass.
- Firebase iOS and Google Sign-In packages resolve at their pinned versions.
- The main app, widget, shield configuration, Device Activity monitor, Device Activity report, and Safari content blocker privacy manifests are tracked and included in their target resources.
- The Shield Action extension does not currently access App Group `UserDefaults` or another required-reason API. Add a manifest to that target if its implementation changes.
- Cloud Functions compile and the offline daily-plan validation script passes.
- Firestore rules/indexes and all 17 second-generation functions were deployed successfully to `the-climb0`. The deployed `generateDailyPlan` source matched the local release source. Post-deploy unauthenticated AI, community post/reaction/report, mission-scoring, and account-deletion smoke requests returned HTTP 401.
- Community posts, groups, leaderboard scores, mission scoring, and account deletion use authenticated callable backend functions. Firestore client writes to server-owned collections are denied.
- The current codebase uses local World English Bible text, authenticated AI generation, bounded retries/timeouts, same-day caching, per-user rate limits, and deterministic fallback plans.
- `https://theclimbapp.org`, `/privacy`, `/terms`, `/download`, and `/.well-known/apple-app-site-association` were deployed through Cloudflare and returned HTTP 200.
- A development-signed arm64 archive for `1.0 (17)` succeeds and contains valid signatures, all six extensions, expected privacy manifests, and app/extension dSYMs.
- App Store export for build 17 is blocked until Xcode has the release Apple account, an Apple Distribution certificate, and profiles for all shipping bundle identifiers.
- Three current iPhone screenshots were regenerated from the build 17 release candidate at exactly 1284 x 2778 in `App Store Previews - 1284x2778`.

## Apple Configuration

- Confirm Apple Developer team `BLH227B4U7` remains selected on the app and every extension before archiving.
- Register these exact bundle IDs in the Apple Developer portal:
  - Main app: `com.jaydenlacy.theclimb`
  - Widget extension: `com.jaydenlacy.theclimb.widget`
  - Shield configuration extension: `com.jaydenlacy.theclimb.shieldconfiguration`
  - Shield action extension: `com.jaydenlacy.theclimb.shieldaction`
  - DeviceActivity monitor extension: `com.jaydenlacy.theclimb.deviceactivitymonitor`
  - Device Activity report extension: `com.jaydenlacy.theclimb.deviceactivityreport`
  - Safari content blocker extension: `com.jaydenlacy.theclimb.contentblocker`
- Register the App Group exactly as `group.com.jaydenlacy.theclimb` and enable it on all seven shipping bundle identifiers where declared.
- Request and enable the Family Controls entitlement for every target that participates in Screen Time blocking before relying on shielding outside development:
  - Main app: `com.jaydenlacy.theclimb`
  - Shield configuration extension: `com.jaydenlacy.theclimb.shieldconfiguration`
  - Shield action extension: `com.jaydenlacy.theclimb.shieldaction`
  - DeviceActivity monitor extension: `com.jaydenlacy.theclimb.deviceactivitymonitor`
  - Device Activity report extension: `com.jaydenlacy.theclimb.deviceactivityreport`
- In the entitlement request, describe the app blocking feature as user-controlled focus protection for voluntary daily missions. Be clear that there is no parent/admin dashboard and no monitoring of another person.
- Confirm App Store Connect device support is iPhone-only for 1.0. Submit the iPhone screenshot set only; do not provide iPad screenshots for this release.
- Confirm privacy manifests remain valid for every shipped binary. The main app declares the account, personalization, user-content, product-interaction, and crash data used by the current Firebase implementation. Target-specific manifests cover the widget, shield configuration, Device Activity monitor, Device Activity report, and Safari content blocker. The Shield Action extension currently has no required-reason API use.
- Confirm App Store Connect privacy answers match the actual Firebase/Auth/community data collection.
- Use `https://theclimbapp.org/privacy` and `https://theclimbapp.org/terms` in App Store Connect. Use `support@theclimbapp.org` as the support contact across docs, website, and in-app legal/support fallback copy.
- Build and archive a Release build in Xcode, then upload through Organizer.

## Firebase Configuration

- Keep `GoogleService-Info.plist` in the main app target only.
- Enable Email/Password and Google providers in Firebase Auth.
- Deploy the `generateDailyPlan` Cloud Function after setting `OPENAI_API_KEY` as a Firebase secret.
- Keep Firebase App Check enabled for the iOS app. Debug builds use the Debug provider; Release builds currently use DeviceCheck. Production enforcement is enabled and rejects requests without a valid token. Register simulator debug tokens only in development, and verify a release-signed physical-device request before public launch. App Attest is a stronger future provider but requires matching Firebase Console registration before changing the client.
- Deploy `generateDailyPlan` with these environment values when App Check is configured. Start from `firebase/functions/.env.example`:
  - `ENFORCE_APP_CHECK=true`
  - `AI_DAILY_LIMIT_PER_USER=6` or another low launch-safe number
  - `OPENAI_MODEL=gpt-5.4-mini` unless intentionally changed
  - Optional `OPENAI_MAX_OUTPUT_TOKENS=1300`; the function clamps this to the 800-1300 range.
  - Optional `OPENAI_TIMEOUT_MS=20000` and `OPENAI_RETRY_COUNT=1` for bounded retry behavior.
- Deploy Firestore rules with `firebase deploy --only firestore:rules,firestore:indexes` after every rules change. Users may access only their own private data, while posts, groups, leaderboard data, and mission-score events remain backend-owned.
- Confirm the backend-only `aiUsage` and `aiDailyPlans` collections exist after testing. Client access is denied by the catch-all Firestore rule; only Cloud Functions should write them.
- Enable Firestore TTL on `aiUsage.expiresAt`, `aiDailyPlans.expiresAt`, and `actionRateLimits.expiresAt` so old rate-limit and cached-plan records are cleaned up automatically.
- Keep the OpenAI key and stored prompt ID backend-only. Never put them in Swift, `Info.plist`, or Remote Config.
- Set Cloud Billing budgets and alerts for Firebase/Google Cloud, OpenAI usage limits, and log-based alerts for repeated `generateDailyPlan` failures.
- Run `npm run validate:security` from the repository root before each release. It rejects tracked secrets, private keys, `.env` files, Firebase backups/exports, and generated build artifacts, then fails on high or critical npm advisories.

## Backend Hardening

- `generateDailyPlan` requires a Firebase Auth ID token before doing any AI work.
- The iOS client sends `X-Firebase-AppCheck` on AI requests. The function can enforce it with `ENFORCE_APP_CHECK=true` after Firebase App Check is configured.
- The function checks `aiDailyPlans` for a same-user same-date cached plan before rate limiting or calling OpenAI.
- User-requested plan regeneration skips the same-day cache, remains rate-limited, and overwrites the same cache document with the replacement plan.
- The function rate-limits uncached AI generations per signed-in user per day through Firestore `aiUsage` records.
- The function trims profile/history payloads before sending them to OpenAI and caps model output tokens to control cost.
- The function uses local World English Bible (WEB) public-domain verse text instead of a runtime external Bible API dependency.
- First-week onboarding ramp context is passed to AI and mirrored client-side so new users get guided early missions even if fallback content is used.
- The function writes structured logs for generation attempts, cache hits, OpenAI latency/usage, App Check failures, rate-limit rejections, and AI fallback use.
- The function returns a deterministic fallback plan if OpenAI or the stored prompt fails, so the app does not dead-end the daily flow.
- Firestore denies direct client writes to `/posts`, `/reports`, `/postAmens`, and `/actionRateLimits`. Creation, one-Amen-per-user reactions, server-verified reports, deletion, filtering, and blocking flow through authenticated callable functions with per-user mutation limits.
- `/partnerLinks` rules only allow pending invite acceptance to set accepted fields. Accepted members can increment only their own action counters and last-check-in field with `lastInteraction`; truthful interaction text and action rate limits remain client-trusted and should move to a Cloud Function if abuse appears.
- Firestore denies direct client writes to `/groups`. Group creation, join/leave, admin promotion, member removal, and deletion are enforced by callable functions.
- Firestore denies direct client writes to `/leaderboards`, `/userScores`, and `/missionScoreEvents`. Leaderboard values and OVR-changing mission outcomes are computed and written by authenticated callable functions.

## Verification

- Run a clean Debug simulator build.
- Run a Release simulator build.
- Run `xcodebuild test` against an available iPhone simulator and confirm all `ClimbCoreTests` pass.
- Run `npm run validate:archive -- <archive-path> 1.0 17 distribution` against the final upload archive. Confirm all first-party dSYMs match and review any remaining precompiled Firebase/gRPC framework symbol warnings in Organizer.
- Complete onboarding with email/password and Google.
- Confirm the Home screen creates one mission and devotional per local calendar day.
- Before starting a pending mission, use "Try a different plan" once and confirm the replacement mission/devotional save, widgets refresh, and repeat app opens return the replacement from cache.
- Complete, fail, and recover a mission; verify OVR, streak, journal, widget, and leaderboard update.
- Background and foreground the app; verify missed-day streaks recalculate and persist.
- Add a community post, join a group, check in with a partner, and tap Amen.
- Report a community post, block a user, delete your own post, and confirm filtered language cannot be posted.
- Confirm App Store Connect uses the live `https://theclimbapp.org/privacy` and `https://theclimbapp.org/terms` URLs.
- Confirm `https://theclimbapp.org/download` and `https://theclimbapp.org/.well-known/apple-app-site-association` continue to return HTTP 200 immediately before submission.
- Upload the three current files from `App Store Previews - 1284x2778`. They are 1284 x 2778 and do not contain the previous Home/tab-bar clipping.
- Add the widget on a physical iPhone and verify mission, streak, and OVR are read from the App Group after app relaunch and mission completion.
- Test on a physical iPhone before TestFlight. Simulator is not enough for launch.

## Real Device Test Matrix

- Screen Time permissions: request authorization, cancel authorization, approve authorization, then relaunch on a physical iPhone.
- App blocking: select apps, begin a mission, confirm selected apps show the custom shield, confirm the DeviceActivity monitor starts and stops the mission interval, end the mission, then confirm apps unblock.
- Notifications: allow, deny, scheduled daily reminder, incomplete mission reminder, streak alert, and recovery prompt.
- Google login: first sign-in, returning sign-in, sign out, delete account.
- Apple login: first sign-in, returning sign-in, sign out, delete account, recent-login-required delete flow.
- Widgets: add widget on a physical iPhone, verify mission/streak/OVR data, complete mission in app, confirm widget refreshes from App Group state.
- Firebase save/load: install fresh, sign in, complete onboarding, force quit, relaunch, sign in on another device, confirm profile/mission/devotional/journal/progress reload.
- App Check: register simulator debug tokens only for development, then confirm AI works from build 14 or a later release-signed physical-device build while production enforcement remains enabled.
- Accessibility: verify Dynamic Type through at least Accessibility Large, VoiceOver order and labels, Reduce Motion behavior, sufficient contrast, and 44-point minimum interactive targets.
- Network resilience: test launch, cached Home content, mission completion, and sign-out while offline or on an unstable connection.

## Known Release Dependencies

- Real Screen Time app shielding requires the approved Apple Family Controls capability; the app-selection flow and custom shield extensions are implemented.
- The DeviceActivity monitor bundle ID `com.jaydenlacy.theclimb.deviceactivitymonitor` must be registered and entitled with the rest of the Screen Time bundle set.
- Server-side daily pregeneration is not required for launch; the app currently generates the next plan when the user opens the app on a new day.
- Website `/download` redirects to the App Store when the Cloudflare Worker `APP_STORE_URL` environment variable is set to a valid Apple URL. Without that variable, it serves a public fallback download page instead of an internal setup error.
- Build 17 is the current release candidate. Do not submit build 15 as evidence for this feature set. If App Store Connect rejects build 17, increment `CURRENT_PROJECT_VERSION`, archive again, and upload a new build.
- The remaining launch gate is a real-device pass for Family Controls, DeviceActivity, custom shields, notifications, widgets, release App Check, Google/Apple sign-in, and account deletion. Simulator evidence is not sufficient for these platform integrations.
- App Store Connect privacy, age-rating, encryption, content-rights, support URL, review notes, and build-selection fields still require final confirmation before pressing Submit for Review.
- Firebase's current Google Cloud dependency chain reports seven moderate transitive `uuid` advisories and no high or critical advisories. The project is on current stable Firebase Admin/Functions releases; do not use npm's suggested forced downgrade.
- The static threat model is tracked in `Documentation/SECURITY_THREAT_MODEL.md`; physical-device behavior, moderation operations, billing alerts, and App Store disclosures remain launch evidence rather than source-code assertions.

## Official References

- Apple: https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement
- Apple: https://developer.apple.com/documentation/xcode/configuring-family-controls
- Firebase: https://firebase.google.com/docs/app-check/ios/custom-resource
- Firebase: https://firebase.google.com/docs/app-check
