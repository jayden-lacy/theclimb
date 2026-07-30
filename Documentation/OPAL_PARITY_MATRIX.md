# Screen Time Capability Parity Matrix

Last reviewed: July 30, 2026

This matrix compares product capability, not marketing language or visual similarity. The Climb is not expected to reproduce proprietary Opal behavior, and it must remain honest about Apple API limits.

## Status Definitions

- `Implemented locally`: source is present and local compilation or deterministic tests pass.
- `Device verification required`: implementation is present, but Apple framework behavior has not been proven on a physical iPhone with distribution entitlements.
- `Partial`: only part of the user-visible or enforcement path exists.
- `Planned`: no complete current implementation.
- `Unavailable`: intentionally disabled or absent because the required API, entitlement, infrastructure, or product decision is missing.

| Reference capability | The Climb equivalent | Status | Current evidence and limits |
| --- | --- | --- | --- |
| Immediate focus timer | Focus Session | Device verification required | General-purpose session model, setup UI, active state, Device Activity schedule, protected-time history, and early-exit rules compile; shielding is not physically verified |
| Recurring sessions | Focus Rhythms | Device verification required | Rhythm model, editor, persistence, scheduling, cross-midnight evaluation, and extension callbacks exist; schedule delivery, restart recovery, time-zone, and DST behavior remain unverified |
| Selected app blocking | Distraction Blocking | Device verification required | FamilyActivityPicker, opaque token storage, Managed Settings shielding, and custom shield targets exist |
| Selected category blocking | Category Blocking | Device verification required | Category selection and shielding exist in source |
| Selected website blocking | Website Protection | Device verification required | Managed Settings web-domain tokens and Apple automatic filtering are requested during active policies |
| Allow-list mode | Essential Apps | Device verification required | Essential Apps selection and `.all(except:)` category enforcement exist; emergency and essential-app safety require real-device review |
| Daily app limits | App Boundaries | Device verification required | Daily cadence, reset time, active weekdays, Device Activity thresholds, and warnings exist |
| Weekly app limits | Weekly Boundaries | Device verification required | Weekly cadence and week-start configuration exist; user flow and OS threshold behavior require device validation |
| Different weekday/weekend limits | Multiple Boundaries | Partial | Separate active-day boundaries can model this, but there is no dedicated paired weekday/weekend editor |
| Usage-based limits | Time Boundaries | Device verification required | DeviceActivity threshold events are created from selected tokens, and a separate report extension renders authorized on-device aggregates |
| App-open limits | Open Boundaries | Unavailable | Production feature flag is off; public APIs do not provide reliable universal exact app-open counts |
| Strict focus mode | Locked Focus | Device verification required | Locked sessions reject early exit in the domain/runtime and unit tests; system bypass limits still apply |
| Temporary breaks | Intentional Breaks | Device verification required | Flexible and intentional sessions support bounded breaks and automatic session-policy reapplication; permanent protection remains higher priority |
| Early-exit friction | Commitment Exit Flow | Implemented locally | Flexible exit, reason-plus-delay intentional exit, and locked rejection have deterministic unit coverage |
| Focus score | Stewardship Score | Implemented locally | Uses recorded protected time, mission outcomes, and reflections; remains separate from OVR and is not presented as spiritual worth |
| Screen-time reports | Attention Reports | Device verification required | Embedded Device Activity Report extension renders authorized aggregate duration, pickups, selected duration, daily trend, and distracting hour for Today/7D/4W/3M without exposing app identities |
| Weekly reports | Weekly Stewardship Review | Partial | Weekly pulse, stewardship factor detail, and 7-day device report are visible; a single combined narrative review is not complete |
| Streaks | Faithfulness Streak | Implemented locally | Existing mission streak, recovery, persistence, and backend scoring remain |
| Focus hours | Protected Time | Implemented locally | Session and protected-mission records support duration, purpose, outcome, breaks, and aggregates |
| Automated reminders | Attention Assist | Partial | Settings, quiet hours, App Group persistence, launch reconciliation, and local scheduling are integrated for upcoming-rhythm and protection-health evidence; no dedicated runtime test or physical notification evidence exists, and device-usage signals are not connected |
| Custom block screens | The Climb Shield | Device verification required | Shield configuration and action extensions compile with app, category, domain, and remaining-time copy |
| Widgets | The Climb Widgets | Partial | Existing widget and Live Activity targets remain; current worktree behavior still needs physical-device and TestFlight validation |
| Siri Shortcuts | The Climb Shortcuts | Implemented locally | Existing app intents remain in the project; no new Screen Time shortcut set was verified in this audit |
| Schedule vacation mode | Rhythm Pause | Implemented locally | Users can pause rhythms for 1, 3, or 7 days with rest, schedule-change, travel, or vacation reasons; permanent protection and boundaries remain active |
| PIN protection | Accountability Lock | Unavailable | Production feature flag is off; no secure credential, backend approval challenge, replay protection, or rate-limited enforcement path is connected |
| Parental controls | Guardian Mode | Unavailable | Production feature flag is off pending supported Apple guardian authorization and legal/product approval |
| Adult-content blocking | Permanent Protection | Device verification required | Standard/Strict configuration, separate permanent policy, Apple automatic filter request, delay model, local domain rules, and health state exist; coverage is not device-wide |
| False-positive recovery | Website Allow Review | Device verification required | User-facing review normalizes a domain and grants a local 1, 7, or 30-day exception; Safari and Managed Settings behavior remains unverified on device |
| Signed rule updates | Trusted Rule Envelope | Partial | Validation structures and failure states exist; no production verifier key or remote update distribution channel is connected |
| Safari content blocking | Safari Protection | Device verification required | A Safari content-blocker target, App Group rules, status query, and reload flow compile; the user must enable it and Safari-only behavior is unverified on device |
| Network-level filtering | Advanced Protection | Unavailable | No Network Extension target or entitlement exists; the feature flag is off |
| Cross-device Screen Time configuration | Local Protection State | Unavailable | Faith data syncs through Firebase, but Apple Screen Time selection tokens remain local and are not treated as portable |
| Protected devotional/prayer/habit | Faithful Focus Launches | Device verification required | Source integration starts general Focus Sessions from Word, prayer, and habit surfaces; enforcement is unverified |
| Existing-user migration | Screen Time Upgrade | Implemented locally | Resumable, idempotent upgrade state and preservation tests exist; production upgrade from an installed prior build remains unverified |

## Current Build Evidence

- Generic iOS Simulator build passed on July 30, 2026.
- All 33 native unit tests passed on July 30, 2026.
- Release analysis passed with no analyzer findings.
- A development-signed `1.0 (16)` archive passed deep code-sign verification and contains all six intended extensions.
- The previously uploaded `1.0 (15)` build does not represent this Screen Time release candidate.
- No physical-device enforcement evidence was produced during this audit.
- App Store distribution export is blocked pending Apple-account access, an iOS Distribution certificate, and profiles for the Safari content blocker and Device Activity report.

## Completion Standard

A capability may be labeled complete for release only when:

1. Persistence survives app termination and device restart.
2. Authorization denial, revocation, and reauthorization are handled.
3. Overlapping policy start, end, break, and expiry behavior is correct.
4. Displayed protection health matches actual enforcement state.
5. Unit and migration tests pass.
6. A signed release candidate passes the applicable physical-device matrix.
7. App Review notes and customer-facing copy state the capability's real scope.
