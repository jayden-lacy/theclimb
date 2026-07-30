# Physical-Device Test Matrix

Last reviewed: July 30, 2026

All physical-device cases below are `Not run` unless explicitly changed with dated evidence. Simulator builds and unit tests do not satisfy these cases.

## Status Values

- `Not run`: no acceptable physical-device evidence.
- `Pass`: expected result observed on the named release build and device.
- `Fail`: behavior differs from the expected result.
- `Blocked`: required implementation, entitlement, account, environment, or backend is missing.
- `N/A`: intentionally unavailable in the submitted build.

## Required Test Context

Record for every run:

| Field | Value |
| --- | --- |
| App version/build | `1.0 (16)` |
| Commit |  |
| Distribution source | Development / Ad Hoc / TestFlight |
| Device model |  |
| iOS version |  |
| Apple ID type | Personal / child-family test account |
| Time zone |  |
| Tester |  |
| Date |  |

Minimum coverage:

1. One clean install on the minimum supported iOS version, if available.
2. One current iOS device.
3. One upgrade from the last public/TestFlight build with real existing data.
4. One release-signed TestFlight build with production App Check.

## Screen Time Authorization and Selection

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| ST-01 | First authorization approval | System prompt appears once; app reports authorized only after approval | Not run |  |
| ST-02 | Cancel or deny authorization | Faith features remain usable; protection is not shown active | Not run |  |
| ST-03 | Re-request after denial | App gives accurate Settings/retry guidance | Not run |  |
| ST-04 | Revoke authorization in Settings | Health becomes action required/unavailable; app does not claim enforcement | Not run |  |
| ST-05 | Reauthorize after revocation | Local policy intent reconciles without duplicate schedules | Not run |  |
| ST-06 | Select individual apps | Opaque selection saves and shields only selected apps during active policy | Not run |  |
| ST-07 | Select categories | Selected categories shield during active policy | Not run |  |
| ST-08 | Select web domains | Selected domain tokens shield during active policy | Not run |  |
| ST-09 | Edit saved selection | New selection replaces prior intended selection without stale blocks | Not run |  |
| ST-10 | App Group access failure simulation | Health reports action required; no false active state | Not run |  |

## Immediate Focus and Shielding

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| FS-01 | Start short Flexible session | Session begins, selected restrictions apply, end time is correct | Not run |  |
| FS-02 | Start Intentional session | Restrictions apply; early exit asks for a reason and honors delay | Not run |  |
| FS-03 | Start Locked session | Restrictions apply; normal early exit is unavailable until end | Not run |  |
| FS-04 | Custom duration | Session end matches configured duration | Not run |  |
| FS-05 | End-at time | Session uses selected local end time | Not run |  |
| FS-06 | Custom purpose | Custom label persists without changing enforcement | Not run |  |
| FS-07 | Custom app shield | Shield title, subtitle, icon, and remaining-time copy render correctly | Not run |  |
| FS-08 | Category shield | Category shield renders and blocks expected category | Not run |  |
| FS-09 | Domain shield | Domain shield renders without exposing unrelated browsing data | Not run |  |
| FS-10 | Natural session expiry | Session ends, history records once, session policy clears | Not run |  |
| FS-11 | App terminated during session | Apple enforcement remains for scheduled interval; app reconciles on return | Not run |  |
| FS-12 | Device locked during session | Session and Live Activity remain coherent | Not run |  |
| FS-13 | Device restart during session | Protection intent and health recover truthfully; no indefinite orphan block | Not run |  |
| FS-14 | Overlap with mission focus | Ending one source does not remove the other active source | Not run |  |
| FS-15 | Essential Apps mode | Reviewed essential apps remain available; other selected scope is restricted | Not run |  |
| FS-16 | Emergency/recovery access | Phone/emergency and necessary recovery paths remain available | Not run |  |

## Intentional Breaks and Exit

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| BR-01 | Start valid break | Session restriction relaxes only for permitted source and duration | Not run |  |
| BR-02 | Resume break early | Session restriction reapplies promptly | Not run |  |
| BR-03 | Break expires | Session restriction reapplies automatically | Not run |  |
| BR-04 | Break near session end | Invalid duration is rejected; break cannot outlive session | Not run |  |
| BR-05 | Break during Permanent Protection | Adult-protection policy remains active | Not run |  |
| BR-06 | End focus during Permanent Protection | Permanent Protection remains active | Not run |  |
| BR-07 | Intentional early-exit delay | Reason and elapsed delay persist across background/foreground | Not run |  |
| BR-08 | Locked early exit | Runtime refuses normal early exit | Not run |  |

## Focus Rhythms

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| RH-01 | Same-day rhythm start | Restrictions start during configured window | Not run |  |
| RH-02 | Same-day rhythm end | Rhythm restriction ends without clearing higher-priority policies | Not run |  |
| RH-03 | Cross-midnight start/end | Previous scheduled day is evaluated correctly | Not run |  |
| RH-04 | Overlapping rhythms | Effective restrictions resolve without premature clear | Not run |  |
| RH-05 | Edit future rhythm | Old schedule is removed and replacement activates once | Not run |  |
| RH-06 | Delete rhythm | Schedule and rhythm-specific policy are removed | Not run |  |
| RH-07 | App terminated | Schedule still activates through Device Activity | Not run |  |
| RH-08 | Device restart | Intended rhythm resumes or health reports action required | Not run |  |
| RH-09 | Time-zone change | Schedule recalculates predictably in local time | Not run |  |
| RH-10 | Daylight-saving transition | No duplicated or missing indefinite restriction | Not run |  |
| RH-11 | Rhythm Pause/travel mode | New rhythm schedules remain paused until the chosen date while permanent protection and boundaries stay active | Not run |  |

## App Boundaries

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| BD-01 | Daily threshold | Restriction begins when selected usage reaches allowance | Not run |  |
| BD-02 | Weekly threshold | Restriction begins when weekly allowance is reached | Not run |  |
| BD-03 | Active weekdays | Inactive days do not schedule the boundary | Not run |  |
| BD-04 | Five-minute warning | Local warning is delivered at the configured native warning point | Not run |  |
| BD-05 | Reset | Restriction ends at the configured reset without clearing unrelated policies | Not run |  |
| BD-06 | Edit active boundary | Old events and stores do not remain orphaned | Not run |  |
| BD-07 | Delete boundary | Schedule, events, and boundary store clear | Not run |  |
| BD-08 | Overlap with session | Ending session does not remove reached boundary | Not run |  |
| BD-09 | Overlap with Permanent Protection | Boundary reset does not remove permanent adult protection | Not run |  |
| BD-10 | Exact app-open count | Feature is intentionally unavailable | N/A | Production feature flag is off |
| BD-11 | Independent device-usage report | Today/7D/4W/3M views render authorized aggregate activity without exposing app identities | Not run |  |

## Permanent Protection and Adult-Site Coverage

Use approved test fixtures. Do not store explicit browsing history or attach unredacted sensitive domains to general tickets.

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| PP-01 | Enable Standard mode | Separate permanent policy activates and health reflects actual layers | Not run |  |
| PP-02 | Disable Standard mode | Permanent source clears without removing session/rhythm/boundary sources | Not run |  |
| PP-03 | Enable Strict mode | Permanent source activates and disable delay is recorded | Not run |  |
| PP-04 | Strict early disable attempt | Turn-off is rejected before 24 hours | Not run |  |
| PP-05 | Strict eligible disable | Turn-off succeeds only after full delay | Not run |  |
| PP-06 | Apple automatic adult classification | Approved known-adult test fixture is blocked in supported scope | Not run |  |
| PP-07 | Safe site under automatic filter | Approved safe fixture remains available | Not run |  |
| PP-08 | User-added blocked domain | Exact domain and intended subdomains are blocked | Not run |  |
| PP-09 | Remove user-added domain | User rule is removed without changing unrelated protection | Not run |  |
| PP-10 | User-facing false-positive allow flow | Normalized domain review creates the selected time-limited exception and refreshes enforcement | Not run |  |
| PP-11 | Offline local rules | Last saved local rules remain available without network dependency | Not run |  |
| PP-12 | Permission revoked | Health reports action required and no false full-protection state | Not run |  |
| PP-13 | Device restart | Permanent policy intent and health recover truthfully | Not run |  |
| PP-14 | Signed remote update accepted | No production update channel/verifier is connected | Blocked | Validation model only |
| PP-15 | Invalid signed update rejected | No production update channel/verifier is connected | Blocked | Validation model only |
| PP-16 | Network-level filter | No Network Extension exists | N/A | Feature flag off |
| PP-17 | Accountability approval/PIN | No production secure approval path exists | N/A | Feature flag off |
| PP-18 | Guardian enforcement | No production guardian flow exists | N/A | Feature flag off |

## Safari Content Blocker

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| SF-01 | Extension appears in Settings | The Climb Safari Protection is present for release build | Not run |  |
| SF-02 | Extension disabled | App reports Safari disabled/partial rather than fully protected | Not run |  |
| SF-03 | Enable extension | App status refresh reports enabled | Not run |  |
| SF-04 | Explicit block rule | Approved test domain is blocked in Safari | Not run |  |
| SF-05 | Subdomain rule | Intended subdomain scope is enforced | Not run |  |
| SF-06 | Explicit allow precedence | Approved safe exception wins over matching parent block | Not run |  |
| SF-07 | Reload rules | Updated local rules take effect without reinstall | Not run |  |
| SF-08 | Invalid local domain | Rule is rejected or omitted without extension failure | Not run |  |
| SF-09 | Other browser | App accurately makes no Safari-extension coverage claim | Not run |  |
| SF-10 | Extension process restart | Rules are regenerated from App Group state | Not run |  |

## Faith Feature Integration

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| FI-01 | Start protected mission | Mission and Focus state agree; selected restrictions apply | Not run |  |
| FI-02 | Complete protected mission | Actual protected interval records once; OVR uses backend mission result | Not run |  |
| FI-03 | Fail protected mission | Failure records correctly and focus policy clears/reconciles | Not run |  |
| FI-04 | Start protected devotional | Focus Session starts from Word and returns to readable devotional flow | Not run |  |
| FI-05 | Start protected prayer | Prayer timer and Focus Session remain coherent | Not run |  |
| FI-06 | Start protected habit | Focus Session starts without falsely completing the habit | Not run |  |
| FI-07 | Stewardship Score | Score changes only from eligible evidence and does not overwrite OVR | Not run |  |
| FI-08 | Weekly Stewardship Review | Weekly pulse, score evidence, and 7-day Screen Time report use only verified local data | Not run | Combined narrative review remains partial |
| FI-09 | Attention Assist delivery | Opt-in frequency and quiet hours persist; only evidence-backed rhythm/protection notifications schedule without duplicates or quiet-hour violations | Not run |  |

## Migration and Data Preservation

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| MG-01 | Upgrade existing signed-in account | Short upgrade flow appears instead of full re-onboarding | Not run |  |
| MG-02 | Existing profile answers | Age, goals, struggle, and preferences remain | Not run |  |
| MG-03 | Existing streak and OVR | Values and history remain unchanged by migration | Not run |  |
| MG-04 | Existing mission/devotional/journal | Records remain and decode | Not run |  |
| MG-05 | Existing habits and achievements | Completion history and unlocks remain | Not run |  |
| MG-06 | Existing groups and partners | Membership and links remain | Not run |  |
| MG-07 | Existing notifications | Reminder preferences remain | Not run |  |
| MG-08 | Existing app-blocking selection | Legacy selection remains usable | Not run |  |
| MG-09 | Existing active mission timer | Valid timer handoff migrates without duplicate record | Not run |  |
| MG-10 | Deny upgrade permission | User retains all nonblocking app access | Not run |  |
| MG-11 | Defer upgrade | Flow resumes from saved state after defer period | Not run |  |
| MG-12 | Reinstall/sign in | Cloud data restores; local Screen Time selection is requested again if not portable | Not run |  |
| MG-13 | Previous/new version interoperability | Shared cloud schema is not corrupted | Not run |  |
| MG-14 | Existing subscription | No subscription exists | N/A | Free product; no IAP |

## Authentication, Backend, and Account

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| AC-01 | Email/password first sign-in | Account and profile load | Not run |  |
| AC-02 | Google first/returning sign-in | Provider flow returns and data loads | Not run |  |
| AC-03 | Apple first/returning sign-in | Provider flow returns and data loads | Not run |  |
| AC-04 | Sign out | Local signed-in state clears and next user cannot see prior user's data | Not run |  |
| AC-05 | Email account deletion | Reauthentication, backend cleanup, auth deletion, and local clear succeed | Not run |  |
| AC-06 | Google account deletion | Provider reauthentication/disconnect and cleanup succeed | Not run |  |
| AC-07 | Apple account deletion | Reauthentication/token revocation and cleanup succeed | Not run |  |
| AC-08 | Leaderboard cleanup | Deleted account no longer appears after backend refresh | Not run |  |
| AC-09 | Community cleanup | Deleted account ownership/membership data follows deletion policy | Not run |  |
| AC-10 | Production App Check | Release-signed device can call protected backend; invalid token is rejected | Not run |  |
| AC-11 | AI cached/fallback plan | Daily flow succeeds under normal, cached, timeout, and fallback paths | Not run |  |
| AC-12 | Offline launch and pending sync | Cached state loads without cross-user leakage or data loss | Not run |  |

## Community Safety

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| CM-01 | Create post | Authenticated backend accepts valid content | Not run |  |
| CM-02 | Filter unsafe/profane content | Invalid content is rejected with actionable copy | Not run |  |
| CM-03 | Report post | Report is accepted once and reflected locally | Not run |  |
| CM-04 | Block user | Blocked user's content is hidden for requester | Not run |  |
| CM-05 | Delete own post | Author can delete; other user cannot | Not run |  |
| CM-06 | Create/join/leave group | Backend ownership and membership rules hold | Not run |  |
| CM-07 | Admin promotion/removal | Only authorized admins can change roles/membership | Not run |  |
| CM-08 | Delete group | Authorized deletion succeeds and members lose stale access | Not run |  |
| CM-09 | Partner invite/check-in | Code/link flow and activity sync work | Not run |  |
| CM-10 | Support path | Mail composer or chosen mail app opens for support | Not run |  |

## Notifications, Widgets, and Live Activities

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| NW-01 | Notification allow/deny | App status and scheduling match user choice | Not run |  |
| NW-02 | Daily mission reminder | Local notification arrives at configured time | Not run |  |
| NW-03 | Incomplete/recovery reminder | Correct notification arrives once without spam | Not run |  |
| NW-04 | Boundary warning | Device Activity extension posts expected local warning | Not run |  |
| NW-05 | Small/medium/large widget | Text fits and current App Group data appears | Not run |  |
| NW-06 | Widget after mission update | Timeline refreshes within system-controlled behavior | Not run |  |
| NW-07 | Live Activity start/update/end | Lock Screen/Dynamic Island state matches active timer | Not run |  |
| NW-08 | Reboot with Live Activity | No stale indefinite activity or false enforcement state | Not run |  |

## Accessibility and Quality

| ID | Test | Expected result | Status | Evidence |
| --- | --- | --- | --- | --- |
| QA-01 | VoiceOver | Logical order, labels, values, and actions across all new screens | Not run |  |
| QA-02 | Accessibility Dynamic Type | No clipped controls at supported accessibility sizes | Not run |  |
| QA-03 | Reduce Motion | Purposeful transitions reduce or stop without lost context | Not run |  |
| QA-04 | Increase Contrast | Boundaries and status remain legible | Not run |  |
| QA-05 | Color-independent status | Health and success/failure use text/icon, not color alone | Not run |  |
| QA-06 | Touch targets | Interactive targets meet at least 44 by 44 points | Not run |  |
| QA-07 | Light mode | Product currently prefers dark presentation; no unreadable system sheet or picker | Not run |  |
| QA-08 | Battery/background | No excessive drain across 24-hour rhythms and boundaries | Not run |  |
| QA-09 | Extension memory | Monitor, shield, and Safari extensions remain within system limits | Not run |  |
| QA-10 | Poor network | Focus enforcement remains local; cloud errors do not dead-end core flow | Not run |  |
| QA-11 | Free product | No paywall, purchase prompt, subscription restore, or StoreKit request appears | Not run |  |

## Sign-Off

Release requires:

- zero open Critical or High failures;
- all Family Controls, focus, boundary, permanent-protection, Safari, migration, authentication, deletion, and App Check release cases applicable to the submitted binary to pass;
- documented disposition for Medium and Low failures;
- App Review notes updated with the exact tested build; and
- product, engineering, privacy/legal, and release-owner approval.

| Role | Name | Date | Result |
| --- | --- | --- | --- |
| Engineering |  |  | Pending |
| QA |  |  | Pending |
| Product |  |  | Pending |
| Privacy/legal |  |  | Pending |
| Release owner |  |  | Pending |
