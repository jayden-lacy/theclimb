# Production Readiness

Use this checklist before shipping The Climb through TestFlight or the App Store.

## Apple Configuration

- Set the final Apple Developer team on the app and widget targets.
- Register these bundle IDs in the Apple Developer portal:
  - `com.jaydenlacy.theclimb`
  - `com.jaydenlacy.theclimb.widget`
  - `com.jaydenlacy.theclimb.shieldconfiguration`
  - `com.jaydenlacy.theclimb.shieldaction`
- Register the App Group exactly as `group.com.jaydenlacy.theclimb` and enable it on the app, widget, and shield extension targets.
- Request and enable the Family Controls entitlement for the main app and both shield extension bundle IDs before relying on Screen Time blocking outside development:
  - `com.jaydenlacy.theclimb`
  - `com.jaydenlacy.theclimb.shieldconfiguration`
  - `com.jaydenlacy.theclimb.shieldaction`
- In the entitlement request, describe the app blocking feature as user-controlled focus protection for voluntary daily missions. Be clear that there is no parent/admin dashboard and no monitoring of another person.
- Confirm App Store Connect privacy answers match the actual Firebase/Auth/community data collection.
- Build and archive a Release build in Xcode, then upload through Organizer.

## Firebase Configuration

- Keep `GoogleService-Info.plist` in the main app target only.
- Enable Email/Password and Google providers in Firebase Auth.
- Deploy the `generateDailyPlan` Cloud Function after setting `OPENAI_API_KEY` as a Firebase secret.
- Enable Firebase App Check for the iOS app in Firebase Console. Use Debug provider for simulator/dev builds and register the debug token printed by Xcode. Use a production provider for release builds before setting `ENFORCE_APP_CHECK=true`.
- Deploy `generateDailyPlan` with these environment values when App Check is configured. Start from `firebase/functions/.env.example`:
  - `ENFORCE_APP_CHECK=true`
  - `AI_DAILY_LIMIT_PER_USER=6` or another low launch-safe number
  - `OPENAI_MODEL=gpt-5.4-mini` unless intentionally changed
- Deploy Firestore rules with `firebase deploy --only firestore:rules,firestore:indexes` so users can only read/write their own profile, mission, devotional, journal, and progress documents while community data uses separate authenticated rules.
- Confirm the backend-only `aiUsage` collection exists after testing. Client access is denied by the catch-all Firestore rule; only Cloud Functions should write it.
- Enable Firestore TTL on `aiUsage.expiresAt` so old rate-limit records are cleaned up automatically.
- Keep the OpenAI key and stored prompt ID backend-only. Never put them in Swift, `Info.plist`, or Remote Config.
- Set Cloud Billing budgets and alerts for Firebase/Google Cloud, OpenAI usage limits, and log-based alerts for repeated `generateDailyPlan` failures.

## Backend Hardening

- `generateDailyPlan` requires a Firebase Auth ID token before doing any AI work.
- The iOS client sends `X-Firebase-AppCheck` on AI requests. The function can enforce it with `ENFORCE_APP_CHECK=true` after Firebase App Check is configured.
- The function rate-limits AI generations per signed-in user per day through Firestore `aiUsage` records.
- The function trims profile/history payloads before sending them to OpenAI and caps model output tokens to control cost.
- The function writes structured logs for generation attempts, App Check failures, rate-limit rejections, and AI fallback use.
- The function returns a deterministic fallback plan if OpenAI or the stored prompt fails, so the app does not dead-end the daily flow.

## Verification

- Run a clean Debug simulator build.
- Run a Release simulator build.
- Complete onboarding with email/password and Google.
- Confirm the Home screen creates one mission and devotional per local calendar day.
- Complete, fail, and recover a mission; verify OVR, streak, journal, widget, and leaderboard update.
- Background and foreground the app; verify missed-day streaks recalculate and persist.
- Add a community post, join a group, check in with a partner, and tap Amen.
- Report a community post, block a user, delete your own post, and confirm filtered language cannot be posted.
- Host the Privacy Policy and Terms of Service at public URLs before App Store submission, then use those URLs in App Store Connect.
- Add the widget and verify mission, streak, and OVR are read from the App Group.
- Test on a physical iPhone before TestFlight. Simulator is not enough for launch.

## Real Device Test Matrix

- Screen Time permissions: request authorization, cancel authorization, approve authorization, then relaunch.
- App blocking: select apps, begin a mission, confirm selected apps show the custom shield, end the mission, confirm apps unblock.
- Notifications: allow, deny, scheduled daily reminder, incomplete mission reminder, streak alert, and recovery prompt.
- Google login: first sign-in, returning sign-in, sign out, delete account.
- Apple login: first sign-in, returning sign-in, sign out, delete account, recent-login-required delete flow.
- Widgets: add widget, verify mission/streak/OVR data, complete mission in app, confirm widget refreshes.
- Watch app sync: install watch app, view mission, start/complete from watch if supported, verify phone state sync.
- Firebase save/load: install fresh, sign in, complete onboarding, force quit, relaunch, sign in on another device, confirm profile/mission/devotional/journal/progress reload.
- App Check: with enforcement off, confirm AI works and debug token appears; register token, turn enforcement on in a test environment, confirm AI still works.

## Known Release Dependencies

- Real Screen Time app shielding requires the approved Apple Family Controls capability; the app-selection flow and custom shield extensions are implemented.
- Server-side daily pregeneration is not required for launch; the app currently generates the next plan when the user opens the app on a new day.
- The watch app source exists, but watch-to-phone synchronization should be verified on real devices before advertising Apple Watch support.

## Official References

- Apple: https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement
- Apple: https://developer.apple.com/documentation/xcode/configuring-family-controls
- Firebase: https://firebase.google.com/docs/app-check/ios/custom-resource
- Firebase: https://firebase.google.com/docs/app-check
