# Support and Troubleshooting

Last reviewed: July 29, 2026

Support contact: `support@theclimbapp.org`

This guide distinguishes normal Apple platform limits from defects. Never ask a user to send browsing history, explicit search terms, raw Screen Time tokens, passwords, authentication codes, or unrelated screenshots.

## First Response Checklist

Ask for:

- app version and build number;
- iPhone model;
- iOS version;
- whether the app came from TestFlight or the App Store;
- feature affected;
- approximate time of failure;
- Screen Time authorization state shown in The Climb;
- whether the issue remains after reopening The Climb; and
- a screenshot limited to The Climb's own status screen, with personal content redacted.

Do not ask for the identity of every selected app or blocked website unless the user voluntarily identifies an approved test fixture and it is essential to reproduce the issue.

## Screen Time Access

### Permission was denied

1. The user can continue using faith, mission, journal, community, and progress features.
2. Open The Climb's Focus area and retry authorization.
3. If iOS does not present the prompt again, open Settings and review The Climb's Screen Time/Family Controls permission.
4. Reopen The Climb and check the protection-health state.

If permission remains denied, do not tell the user blocking is active.

### Permission was revoked

Expected behavior:

- protection health changes to an action-required or unavailable state;
- active Apple restrictions may stop;
- local policy intent remains so the app can reconcile after reauthorization.

Ask the user to reauthorize, reopen The Climb, and restart the intended session or schedule. Escalate if the app still reports fully protected after revocation.

### App picker is empty or will not save

- Confirm Screen Time authorization is granted.
- Reopen the picker from Focus.
- Select at least one app, category, or domain.
- Save and return to the Focus setup.
- Reopen The Climb if the opaque selection does not appear to persist.

The Climb cannot display a readable installed-app inventory outside Apple's picker.

## Focus Sessions

### Selected apps are not blocked

1. Confirm the test is on a physical iPhone; simulator results are not valid.
2. Confirm Screen Time authorization is granted.
3. Confirm a distraction selection was saved.
4. Confirm the session shows as active and has not ended.
5. Confirm the tested app was included in the saved selection.
6. Reopen The Climb to trigger runtime reconciliation.
7. End the session, start a new short session, and retest.

Escalate with app build, iOS version, policy type, start/end time, and whether the custom shield appeared. Do not collect raw token data.

### Session ended but apps remain blocked

1. Reopen The Climb so expired sessions reconcile.
2. Check whether a Focus Rhythm, App Boundary, or Permanent Protection policy is also active.
3. End or edit only the policy responsible for the restriction.
4. Revoke Screen Time permission only as a last user-controlled recovery step.

An ordinary session ending must not remove a higher-priority Permanent Protection rule.

### Early exit is unavailable

- Flexible sessions may end early.
- Intentional sessions require a reason and a brief delay.
- Locked sessions are designed to remain until their scheduled end.

The user can still revoke Apple permission, change system settings, or uninstall the app. Never describe a locked session as impossible to bypass.

### Intentional break does not start or end

- Breaks are limited to eligible session strictness and must end before the session itself.
- Reopen The Climb and check the active-session state.
- Use Resume if the break is still shown.
- Confirm Permanent Protection remains active; a normal focus break must not disable it.

## Focus Rhythms

### A rhythm did not start

- Confirm the rhythm is enabled.
- Confirm the selected day, local start/end time, and current time zone.
- Confirm Screen Time authorization is still granted.
- Confirm a valid app/category/domain selection exists.
- Reopen The Climb to reconcile schedules.

iOS manages background schedule delivery and may not execute at an exact second. Escalate repeated misses with timestamps and time-zone information.

### Cross-midnight or travel issue

The source model supports cross-midnight rhythms and a time-limited Rhythm Pause for travel or vacation, but physical time-zone and daylight-saving behavior is not release-verified. Record the original time zone, destination time zone, schedule, pause end, and observed start/end times.

## App Boundaries

### Warning or limit did not trigger

- Confirm the boundary is enabled.
- Confirm its active days, reset time, allowance, and selected apps/categories.
- Confirm Screen Time permission remains granted.
- Reopen The Climb after changing a boundary.

Device Activity thresholds are system-managed. The app does not provide exact universal app-open counts. Its independent Device Activity report shows authorized aggregate usage on device and may remain empty until Screen Time access is granted and iOS supplies report data.

## Permanent Protection

### Protection status is not fully protected

Read the health reason shown in The Climb:

- authorization required: grant or restore Screen Time access;
- missing selection: choose the relevant apps/categories/domains;
- stale policy or heartbeat: reopen The Climb and retry;
- Safari disabled: enable the Safari extension if Safari coverage is desired;
- unavailable network layer: expected, because no Network Extension exists.

Do not report device-wide coverage. Screen Time, selected domains, and Safari each have different scope.

### Turn off Standard mode

Use the explicit turn-off control in Focus. Standard mode is intended to turn off without the Strict waiting period.

### Turn off Strict mode

Start the turn-off request and wait until the 24-hour delay completes. Reopening or restarting the app should not shorten the required delay. If the request disappears or executes early, capture timestamps and escalate as a release-blocking defect.

### A safe website is blocked

The current product does not yet expose a complete false-positive allow/review flow. The user may remove a domain they manually added. For Apple automatic classification issues, explain that classification is provided by Apple and avoid promising an immediate app-level exception.

Escalate with a privacy-safe domain classification description. Do not place explicit URLs in Crashlytics, analytics, community posts, or partner messages.

## Safari Protection

### Safari extension is disabled

Open Settings, locate Safari's Extensions settings, and enable **The Climb Safari Protection**. Settings paths can vary by iOS version. Return to The Climb and refresh Safari status.

### Rules do not reload

- Confirm the extension is enabled.
- Return to The Climb and use the Safari status reload action.
- Remove and re-add the approved test rule.
- Force-quit Safari and retry the approved test fixture.
- Reopen The Climb.

Safari Protection does not filter Chrome, other browsers, encrypted in-app feeds, or device network traffic.

## Widgets and Live Activities

### Widget is blank or stale

- Open The Climb once after install or update.
- Sign in and allow the Home data to finish loading.
- Remove and re-add the widget.
- Complete a mission or refresh data in app.
- Wait for iOS to refresh the timeline.

Widget refresh timing is controlled by iOS. A widget is not an enforcement authority.

### Live Activity does not appear

- Confirm Live Activities are allowed for The Climb in Settings.
- Start a timed mission or supported focus flow.
- Lock the phone and check the Lock Screen.
- Confirm the session has not already ended.

## Notifications

- Confirm notification permission in Settings.
- Confirm the reminder time and notification toggles in The Climb.
- Reopen The Climb after changing settings.
- Check Focus modes and notification summaries that may delay presentation.

The current app uses local notifications, not remote push notifications.

## Daily Plan and AI

### Daily mission or devotional is delayed

- Check network connectivity.
- Reopen the app.
- Allow the cached or deterministic fallback plan to load.
- Avoid repeatedly requesting regeneration.

Escalate with the request time, build number, account user ID only if policy allows, and the user-facing error. Never request the OpenAI key or expose raw prompts in support.

### Content is inappropriate or repetitive

Use the in-app feedback/report path where available and contact support. Record the generated plan ID or date, not additional sensitive journal text. Treat unsafe content as a moderation incident.

## Account, Sync, and Community

### Changes could not sync

- Confirm connectivity.
- Keep the app open briefly and retry.
- Sign out only after local work is no longer pending.
- Do not delete and reinstall as the first troubleshooting step.

### Sign-in failure

- Confirm the selected provider.
- Retry on a stable network.
- For Apple or Google, verify the provider flow completes and returns to The Climb.
- For email/password, use the correct email format and password.

Never ask for a password or provider authorization code.

### Account deletion fails

- Confirm a stable network.
- Reauthenticate when prompted.
- Retry once.
- Contact support if recent-login or backend cleanup continues to fail.

Support must track the deletion request without asking the user to share credentials.

### Community safety issue

Use in-app report and block controls first. For threats, exploitation, self-harm risk, or illegal content, follow the internal safety escalation process and preserve only necessary evidence.

## Escalation Record

| Field | Value |
| --- | --- |
| Ticket ID |  |
| App version/build |  |
| Device/iOS |  |
| Feature/policy type |  |
| Authorization state |  |
| Time zone |  |
| Reproduction steps |  |
| Expected result |  |
| Actual result |  |
| Privacy-safe evidence |  |
| Severity/owner |  |
