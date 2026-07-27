# The Climb Widget Ecosystem 2.0

This is the product and engineering direction for The Climb's system surfaces: Home Screen widgets, Lock Screen widgets, StandBy, Live Activities, Dynamic Island, Smart Stack, Siri, Shortcuts, and App Intents.

The goal is not to show more data. The goal is to make the next faithful action obvious in under one second.

## Product Thesis

The Climb should behave like a quiet spiritual coach that lives across the user's day. It should not nag, gamify shame, or become another feed. Every surface should answer one of four questions:

1. What is my next faithful step?
2. Am I protecting focus right now?
3. Is my streak safe today?
4. Who is waiting on me?

## Design Principles

- Glance first: a user should understand the state before reading full text.
- One action per surface: start, continue, pray, check in, reflect, or open.
- Less green, more meaning: green means action or protected momentum, not decoration.
- Christian without clutter: scripture and prayer should feel calm, not poster-like.
- System-native: follow WidgetKit, ActivityKit, App Intents, Lock Screen, StandBy, and Dynamic Island constraints.
- Battery quiet: timeline refreshes are sparse; Live Activities only run during active missions/prayer.
- Accessible by default: short labels, high contrast, large enough hit targets, Dynamic Type bounds, and no meaning conveyed by color alone.

## Full Day Journey

### Morning

- Smart Stack surfaces "Morning Word" or "Begin Mission" based on whether the devotional has been read.
- Medium widget shows scripture, mission duration, and streak risk.
- Siri suggestion: "Start today's mission in The Climb."

### Midday

- If no mission is active, widgets pivot to "protect the streak" messaging.
- If a focus mission is active, Live Activity and Dynamic Island own the lock screen.

### Evening

- If mission is complete but reflection is missing, Lock Screen accessory becomes "Reflect."
- If nothing is complete, widget shifts to recovery language instead of guilt.
- StandBy shows "streak safe" or "one recovery step left."

### Night

- Large widget becomes a quiet review: Word, mission result, prayer minutes, shared partner streak.
- Smart Stack relevance drops after completion unless reflection is pending.

## Concept Matrix

The following 40 concepts are intentionally not variations of one widget. They cover different moments, devices, and behaviors.

| # | Concept | Surface | Purpose | Appears When | Why Users Keep It | Flow | Implementation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Next Faithful Step | Small Home | Show the one thing to do now | Daily mission pending | Replaces decision fatigue | Tap opens mission | Static widget + deep link |
| 2 | Mission Command | Medium Home | Mission, duration, streak, OVR | All day | The best default widget | Tap mission/progress zones | Static widget with Link regions |
| 3 | Daily Word Window | Medium Home | Scripture + reflection prompt | Morning/devotional unread | Gives spiritual value without opening app | Tap opens devotional | Static widget |
| 4 | Streak Shield | Small Home | Streak risk state | Afternoon/evening incomplete | Protects streak in one glance | Tap opens mission | Timeline relevance |
| 5 | Prayer Start | Small Home | Start 2-minute prayer | No active prayer | Zero-friction prayer | Button starts timer | Interactive widget App Intent |
| 6 | Prayer Timer | Small Home | Show active prayer countdown | Prayer active | Keeps user anchored | Button finishes timer | App Intent + timeline refresh |
| 7 | Habit Tile | Small Home | Complete next habit | Habit incomplete | One-tap progress | Button marks complete | Interactive widget App Intent |
| 8 | Partner Waiting | Small Home | Show accountability pressure | Partner has checked in | Emotional but not manipulative | Tap opens partner check-in | Deep link |
| 9 | OVR Momentum | Small Home | Score plus trend | Daily | Quick progress pride | Tap opens progress | Static widget |
| 10 | Recovery Step | Small Home | Offer fallback after missed mission | Mission failed/overdue | Prevents dropout | Tap opens recovery | Deep link |
| 11 | Focus Lock | Lock Screen Rect | Active blocking/timer | Focus mission active | Confirms apps are blocked | Tap opens active mission | Live Activity preferred |
| 12 | One-Line Word | Lock Screen Inline | Verse reference + short phrase | Morning | Fits Lock Screen | Tap opens Word | Accessory inline |
| 13 | Streak Ring | Lock Screen Circular | Progress to streak goal | Daily | Simple status at lock glance | Tap opens progress | Accessory circular |
| 14 | Reflect Now | Lock Screen Rect | Reflection required | Mission complete, no reflection | Keeps loop complete | Tap opens reflection | Accessory rectangular |
| 15 | Partner Pulse | Lock Screen Rect | Partner shared streak | Accountability active | Keeps relationship visible | Tap opens partner | Accessory rectangular |
| 16 | StandBy Mission | StandBy Small | Big mission timer/status | iPhone charging sideways | Useful desk mode | Tap opens mission | System small optimized |
| 17 | StandBy Word | StandBy Small | Calm scripture card | Morning/night StandBy | Spiritual glance without phone use | Tap opens devotional | System small optimized |
| 18 | StandBy Streak Safe | StandBy Small | Big "safe/not safe" state | Evening | Replaces anxious checking | Tap opens app | Timeline relevance |
| 19 | Focus Live Activity | Lock Screen + Island | Active mission timer | Mission started | Essential during blocking | End by app, tap opens app | ActivityKit |
| 20 | Prayer Live Activity | Lock Screen + Island | Active prayer session | Prayer timer started | Keeps prayer focused | Finish in app/intent | ActivityKit future pass |
| 21 | Scripture Live Activity | Island | Reading session progress | Devotional reader open | Turns reading into a calm session | Tap returns to reader | ActivityKit future pass |
| 22 | Reflection Live Activity | Island | Reflection pending | Mission completed | Prevents loop abandonment | Tap opens reflection | ActivityKit future pass |
| 23 | Streak Save Island | Island | Urgent streak protection | Late day incomplete | Timely without notification spam | Tap opens recovery | ActivityKit/notification-triggered |
| 24 | Completion Celebration | Island end state | Reward completion | Mission complete | Feels satisfying | Auto-dismisses | Activity end state |
| 25 | Shared Streak | Medium Home | You + partner streak | Partner connected | Makes accountability real | Tap opens partner | Static widget |
| 26 | Group Momentum | Medium Home | Group completion pulse | Joined group | Community without feed noise | Tap opens group | Static widget |
| 27 | Leaderboard Snapshot | Medium Home | Global/local rank | User opts in | Competitive users keep it | Tap opens leaderboard | Static widget |
| 28 | Weekly Path | Large Home | Seven-day rhythm | Sunday/Monday | Makes growth tangible | Tap opens progress | Static widget |
| 29 | Discipline Board | Large Home | Mission, habits, prayer, partner | Daily | The premium dashboard | Multiple Link zones/buttons | Static + interactive |
| 30 | Devotional Reader Widget | Large Home | Verse + question + action | Morning | A mini reading surface | Tap opens full reader | Static widget |
| 31 | Progress Story | Large Home | OVR, streak, completion, weakness | Weekly report ready | Analytics feels human | Tap opens report | Static widget |
| 32 | Recovery Coach | Large Home | Failure reason + next mission | User failed yesterday | Reduces shame, increases return | Tap opens recovery | Static widget |
| 33 | Extra-Large Command Center | Extra Large | Full day plan | iPad/large widget surfaces | One glance replaces app opening | Tap zones | System extraLarge |
| 34 | Extra-Large Weekly Review | Extra Large | Week path + Word archive | Weekly | Spiritual/productivity recap | Tap report | System extraLarge |
| 35 | Lock Screen Streak Halo | Lock Screen Accessory | Streak ring and safe/risk state | Always | One-glance momentum | Tap progress | Accessory circular |
| 36 | StandBy Focus Timer | StandBy | Active focus countdown and protection state | Mission active | Useful across the room | Tap mission | Live Activity timer |
| 37 | Lock Screen Word Inline | Lock Screen Accessory | Short verse reference | Morning | Low-friction scripture | Tap reader | Accessory inline |
| 38 | Partner Check-In Accessory | Lock Screen Accessory | Partner waiting state | Partner waiting | Human accountability | Tap check-in | Accessory rectangular |
| 39 | Siri Start Mission | Siri/Shortcut | Begin today's mission | Suggested after reminder | Hands-free start | Voice starts/open app | App Intent |
| 40 | Siri Quick Prayer | Siri/Shortcut | Start 2-minute prayer | Suggested during stress windows | Real spiritual utility | Voice starts timer | App Intent |

## Dynamic Island Redesign

### Minimal

```
[mountain/lock glyph]
```

- Use only when another Live Activity is also active or the island collapses fully.
- Symbol communicates focus/protection.
- Green keyline only if blocking is active.

### Compact

```
left:  lock.shield / timer
right: 12:04
```

- Left shows protection state.
- Right is a monospaced countdown.
- No mission title; compact space is for state, not reading.

### Expanded

```
THE CLIMB        12:04
Apps blocked     remaining

No phone after waking
[progress line]
Protected focus · Level 4
```

- Leading: brand + protection label.
- Trailing: live timer.
- Bottom: mission title, progress, and one quiet cue.
- No large buttons unless the action can safely complete from an intent.

### End State

```
Mission complete
Reflection is next
```

- Ends quickly.
- Opens reflection if tapped.
- Completion animation should be subtle: green keyline and timer collapse, not confetti.

### Multiple Activities

- The Climb should only run one Live Activity at a time for missions.
- Prayer Live Activity should not start during a focus mission; it should become a widget/App Intent state instead.
- If iOS shows another app's Live Activity, The Climb minimal state must still be meaningful.

## Timeline Strategy

- Static widgets refresh every 20 minutes, immediately on app writes through `WidgetCenter.shared.reloadAllTimelines()`, and at mission/prayer end.
- Smart Stack relevance should be high for mission pending, active focus, reflection pending, partner waiting, and streak-at-risk states.
- Low relevance after streak is safe and reflection is complete.
- Avoid minute-by-minute widget timelines. Use Live Activity timer styles for active sessions.

## Architecture

- App Group snapshot remains the primary widget data source.
- `AppViewModel` owns mission state and writes the snapshot.
- Widget App Intents perform only small local mutations, then reload timelines.
- ActivityKit state is limited to active-session data: mission id, title, start/end dates, focus label, and blocking state.
- Siri/App Shortcuts should expose three first actions: start mission, open Daily Word, and start prayer.

## Critique Filter

Rejected ideas:

- Verse-of-the-day carousel: too generic and not personalized.
- Leaderboard-first widgets: wrong emotional center for this app.
- Confetti-heavy streak animations: feels childish and manipulative.
- Mini-feed widgets: makes community feel like social media.
- Always-on AI chat widget: too slow, costly, and not glanceable.
- Red warning widgets: shame-based and visually harsh.

## Implementation Phases

### Phase 1

- Redesign current small, medium, large, accessory, and Live Activity surfaces.
- Add system extra-large support where available.
- Improve text fitting and reduce widget clutter.
- Add richer Dynamic Island and Lock Screen Live Activity state.

### Phase 2

- Add app-target App Shortcuts for start mission, Daily Word, prayer, and reflection.
- Add Smart Stack relevance scoring.
- Add configurable widget modes using App Intent configuration.

### Phase 3

- Add prayer/reflection Live Activities.
- Add Control Center focus and prayer controls.
- Add real widget previews and screenshot automation for App Store media.
