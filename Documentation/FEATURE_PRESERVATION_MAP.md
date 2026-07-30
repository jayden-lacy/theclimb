# Feature Preservation Map

No existing Firebase collection will be renamed. Existing Codable fields remain decodable, and new fields must use defaults.

| Existing feature | Decision | Destination | Compatibility requirement |
| --- | --- | --- | --- |
| Daily mission | Preserved and redesigned | Focus/Home | Existing mission IDs, status, history, and AI payload remain valid |
| AI daily plan | Preserved unchanged internally | Daily plan service | Auth, App Check, cache, rate limit, and fallback behavior remain |
| Devotional and Scripture | Preserved and redesigned | Word and Home | Existing devotionals and WEB verse text remain readable |
| Mission timer | Merged into Focus Session | Focus | Existing active mission timer handoff must migrate without losing state |
| Mission completion/failure/recovery | Preserved unchanged | Mission flow | Backend-owned scoring remains authoritative |
| OVR | Preserved | Insights | Stewardship Score is separate and must not redefine spiritual worth |
| Faithfulness streak | Preserved | Home and Insights | Migration must never reset streak history |
| Quick reflection and journal | Preserved and expanded | Mission/Insights | Existing reflection IDs and history remain |
| Habits | Preserved and integrated | Word/Home | Existing completion dates remain |
| Guided prayer | Preserved and integrated | Word/Focus | Prayer can start a protected session |
| Verse memory | Preserved unchanged | Word | Existing review schedule remains |
| Achievements/badges | Preserved and expanded | Insights | Existing unlocks remain |
| Monthly reflection letters | Preserved unchanged | Insights | Existing letters remain |
| Growth challenges | Data preserved, UI deferred | Future Word experience | Decode old challenge data; do not silently delete it |
| Groups | Preserved and expanded | Circle | Backend administration and membership remain authoritative |
| Accountability partners | Preserved and expanded | Circle/Protection | Existing partner links remain valid; protection sharing is opt-in |
| Encouragement feed | Preserved unchanged | Circle | Moderation and block behavior remain |
| Leaderboard | Preserved unchanged | Circle/Insights | Scores remain server-owned |
| Profile answers | Preserved | Me | Existing users get an upgrade flow, not full re-onboarding |
| Notification time/preferences | Preserved | Me | Existing notification identifiers and schedules remain |
| Screen Time selection | Preserved and migrated | Focus policy store | Existing `FamilyActivitySelection` remains usable |
| Focus templates | Rebuilt with backward-compatible data | Focus Rhythms presets | Existing template blobs remain decodable |
| Adult web filter toggle | Rebuilt with explicit scope | Permanent Protection | Existing value seeds Standard Protection; no false device-wide claim |
| Widgets and Live Activity | Preserved and expanded | Widget extension | Existing App Group keys remain readable |
| Siri/App Intents | Preserved and expanded | App Intents | Existing shortcuts remain valid |
| Sign in/sign out/delete | Preserved unchanged | Onboarding/Me | No auth provider or deletion regression |
| Legal/support | Preserved unchanged | Me and website | Public URLs and support email remain |

## Navigation Preservation

The current five-tab structure remains familiar:

- Focus becomes the main attention dashboard.
- Word retains faith content and habits.
- Circle retains community and accountability.
- Insights combines OVR, achievements, faith history, and future attention reports.
- Me retains profile, settings, privacy, and protection setup.

New focus capabilities should use nested navigation inside Focus rather than removing Word or Circle.

## Existing User Upgrade Rule

An existing signed-in user with a valid profile:

1. Keeps the existing profile and snapshot.
2. Receives a versioned, dismissible attention-protection upgrade flow.
3. Is not asked to recreate faith goals, struggle, streak goal, notification time, habits, groups, or partners.
4. Does not lose access if Screen Time authorization is denied.
5. Sees accurate capability status instead of fabricated usage data.
