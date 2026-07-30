# Existing App Audit

Last audited: July 29, 2026

## Repository

- Product: The Climb
- Bundle ID: `com.jaydenlacy.theclimb`
- Minimum iOS version: 17.0
- Primary architecture: SwiftUI with one `AppViewModel`, service protocols, and repository-backed state
- Local persistence: Codable `AppStateSnapshot` stored in App Group `UserDefaults`
- Cloud persistence: Firebase Authentication, Firestore, Cloud Functions, App Check, and Crashlytics
- AI: authenticated Firebase Function using OpenAI Structured Outputs with caching, rate limits, retries, and local fallback
- Monetization: none. No StoreKit target, paywall, subscription model, or entitlement matrix exists.

## Shipped Targets

| Target | Purpose | App Group | Family Controls |
| --- | --- | --- | --- |
| The Climb | Main iPhone app | Yes | Yes |
| The ClimbWidget | Home/Lock Screen widgets and Live Activity | Yes | No |
| The ClimbShieldConfiguration | Custom app, category, and website shield | Yes | Yes |
| The ClimbShieldAction | Shield button handling | Yes | Yes |
| TheClimbDeviceActivityMonitor | Ends mission monitoring and clears mission shield | Yes | Yes |
| TheClimbTests | Native unit tests | No | No |

Not present:

- Device Activity Report extension
- Safari Content Blocker or Safari Web Extension
- Network Extension
- StoreKit configuration
- watchOS target

## Navigation and Routes

The current five tabs are:

1. Focus (`HomeView`)
2. Word (`GrowView`)
3. Circle (`CommunityView`)
4. Insights (`ProgressDashboardView`)
5. Me (`ProfileView`)

Deep links support:

- `theclimb://open?tab=...`
- `https://theclimbapp.org/open?tab=...`
- Partner invite links
- Group invite links

Major modal or nested destinations:

- Mission session and reflection
- Full devotional reader
- Habit detail and verse-memory flows
- Partner detail, invite, and check-in flows
- Group list, create, detail, administration, and membership flows
- Global leaderboard
- Legal documents
- Account deletion and support
- Screen Time activity picker

## Existing Feature Inventory

### Faith and behavior

- Personalized daily mission and devotional
- World English Bible verse text
- AI generation plus deterministic offline fallback
- Mission timer and Live Activity
- Completion, failure, recovery, reflection, and automatic expiration
- OVR progression with increasing difficulty
- Mission streaks and recovery streaks
- Habits with daily completion history and streak calculations
- Prayer sessions, verse memory, monthly reflection letters, and achievements
- Notification fatigue controls

### Screen Time

- Individual Family Controls authorization
- Privacy-preserving app, category, and web-domain selection
- Reusable local focus templates
- Managed Settings app/category/domain shielding during a mission
- Apple automatic adult web-content filtering during a protected mission
- Device Activity monitor for a one-time mission interval
- Custom shield configuration with remaining-time copy
- Mission Live Activity and timer-ended notification
- App Group handoff between app and extensions

### Community

- Encouragement feed
- Reporting, blocking, filtering, and own-post deletion
- Groups with backend-enforced create, join, leave, edit, admin promotion, member removal, and deletion
- Accountability partner invites and check-ins
- Global leaderboard with server-owned score writes

### Account and release

- Email/password, Google, and Apple authentication
- Sign out and account deletion
- Backend account-data cleanup
- Privacy policy, terms, support email, and public website
- App Check, Crashlytics logs, Firestore rules, Functions rate limits, and security validation

## Data Models

The shared snapshot contains:

- `UserProfile`
- `Mission`
- `Devotional`
- `ReflectionEntry`
- `ProgressSnapshot`
- `GrowthHabit`
- `GrowthChallenge`
- `ClimbGroup`
- `EncouragementPost`
- `AccountabilityPartner`
- `LeaderboardEntry`
- blocked user IDs
- moderation reports
- AI content feedback
- notification-fatigue state
- monthly reflection letters
- memorized verses
- achievement unlocks

Screen Time selections and active timer handoff are currently stored separately in App Group `UserDefaults`.

## Firebase Collections

Client-owned or user-scoped:

- `users`
- `users/{uid}/state`
- `missions`
- `devotionals`
- `journalEntries`
- `progress`
- `partnerLinks`
- `reports`

Backend-owned:

- `posts`
- `groups`
- `leaderboards`
- `userScores`
- `missionScoreEvents`
- `aiDailyPlans`
- `aiUsage`

## Cloud Functions

- Daily plan generation
- Account-data deletion
- Mission completion, failure, and recovery scoring
- Leaderboard synchronization
- Community post creation, Amen, and deletion
- Group creation, membership, editing, administration, member removal, and deletion

## Notifications

- Daily mission reminder
- Incomplete mission reminder
- Mission timer completion
- Recovery prompt

Existing notification identifiers and schedules must remain backward compatible.

## Analytics

The app records a small event taxonomy through Crashlytics log messages. It does not use Firebase Analytics. Events include app launch, mission states, permission requests, content feedback, community actions, habits, profile updates, sign out, onboarding restart, and account deletion.

Sensitive URL, domain, and adult-protection details must never be added to this logging path.

## Current Risks

1. The mission focus service owns one Managed Settings store and calls `clearAllSettings()`. It cannot safely preserve overlapping permanent, rhythm, or boundary restrictions.
2. Adult filtering is active only while mission focus is active, despite some UI copy suggesting broader protection.
3. No policy resolver, schedule model, migration version, or protection health model exists.
4. No Device Activity Report extension exists, so real usage reports are not available.
5. No Safari or network filtering target exists. Device-wide adult-content claims would be inaccurate.
6. The simulator Apple-login fallback contains a fixed test password in app source. It must be removed or isolated from production compilation.
7. Screen Time authorization handling does not yet model App Group, extension, stale-state, or enforcement health.
8. No secure accountability credential store exists.
9. Existing `GrowthChallenge` data remains decodable, but the current product UI intentionally does not foreground challenges.
