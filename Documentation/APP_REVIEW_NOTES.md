# App Review Notes

Last reviewed: September 4, 2026

This is a draft for App Store Connect. Replace all bracketed fields with information for the exact submitted build. Do not place reviewer credentials, API keys, recovery codes, or private entitlement correspondence in the repository.

## Review Contact

- Contact name: `[RELEASE CONTACT]`
- Phone: `[PHONE]`
- Email: `support@theclimbapp.org`
- Submitted version/build: `1.0 (17)`
- Test account email: `[ENTER SECURELY IN APP STORE CONNECT]`
- Test account password: `[ENTER SECURELY IN APP STORE CONNECT]`

## Product Summary

The Climb is a free, faith-based focus and Screen Time app for users age 13 and older. Users can create voluntary focus sessions, select distracting apps, categories, and web domains through Apple's Family Controls picker, schedule Focus Rhythms, create app-time boundaries, read a daily devotional, pray, complete missions, reflect, and participate in moderated accountability features.

There are no subscriptions, in-app purchases, advertisements, or paid feature gates.

## Family Controls Purpose

The app requests individual Family Controls authorization from the device owner. It uses:

- Family Controls for privacy-preserving app, category, and web-domain selection;
- Managed Settings to shield the user's selected distractions;
- Device Activity to schedule focus intervals and selected usage thresholds; and
- Shield Configuration and Shield Action extensions to present a branded blocking screen.

This is not a parent or organization dashboard. The Climb does not expose a readable installed-app list, browsing history, search terms, messages, or another person's Screen Time activity.

## How to Review Focus Blocking

Screen Time APIs and shields require a physical iPhone. Simulator behavior is not representative.

1. Sign in with the reviewer account.
2. Open the **Focus** tab.
3. Grant Screen Time access when prompted.
4. Choose one nonessential test app in the distraction picker.
5. Configure a short Focus Session.
6. Start the session.
7. Open the selected app and confirm The Climb's shield appears.
8. Return to The Climb and complete or end the session according to its strictness.

For an intentional session, an early exit requires a reason and a brief delay. A locked session is designed to remain active until its scheduled end, subject to the user's ability to revoke system permission, change settings, or uninstall the app.

## Recurring Rhythms and Boundaries

Focus Rhythms schedule selected restrictions on chosen days and times. App Boundaries use Device Activity thresholds for selected apps or categories. Operating-system scheduling may not trigger at an exact wall-clock second.

The app does not claim to count every app open. Exact app-open boundaries are disabled because Apple does not expose a reliable universal open-count API.

## Permanent Protection

Permanent Protection can request Apple's automatic adult-web-content filtering while its Screen Time policy is active. It supports:

- Standard mode, which can be turned off from the app; and
- Strict mode, which requires a 24-hour waiting period before turn-off.

The app may also shield user-selected apps, categories, and web domains. The feature is intended to create voluntary friction, not an impossible-to-bypass guarantee. A user can revoke authorization, change system settings, or uninstall the app.

## Safari Protection

The submitted build is intended to include a Safari declarative content-blocker extension. The user must enable it in iOS Settings. It reads normalized local domain rules from the shared App Group and returns declarative block or allow rules to Safari.

Safari Protection applies only to Safari content covered by those rules. It does not filter every browser or device network traffic. The build contains no Network Extension, DNS filter, VPN, or device-wide network monitor.

Review path:

1. Enable **The Climb Safari Protection** in Safari extension settings.
2. Return to **Focus** and refresh the Safari status.
3. Add an approved test domain to the local block list.
4. Open that test domain in Safari and confirm blocking.

Do not use or record a real user's browsing data during review.

## Faith and AI Content

The app provides Christian devotionals, World English Bible scripture text, prayer tools, and personalized daily missions. Daily plan generation uses an authenticated Firebase Cloud Function and OpenAI. The API key is server-side. A deterministic local fallback keeps the daily flow available if AI generation fails.

AI output is not pastoral, medical, mental-health, legal, or emergency advice. Community and generated content are filtered and constrained, but users should contact qualified professionals or emergency services when appropriate.

## Community Safety

Community includes encouragement posts, groups, and accountability partners. Users can:

- report a post;
- block a user;
- delete their own post;
- leave groups or accountability links; and
- contact support.

Community and group writes are authenticated and enforced through backend functions. Basic unsafe-language and abuse filtering is applied. The app is not an anonymous public chat service.

## Account and Data Controls

Users can sign in with email/password, Google, or Apple. In Profile they can:

- sign out;
- open Privacy Policy and Terms;
- contact support; and
- delete their account in app.

Account deletion removes the Firebase Authentication account and requests deletion of active user-linked Firestore data, including leaderboard and community ownership records, subject to limited provider backup and security-log retention described in the privacy policy.

## URLs

- Privacy Policy: `https://theclimbapp.org/privacy`
- Terms of Service: `https://theclimbapp.org/terms`
- Support: `https://theclimbapp.org`
- Support email: `support@theclimbapp.org`

## Known Scope Limits

- No Network Extension or device-wide DNS/VPN filtering.
- No exact universal app-open counter.
- No remote parental or church-administrator monitoring.
- No Guardian Mode in the production feature set.
- No production Accountability PIN/approval lock in the production feature set.
- Device Activity reports remain on device and show only aggregate Screen Time values; the app does not expose selected app identities or browsing history.
- No watchOS app.
- iPhone only.
- No subscriptions or in-app purchases.

## Submission Gate

These notes are not ready to paste until:

- Family Controls distribution profiles are confirmed for every participating target;
- an App Store distribution archive is exported and validated;
- the full physical-device matrix passes; and
- bracketed reviewer information is entered securely in App Store Connect.
