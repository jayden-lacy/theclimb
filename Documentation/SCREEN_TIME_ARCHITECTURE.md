# Screen Time Architecture

## Design Goals

1. Preserve the current mission focus path.
2. Allow multiple independent restriction sources.
3. Never clear a restriction that another active source still requires.
4. Keep Apple framework code behind protocols.
5. Store only privacy-preserving tokens and aggregate outcomes.
6. Make displayed protection state match enforcement health.

## Layers

### Domain models

- `FocusSession`
- `FocusRhythm`
- `AppBoundary`
- `OpenBoundary`
- `ProtectionPolicy`
- `ProtectionSource`
- `ProtectionStrictness`
- `ProtectionHealth`
- `PolicyResolution`
- `ProtectedTimeRecord`

Models are Codable with versioned defaults. They do not import SwiftUI.

### Persistence

`ScreenTimePolicyStore` uses the existing App Group:

`group.com.jaydenlacy.theclimb`

Storage is separate from `AppStateSnapshot` because extensions must read enforcement data without loading the full Firebase snapshot.

Existing keys remain readable:

- activity selection v1
- adult web-content toggle v1
- active mission timer v1
- focus templates v1

New state uses one versioned policy envelope and a migration marker.

### Policy resolver

`ScreenTimePolicyResolving` accepts all active policies and returns one effective resolution.

Precedence:

1. Permanent adult protection
2. Guardian/accountability-locked protection
3. Locked sessions and boundaries
4. Intentional sessions and rhythms
5. Flexible sessions
6. Temporary exceptions

An exception may relax only the source that granted it. It cannot override a higher-priority permanent rule.

### Apple framework adapter

`ScreenTimeEnforcementService` owns Managed Settings stores and DeviceActivity schedules.

Use separate named stores by policy class:

- `TheClimbPermanentProtection`
- `TheClimbFocusSession`
- `TheClimbRhythms`
- `TheClimbBoundaries`

The resolver writes the complete effective state. Ending one source triggers re-resolution rather than a global `clearAllSettings()`.

### Authorization and health

`ScreenTimeAuthorizationProviding` reports Apple authorization.

`ProtectionHealthChecking` combines:

- Family Controls authorization
- App Group read/write health
- selected-token availability
- active DeviceActivity schedule state where observable
- extension heartbeat
- policy freshness
- optional Safari/network capability flags

Health states:

- fullyProtected
- partiallyProtected
- actionRequired
- off
- unavailable

### View model integration

`AppViewModel` receives a coordinator rather than directly orchestrating framework details. Existing mission methods remain behavior compatible while delegating policy activation and deactivation.

## Overlap Example

Active inputs:

- Permanent adult website protection
- School rhythm blocking social apps
- 25-minute prayer session blocking entertainment

When prayer ends:

- Prayer source is removed.
- Resolver runs again.
- Adult domains and school social-app restrictions remain.

No code path may call a global clear without immediately reapplying the resolved policy.

## Extension Contract

The DeviceActivity monitor reads only:

- policy source ID
- schedule ID
- end behavior
- effective policy snapshot
- extension heartbeat keys

The extension never reads Firebase credentials, profile journals, browsing history, or raw URLs.

## Testing Contract

Unit tests cover:

- precedence
- overlapping start/end
- permanent protection surviving breaks
- expired policies
- cross-midnight rhythms
- corrupted storage fallback
- migration from existing v1 keys
- health-state truthfulness
