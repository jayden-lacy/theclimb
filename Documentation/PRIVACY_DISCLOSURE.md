# Privacy Disclosure

Last reviewed: July 29, 2026

This document maps the current implementation to release disclosures. It supports, but does not replace, the public privacy policy or the App Store Connect questionnaire. Reconcile it against the exact archived binary and current provider documentation before submission.

## Privacy Position

The Climb:

- does not sell personal information;
- does not show third-party advertising;
- does not perform cross-app tracking;
- does not use Screen Time or browsing information for advertising;
- does not receive a readable list of installed apps from Family Controls;
- does not upload `FamilyActivitySelection` token blobs to Firebase;
- does not collect full browsing history or search terms; and
- has no Network Extension, DNS filter, or VPN traffic inspection.

## Data Inventory

| Data | Linked to account | Stored location | Purpose | User control |
| --- | --- | --- | --- | --- |
| Name and email | Yes | Firebase Authentication and user profile | Account functionality and display | Edit where supported; delete account |
| Firebase user ID | Yes | Firebase Authentication and Firestore | Authentication, ownership, sync, abuse prevention | Delete account |
| Sign-in provider | Yes | Firebase Authentication | Authentication and reauthentication | Sign out or delete account |
| Age group | Yes | User profile | Age-appropriate mission and lesson maturity | Profile/account deletion |
| Goals, struggle, and faith preferences | Yes | User profile and synchronized snapshot | Product personalization | Profile/account deletion |
| Missions, devotionals, prayer, habits, journal, reflections, progress, streaks, OVR, badges | Yes | Local snapshot and Firestore | Core functionality, sync, personalization | In-app controls where available; delete account |
| Community posts, groups, partner links, reports, and blocked users | Yes | Firestore and local snapshot | Community, accountability, safety, moderation | Delete own post, leave/block/report, delete account |
| AI generation context | Yes during request | Firebase Function and OpenAI request | Generate a daily mission and devotional | Avoid optional sensitive text; delete account data |
| AI cache and usage counters | Yes by user/date key | Firestore backend-only collections | Reliability, cost control, and rate limiting | TTL and account deletion path |
| Crash and diagnostic data | Generally not intentionally linked by product logic | Firebase Crashlytics/provider systems | Reliability and security | Governed by provider and platform controls |
| Product interactions | May be linked to the local or authenticated user context | Local state, Firestore, and Crashlytics logs | App functionality, personalization, and diagnostics | Delete account where linked |
| Screen Time selection tokens | No readable app identity available to The Climb | Local shared App Group | Apply selected restrictions | Change selection, revoke permission, remove app |
| Focus policies, sessions, rhythms, boundaries, and protected-time records | Local device context | Local shared App Group | Operate and report The Climb focus behavior | Edit/remove policies or remove app |
| Local adult-protection domain rules | Not uploaded by the current implementation | Local shared App Group | Apply local Screen Time and Safari rules | Add/remove rules or disable protection |
| Browsing history and search terms | No | Not collected | Not used | Not applicable |
| Purchase history | No | Not collected | No IAP exists | Not applicable |

## App Store Privacy Categories

The main privacy manifest currently declares:

- Name
- Email Address
- User ID
- Sensitive Info
- Other User Content
- Product Interaction
- Crash Data

Expected purposes are app functionality and, where applicable, product personalization, analytics/diagnostics, or abuse prevention. Tracking is declared false.

Before submission:

- [ ] Compare App Store Connect answers with the main app privacy manifest.
- [ ] Review the privacy manifests bundled by Firebase, Google Sign-In, and their transitive SDKs.
- [ ] Confirm whether provider SDK behavior requires additional Device ID or Diagnostics disclosures under Apple's current definitions.
- [ ] Confirm Crashlytics collection and linking answers using the exact release configuration.
- [ ] Confirm no new analytics SDK, ad SDK, or tracking domain is present.
- [ ] Confirm all declared purposes are necessary and reflected in the public policy.

No final App Store Connect privacy questionnaire was inspected during this audit.

## Screen Time and Adult Protection

Apple Family Controls supplies opaque application, category, and web-domain tokens. The Climb stores those tokens locally in:

`group.com.jaydenlacy.theclimb`

The current implementation does not upload these token blobs to Firebase. Device Activity and Managed Settings enforcement occurs through Apple frameworks and extensions.

The embedded Device Activity Report extension aggregates authorized Screen Time data on device. It stores only totals, daily duration and pickup counts, selected app/category aggregate duration, and an aggregate distracting-hour value in a protected App Group file. It does not persist app identities, token descriptions, URLs, domains, or browsing history.

Permanent Protection may request Apple's automatic adult-web-content filter and apply user-selected local domain rules. Adult-protection state and Safari block/allow domain rules are stored in App Group files protected by iOS Data Protection. The Safari content blocker does not receive general Safari history from the app.

Support and diagnostics must never request or log:

- full browsing history;
- explicit search terms;
- raw Screen Time token blobs;
- full blocked URLs;
- another person's private activity; or
- screenshots containing unrelated personal browsing information.

Use aggregate evidence such as permission state, policy type, extension enabled state, event timestamp, OS version, and whether a test rule passed.

## AI Processing

The iOS app sends a limited, sanitized daily-plan request to an authenticated Firebase Function. Relevant context may include:

- age group;
- goals and main struggle;
- mission difficulty and recent outcomes;
- streak consistency;
- recent reflection signals; and
- requested daily-plan date.

The Firebase Function calls OpenAI using a server-held secret. It uses structured output, bounded timeouts/retries, per-user rate limits, same-day caching, and deterministic fallback content. The OpenAI key and stored prompt identifier must never be included in the app binary.

Do not transmit Screen Time token blobs, installed-app identities, browsing history, or raw blocked URLs to OpenAI.

## Community and Safety

Community data is user-generated and linked to the posting or participating account. The product includes report, block, own-post deletion, group administration, and support paths. Backend enforcement owns community posts and groups.

Moderation reports and security records may be retained for a limited period when needed to prevent abuse, investigate reports, comply with law, or protect users. The public privacy policy must describe that limited retention without promising immediate deletion from provider backups.

## Retention and Deletion

Account deletion is available in app and is intended to:

1. reauthenticate the user when required;
2. delete active user-linked backend records;
3. remove leaderboard and community ownership/membership data handled by backend cleanup;
4. revoke or disconnect supported authentication providers where applicable;
5. delete the Firebase Authentication account; and
6. clear local app state.

Provider backups, abuse-prevention records, and diagnostic logs may persist temporarily under provider retention schedules. Validate account deletion on a physical device for email/password, Google, and Apple before submission.

## Privacy Manifest Coverage

Source privacy manifests are present for:

- main app;
- widget;
- shield configuration;
- Device Activity monitor; and
- Safari content blocker.

The Shield Action extension currently does not read shared `UserDefaults`. Recheck this before every release. If it begins using a required-reason API, add an accurate target privacy manifest.

## Public Documents and Contact

- Privacy Policy: `https://theclimbapp.org/privacy`
- Terms: `https://theclimbapp.org/terms`
- Support: `support@theclimbapp.org`

Before submission, verify the live pages match this implementation map and return successfully over HTTPS.
