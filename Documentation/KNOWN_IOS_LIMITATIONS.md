# Known iOS Limitations

These limitations must be reflected in product copy and App Review notes.

## User control

- On a personally managed iPhone, the user can uninstall the app, revoke authorization, or change system settings.
- The Climb may add friction and accountability but cannot honestly claim to be impossible to bypass.
- Stronger guardian behavior depends on Apple's supported family/child authorization model.

## Screen Time visibility

- Family Controls exposes privacy-preserving tokens, not a readable inventory of installed apps.
- App usage reports require a Device Activity Report extension and user authorization.
- Screen Time data should be processed locally where possible.

## App opens

- Public Screen Time APIs do not provide an exact, universal open count for every third-party app.
- DeviceActivity events can approximate some threshold behavior but must not be labeled as exact when they are not.

## Climb Time accounting

- Climb Time usage is inferred from cumulative DeviceActivity threshold callbacks for the user's authorized selection. It is a monotonic lower-bound estimate, not a continuously readable second-by-second counter.
- Threshold delivery is system-managed. The UI may update after the next checkpoint or app foreground reconciliation rather than instantly.
- The Climb does not use the newer direct Device Activity data-fetch API as a general solution because availability and entitlement constraints do not cover ordinary worldwide consumer distribution.
- If authorization, selection, App Group access, or scheduling is unavailable, the app must report that state and must not claim Climb Time enforcement is active.

## Websites

- Managed Settings can shield selected web domains and apply Apple's automatic web-content filtering.
- A Safari content blocker protects Safari content covered by its declarative rules, not every browser.
- HTTPS encryption prevents content-level inspection inside many apps and feeds.
- For high-risk encrypted feeds, the reliable choice is to block the entire selected app.

## Network filtering

- Device-wide DNS, VPN, or content filtering requires Network Extension capabilities and App Review approval.
- The current project has no Network Extension entitlement or target.
- Until approved and physically verified, the product must not claim device-wide network protection.

## Schedules and restarts

- DeviceActivity scheduling is managed by the operating system and can be delayed or invalidated by authorization changes.
- The app must restore policy intent after launch and use extension heartbeats, but cannot guarantee instant background execution.
- Time-zone and daylight-saving changes require schedule recalculation.

## Essential apps

- The app cannot safely infer every emergency, medical, school, transportation, or authentication app.
- Strict allow-list sessions require explicit user review and clear warnings.
- Phone and emergency functionality must not be represented as blockable by The Climb.

## Live Activities and widgets

- Timeline and Live Activity refresh timing is system-controlled.
- They are status surfaces, not enforcement authorities.

## Simulator

- Family Controls, DeviceActivity, shields, App Check, notifications, and extension lifecycle behavior require physical-device verification.
- Simulator timer-only fallbacks must never be treated as evidence of production blocking.
