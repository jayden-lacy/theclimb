# Production Readiness

Use this checklist before shipping The Climb through TestFlight or the App Store.

Current 1.0 release decision: ship iPhone-only and submit iPhone screenshots only. The Xcode project sets `TARGETED_DEVICE_FAMILY = 1` for the app, widget, shield extensions, and DeviceActivity monitor. Do not upload iPad screenshots unless the project is intentionally moved back to universal and a full iPad QA pass is completed.

## Apple Configuration

- Set the final Apple Developer team on the app and widget targets.
- Register these exact bundle IDs in the Apple Developer portal:
  - Main app: `com.jaydenlacy.theclimb`
  - Widget extension: `com.jaydenlacy.theclimb.widget`
  - Shield configuration extension: `com.jaydenlacy.theclimb.shieldconfiguration`
  - Shield action extension: `com.jaydenlacy.theclimb.shieldaction`
  - DeviceActivity monitor extension: `com.jaydenlacy.theclimb.deviceactivitymonitor`
- Register the App Group exactly as `group.com.jaydenlacy.theclimb` and enable it on the app, widget, shield configuration, shield action, and DeviceActivity monitor targets.
- Request and enable the Family Controls entitlement for every target that participates in Screen Time blocking before relying on shielding outside development:
  - Main app: `com.jaydenlacy.theclimb`
  - Shield configuration extension: `com.jaydenlacy.theclimb.shieldconfiguration`
  - Shield action extension: `com.jaydenlacy.theclimb.shieldaction`
  - DeviceActivity monitor extension: `com.jaydenlacy.theclimb.deviceactivitymonitor`
- In the entitlement request, describe the app blocking feature as user-controlled focus protection for voluntary daily missions. Be clear that there is no parent/admin dashboard and no monitoring of another person.
- Confirm App Store Connect device support is iPhone-only for 1.0. Submit the iPhone screenshot set only; do not provide iPad screenshots for this release.
- Confirm privacy manifests are present, included in target membership, and valid for every shipped binary. The main app and widget manifests are tracked; shield configuration and DeviceActivity monitor manifests are present locally and referenced by the project but must be reviewed and committed. Shield action currently has no manifest or resources entry; add one before archive if it accesses UserDefaults, App Group storage, or other required-reason APIs.
- Confirm App Store Connect privacy answers match the actual Firebase/Auth/community data collection.
- Use `https://theclimbapp.org/privacy` and `https://theclimbapp.org/terms` in App Store Connect. Use `support@theclimbapp.org` as the support contact across docs, website, and in-app legal/support fallback copy.
- Build and archive a Release build in Xcode, then upload through Organizer.

## Firebase Configuration

- Keep `GoogleService-Info.plist` in the main app target only.
- Enable Email/Password and Google providers in Firebase Auth.
- Deploy the `generateDailyPlan` Cloud Function after setting `OPENAI_API_KEY` as a Firebase secret.
- Enable Firebase App Check for the iOS app in Firebase Console. Use Debug provider only for simulator/dev builds and register the debug token printed by Xcode. Configure a real release provider such as App Attest or DeviceCheck for TestFlight/App Store builds before setting `ENFORCE_APP_CHECK=true`.
- Deploy `generateDailyPlan` with these environment values when App Check is configured. Start from `firebase/functions/.env.example`:
  - `ENFORCE_APP_CHECK=true`
  - `AI_DAILY_LIMIT_PER_USER=6` or another low launch-safe number
  - `OPENAI_MODEL=gpt-5.4-mini` unless intentionally changed
  - Optional `OPENAI_MAX_OUTPUT_TOKENS=1300`; the function clamps this to the 800-1300 range.
  - Optional `OPENAI_TIMEOUT_MS=20000` and `OPENAI_RETRY_COUNT=1` for bounded retry behavior.
- Deploy Firestore rules with `firebase deploy --only firestore:rules,firestore:indexes` so users can only read/write their own profile, mission, devotional, journal, and progress documents while community data uses separate authenticated rules.
- Confirm the backend-only `aiUsage` and `aiDailyPlans` collections exist after testing. Client access is denied by the catch-all Firestore rule; only Cloud Functions should write them.
- Enable Firestore TTL on `aiUsage.expiresAt` and `aiDailyPlans.expiresAt` so old rate-limit and cached-plan records are cleaned up automatically.
- Keep the OpenAI key and stored prompt ID backend-only. Never put them in Swift, `Info.plist`, or Remote Config.
- Set Cloud Billing budgets and alerts for Firebase/Google Cloud, OpenAI usage limits, and log-based alerts for repeated `generateDailyPlan` failures.

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
- Firestore community rules validate `/posts` ownership and schema, require `authorID == userID`, cap post body length, require initial `amenCount == 0`, and only allow author body edits or one-count amen increments.
- `/partnerLinks` rules only allow pending invite acceptance to set accepted fields. Accepted members can increment only their own action counters and last-check-in field with `lastInteraction`; truthful interaction text and action rate limits remain client-trusted and should move to a Cloud Function if abuse appears.
- `/groups` self join/leave writes can only add or remove the caller from `memberIDs` and the caller's own `memberNames` entry. Broader group detail, member, and admin edits require an existing group admin.
- `/leaderboards` still allow client writes to the signed-in user's own entry, constrained to `id`, `userID`, `name`, `ovrScore`, `streak`, and `updatedAt`. Score and streak integrity remain client-trusted until leaderboard updates move to a backend writer.

## Verification

- Run a clean Debug simulator build.
- Run a Release simulator build.
- Run a Release archive validation and confirm no privacy manifest warnings are emitted for the app, widget, shield configuration, shield action, or DeviceActivity monitor binaries.
- Complete onboarding with email/password and Google.
- Confirm the Home screen creates one mission and devotional per local calendar day.
- Before starting a pending mission, use "Try a different plan" once and confirm the replacement mission/devotional save, widgets refresh, and repeat app opens return the replacement from cache.
- Complete, fail, and recover a mission; verify OVR, streak, journal, widget, and leaderboard update.
- Background and foreground the app; verify missed-day streaks recalculate and persist.
- Add a community post, join a group, check in with a partner, and tap Amen.
- Report a community post, block a user, delete your own post, and confirm filtered language cannot be posted.
- Host the Privacy Policy and Terms of Service at public URLs before App Store submission, then use those URLs in App Store Connect.
- Add the widget on a physical iPhone and verify mission, streak, and OVR are read from the App Group after app relaunch and mission completion.
- Test on a physical iPhone before TestFlight. Simulator is not enough for launch.

## Real Device Test Matrix

- Screen Time permissions: request authorization, cancel authorization, approve authorization, then relaunch on a physical iPhone.
- App blocking: select apps, begin a mission, confirm selected apps show the custom shield, confirm the DeviceActivity monitor starts and stops the mission interval, end the mission, then confirm apps unblock.
- Notifications: allow, deny, scheduled daily reminder, incomplete mission reminder, streak alert, and recovery prompt.
- Google login: first sign-in, returning sign-in, sign out, delete account.
- Apple login: first sign-in, returning sign-in, sign out, delete account, recent-login-required delete flow.
- Widgets: add widget on a physical iPhone, verify mission/streak/OVR data, complete mission in app, confirm widget refreshes from App Group state.
- Watch: do not market or submit Watch screenshots until a real Watch target is present in the Xcode project and paired-device sync is implemented and verified.
- Firebase save/load: install fresh, sign in, complete onboarding, force quit, relaunch, sign in on another device, confirm profile/mission/devotional/journal/progress reload.
- App Check: with enforcement off, confirm AI works and debug token appears; register the debug token for development, configure the release provider for `com.jaydenlacy.theclimb`, turn enforcement on in a test environment, and confirm AI still works from a release-signed physical device build.

## Known Release Dependencies

- Real Screen Time app shielding requires the approved Apple Family Controls capability; the app-selection flow and custom shield extensions are implemented.
- The DeviceActivity monitor bundle ID `com.jaydenlacy.theclimb.deviceactivitymonitor` must be registered and entitled with the rest of the Screen Time bundle set.
- Server-side daily pregeneration is not required for launch; the app currently generates the next plan when the user opens the app on a new day.
- Watch source files exist in the repository, but no Watch native target is registered in the Xcode project. Do not advertise Apple Watch support until the target, archive, screenshots, and paired-device sync are real.
- Website `/download` returns `503` until the Cloudflare Worker `APP_STORE_URL` environment variable is set to a valid Apple App Store URL. Keep public copy launch-pending until that variable points to the live listing.

## Official References

- Apple: https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement
- Apple: https://developer.apple.com/documentation/xcode/configuring-family-controls
- Firebase: https://firebase.google.com/docs/app-check/ios/custom-resource
- Firebase: https://firebase.google.com/docs/app-check
