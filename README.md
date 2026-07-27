# The Climb

The Climb is a SwiftUI iOS app for daily Christian discipline: devotional, mission, focused action, reflection, recovery, accountability, and progress tracking.

## Current Build

- Five-tab SwiftUI app: Home, Grow, Community, Progress, Profile
- Onboarding flow for age group, goals, struggle, streak goal, and reminder time
- Daily mission and longer devotional generation through a `MissionGenerationService`
- Devotionals include an actual quoted public-domain verse text field
- Local-first persistence through `AppRepository`
- Mission timer, Screen Time focus mode with selected app/category shielding, required reflection, failure logging, and fallback recovery
- OVR, streak, journal, completion rate, and Swift Charts progress views
- Community groups, partners, encouragement feed, group challenges, and leaderboard interactions
- Widget target for mission, streak, and OVR using shared App Group state
- Custom Screen Time shield extensions for The Climb-branded blocked app screens and shield button handling

## Release Integrations

The app is intentionally wired through protocols so release services can replace the local defaults:

- Firebase Auth and Firestore: implement `AppRepository` in `TheClimb/Services/FirebaseIntegration.swift`
- OpenAI: `TheClimb/Info.plist` points at the Firebase Functions proxy; deploy `firebase/functions`, set the `OPENAI_API_KEY` secret, and keep prompt IDs and model settings backend-only
- Screen Time app blocking: request Apple Family Controls approval before relying on app/category shielding in production

Canonical release domain: `https://theclimbapp.org`. Support contact: `support@theclimbapp.org`.

No payments, subscriptions, admin dashboard, or church admin system are included.

## AI Daily Devotionals

See `docs/AI_DAILY_DEVOTIONALS.md` for the exact backend setup. The app never stores an OpenAI API key client-side.

## Production Checklist

See `docs/PRODUCTION_READINESS.md` before TestFlight or App Store submission.
