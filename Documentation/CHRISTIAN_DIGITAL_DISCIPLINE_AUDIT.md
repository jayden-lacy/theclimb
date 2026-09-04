# Christian Digital Discipline Implementation Audit

Last reviewed: September 2, 2026

This audit maps the current production code to the Christian digital-discipline product brief. It treats source compilation and Simulator behavior as local evidence only. Family Controls, Managed Settings, Device Activity, Safari extension behavior, and notification delivery still require physical-device verification.

## 1. Current architecture

- SwiftUI app with a single `AppRootView` and five tab destinations: Focus, Word, Circle, Insights, and Me.
- `AppViewModel` coordinates the existing account snapshot, AI daily plan, missions, devotionals, habits, journal, progress, community, notifications, widgets, and authentication.
- `AppRepository` abstracts local/Firebase persistence. Existing Codable fields use backward-compatible defaults.
- Screen Time state is isolated from the Firebase snapshot in versioned App Group envelopes.
- `ScreenTimePolicyEngine` resolves overlapping protection policies.
- `FocusSessionEngine` and `FocusSessionRuntimeService` own immediate sessions, rhythms, boundaries, intentional breaks, early exits, and protected-time history.
- `AdultProtectionEngine` and `AdultProtectionRuntimeService` own permanent adult-site protection, strict disable delay, local domain rules, exceptions, and privacy-safe events.
- `ClimbControlRuntimeService` owns the device-local Daily Climb projection, idempotent Climb Time rewards, daily reset, owner isolation, and reconciliation of DeviceActivity threshold evidence.
- `DeviceActivityClimbTimeUsageMonitor` schedules bounded cumulative usage events for the user's selected apps, categories, and web domains. The monitor extension records monotonic evidence and applies a separate Climb Time shield when allowance is exhausted.
- Embedded extensions cover Device Activity monitoring/reporting, Managed Settings shields, Safari content blocking, widgets, and Live Activities.
- Firebase callable functions own AI generation, account deletion, scoring, leaderboard writes, and community/group mutations.

## 2. Existing features that already satisfy the brief

| Current component | Purpose | Decision | Dependencies | Migration risk |
| --- | --- | --- | --- | --- |
| Daily mission, reflection, recovery | Real-world action and honest follow-through | Keep | Firebase scoring, journal, notifications | Low |
| AI daily mission and devotional | Personalized daily plan | Keep and constrain | Firebase Functions, OpenAI, local fallback | Medium |
| Focus sessions | Immediate protected work/prayer/mission window | Modify into Climb Modes foundation | FamilyControls, ManagedSettings, DeviceActivity | Medium |
| Focus rhythms | Recurring protection windows | Keep and generalize | DeviceActivity monitor, App Group | Medium |
| App boundaries | Time-based limits for selected content | Keep and connect to Climb Time/Hard Stop | DeviceActivity | High |
| Adult protection | Apple automatic filter plus local domain rules | Keep as Content Shield | FamilyControls, Safari extension | High |
| Attention report | Authorized aggregate device usage | Keep | DeviceActivity report extension | High |
| Stewardship Score | Behavioral consistency without spiritual-worth claims | Keep; rename presentation to Momentum | Focus history, mission/reflection evidence | Medium |
| Word, prayer, habits, journal | Faith formation | Keep and deepen | Local/Firebase snapshot | Low |
| Community and accountability | Encouragement, groups, partners | Keep finite and consent-based | Firestore rules/functions | Medium |
| Widgets, Live Activity, App Intents | Low-friction glanceable actions | Keep and connect to new state | App Group, WidgetKit, ActivityKit | Medium |

## 3. Implemented in the current Climb Control slice

- Home now presents one derived Daily Climb with Scripture, mission, prayer, reflection, and screen-goal actions.
- Climb Time starts with a 30-minute base allowance, applies idempotent capped rewards, tracks cumulative eligible usage, and resets by calendar day.
- Usage monitoring uses privacy-preserving Family Activity selections and bounded cumulative DeviceActivity thresholds. It does not inspect app names or content.
- DeviceActivity evidence is owner- and day-scoped in the App Group, survives app termination, and is reconciled on relaunch without repeated writes.
- The Climb Time shield uses its own named Managed Settings store, so stopping it does not clear mission, rhythm, boundary, or permanent-protection policies.
- A hard upper limit is represented in the wallet and threshold plan. Existing reward caps keep the normal daily allowance below that upper limit.
- Home reports whether usage monitoring is active, needs permission, needs a selection, or is degraded instead of claiming protection unconditionally.

## 4. Features requiring modification

- OVR remains visible on Home and can be misread as spiritual worth; it needs a clear Momentum presentation and explanation.
- Focus purposes are not yet first-class named Climb Modes with shared schedules, exceptions, and exit policies.
- Adult-site protection and the session-only adult filter need one explicit user choice with truthful scope.
- Accountability does not yet support granular, opt-in protection events.

## 5. Missing features

- Active Bible reading verification and first-class Bible navigation/progress.
- Scripture Before Scroll enforcement. The domain model exists, but it is not yet wired into the policy coordinator.
- Built-in and custom Climb Modes beyond the current generic purpose presets.
- Doomscroll Guard state machine and cooldown behavior.
- I Need Help intervention flows.
- Mode analytics and digital-discipline reports grounded in authorized data.
- Bible games and their tightly capped reward architecture.

## 6. Required Apple capabilities

Present in source/targets:

- Family Controls on the app, Device Activity monitor, and Device Activity report targets.
- Managed Settings shield configuration/action extensions.
- App Groups for cross-process state.
- WidgetKit, ActivityKit, App Intents, and local notifications.
- Safari content blocker extension.

Still required outside source control:

- Distribution approval and profiles for every Family Controls target.
- Physical-device authorization, shielding, threshold, restart, and revocation evidence.
- Safari extension enablement and filtering evidence.
- A Network Extension entitlement and URL Filter target only if Apple approves a future system-wide Content Shield. The current build must not claim network-wide filtering.

## 7. Current technical blockers

1. Apple does not expose readable app identities from Family Activity tokens, so The Climb cannot silently identify or auto-select X/Reddit apps. The user must authorize and select those apps once.
2. Device Activity threshold delivery and report accuracy cannot be proven in Simulator.
3. No Network Extension target exists; system-wide website filtering cannot be claimed.
4. Existing policy stores must remain backward compatible for at least one production upgrade cycle.
5. The worktree includes an uncommitted AI/onboarding/purity-protection update and must not be destructively rewritten.

## 8. Proposed module architecture

```text
Domain/
  DailyClimb
  ClimbTimeWallet + RewardPolicy + HardStopPolicy
  ScriptureBeforeScroll
  ClimbMode + EffectiveRestrictionPolicy
  DoomscrollPolicy

Services/
  ClimbControlRuntimeService
  DailyResetService
  ActiveReadingService
  ClimbTimeUsageCoordinator
  ModeCoordinator
  DoomscrollGuardService

Existing adapters retained/
  ScreenTimePolicyCoordinator
  FocusSessionRuntimeService
  AdultProtectionRuntimeService
  DeviceActivity monitor/report extensions
```

Business rules remain outside SwiftUI. App Group envelopes are the local source of truth for controls that extensions must read. Firebase remains the source of truth for server-owned scoring/community operations.

## 9. Data migration risks

- Never rename or remove existing Firebase collections or Codable snapshot fields.
- Introduce Climb Control state in a new versioned App Group envelope with an owner user ID.
- Reset device-local Climb Control state when the authenticated owner changes or signs out.
- Preserve existing focus selections, active timers, rhythms, boundaries, permanent-protection rules, history, streaks, and OVR.
- Derive Daily Climb presentation from existing records before storing duplicate completion state.
- Use calendar day identifiers rather than 24-hour intervals so DST and time-zone changes do not double-award or skip a reset.

## 10. Testing gaps

- Physical-device matrix for authorization, selection, shielding, thresholds, reports, app termination, restart, DST, time-zone changes, and revocation.
- Scripture active-reading idle and progress verification tests.
- Physical-device Climb Time threshold delivery and Hard Stop shield evidence.
- Scripture Before Scroll extension enforcement tests.
- Mode precedence and overlapping schedule tests across every built-in mode.
- Doomscroll cooldown, intervention cap, and notification replacement tests.
- Dynamic Type, VoiceOver, Reduce Motion, and contrast testing on protection screens.

## 11. Exact implementation sequence

1. Add active Bible reading sessions and only then award capped Scripture-based Climb Time.
2. Enforce Scripture Before Scroll through the shared policy coordinator.
3. Physically verify selected-content usage callbacks and the Climb Time Hard Stop on a signed iPhone build.
4. Generalize current Focus purposes/rhythms into Climb Modes, starting with Study and Pomodoro.
5. Add School/Church schedules, then Brick/Sleep/Prayer/Present presets.
6. Add Doomscroll Guard using technically defensible prolonged-usage thresholds.
7. Replace remaining OVR presentation with Momentum language that cannot be misread as spiritual worth.
8. Add I Need Help, opt-in accountability summaries, Bible games, finite community improvements, and reports.
9. Run the complete physical-device and release verification matrix before changing App Store claims.
