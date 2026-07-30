# Data Migration Plan

## Principles

- Never reset the existing `AppStateSnapshot`.
- Never rename an existing Firebase collection in place.
- Add optional/defaulted Codable fields only.
- Keep Screen Time token data local in the App Group.
- Make every migration idempotent.
- Persist migration completion only after validation succeeds.

## Versioning

Introduce:

- `ScreenTimeSchemaVersion`
- `ScreenTimeMigrationState`
- `ScreenTimePolicyEnvelope`

The initial policy schema is version 1. The migration runner stores the last completed version in the App Group.

## Migration 0 to 1

Inputs:

- `the-climb.screen-time-selection.v1`
- `the-climb.screen-time-templates.v1`
- `the-climb.adult-web-content-filter.v1`
- active mission timer keys
- existing profile `appBlockingEnabled`

Actions:

1. Preserve existing `FamilyActivitySelection` data unchanged.
2. Preserve existing focus template blobs unchanged.
3. Convert the adult filter preference into a Standard Protection preference, not a claim of active permanent enforcement.
4. If a valid active mission timer exists, create a mission-session source policy.
5. Write the versioned policy envelope.
6. Validate decode and App Group readback.
7. Mark migration 1 complete.

Rollback:

- Keep all v1 source keys.
- If new-state decode fails, ignore the new envelope and continue using the current mission path.
- Never delete old keys during the first production migration.

## Existing User Upgrade

The upgrade presentation is controlled by a local version marker:

- existing profile plus migration not acknowledged: show short upgrade flow;
- no profile: continue full onboarding;
- denied Screen Time access: preserve faith app access and show setup later;
- completed upgrade: never repeat unless a materially new migration requires it.

## Firebase

Phase 1 adds no required Firebase collection.

Future cloud-synced aggregates may be added beneath:

`users/{uid}/attentionState/{document}`

Do not upload `FamilyActivitySelection` token blobs unless Apple documentation explicitly permits the intended use and cross-device behavior is validated.

## Migration Tests

- Decode a snapshot created before Screen Time infrastructure.
- Preserve all profile, mission, devotional, journal, habit, group, partner, and achievement values.
- Run migration twice with identical result.
- Recover from corrupted new policy data.
- Preserve active mission handoff.
- Preserve notification settings and streaks.
