# App Store Entitlement Checklist

Last reviewed: September 4, 2026

Use this checklist for the exact archive submitted to App Store Connect. A capability present in an `.entitlements` file is not proof that Apple approved it for distribution or that the provisioning profile contains it.

## Release State

| Item | Current status |
| --- | --- |
| Current branch | `main` |
| Release source | Current `main`; record the exact uploaded commit and archive when TestFlight processing completes |
| Screen Time upgrade | Included in release candidate `1.0 (17)` |
| Local simulator build | Debug and Release passed September 3, 2026 |
| Native tests | 50 of 50 passed September 3, 2026 |
| Release analyzer | Passed September 3, 2026 with no analyzer findings |
| Signed archive for current worktree | Development-signed `1.0 (17)` archive succeeded; deep code-sign verification passed |
| TestFlight build containing current worktree | Not uploaded |
| Apple portal entitlement status | Source entitlements are present; distribution-profile evidence remains required |
| Distribution provisioning profiles | App Store export reported no Apple account, no iOS Distribution certificate, and missing profiles for `contentblocker` and `deviceactivityreport` |

Do not submit the previously uploaded `1.0 (15)` as evidence for the current Screen Time upgrade or Safari content blocker. The next upload must be build `17` or later.

## Bundle and Target Inventory

| Target | Bundle identifier | App Group in source | Family Controls in source | Release action |
| --- | --- | --- | --- | --- |
| Main app | `com.jaydenlacy.theclimb` | Yes | Yes | Distribution profile present; install distribution certificate before export |
| Widget and Live Activity | `com.jaydenlacy.theclimb.widget` | Yes | No | Distribution profile present; install distribution certificate before export |
| Shield configuration | `com.jaydenlacy.theclimb.shieldconfiguration` | Yes | Yes | Family Controls distribution profile present |
| Shield action | `com.jaydenlacy.theclimb.shieldaction` | Yes | Yes | Family Controls distribution profile present |
| Device Activity monitor | `com.jaydenlacy.theclimb.deviceactivitymonitor` | Yes | Yes | Family Controls distribution profile present |
| Device Activity report | `com.jaydenlacy.theclimb.deviceactivityreport` | Yes | Yes | Development profile present; distribution profile still required |
| Safari content blocker | `com.jaydenlacy.theclimb.contentblocker` | Yes | No | Development profile present; distribution profile still required |

Shared App Group:

`group.com.jaydenlacy.theclimb`

The Device Activity report extension is embedded as an ExtensionKit extension and must be registered, provisioned, archived, and physically verified with the other Family Controls targets.

## Apple Developer Portal

### App IDs

- [x] Every bundle identifier above resolves through an explicit development provisioning profile under team `BLH227B4U7`.
- [x] The main app, widget, shield extensions, monitor, report, and Safari extension use the same intended team in the archive.
- [x] The App Group is enabled in the signed entitlements for every shipping target.
- [x] No obsolete bundle identifier is embedded in the archive.

### Family Controls

- [x] A distribution profile containing Family Controls exists for the main app.
- [x] A distribution profile containing Family Controls exists for the shield configuration extension.
- [x] A distribution profile containing Family Controls exists for the shield action extension.
- [x] A distribution profile containing Family Controls exists for the Device Activity monitor extension.
- [ ] Apple has approved Family Controls for distribution for the Device Activity report extension.
- [ ] Each distribution provisioning profile contains `com.apple.developer.family-controls`.
- [x] The entitlement request and review notes describe voluntary, user-controlled focus and adult-site protection.
- [x] Review copy does not claim remote parental surveillance, universal app-open counting, or bypass-proof control.

The widget and Safari content blocker do not declare Family Controls in source and should not be given that entitlement without a documented technical need.

### Other Capabilities

- [x] Sign in with Apple is present in the signed main-app entitlements.
- [x] Associated Domains is present in the signed main-app entitlements with `applinks:theclimbapp.org`.
- [x] App Group access is present in all seven signed shipping bundles.
- [x] Live Activities are supported by the main app Info.plist and widget target.
- [x] No Network Extension target or capability is embedded or represented in review notes.
- [x] No APNs entitlement is embedded; the current notification implementation uses local notifications.
- [x] No StoreKit, in-app purchase, subscription, or paywall capability is configured in source.

## Provisioning and Signing

- [ ] Xcode automatic signing or manually selected profiles resolve for every shipping target.
- [ ] Release uses team `BLH227B4U7`.
- [ ] The archive is signed for distribution, not development.
- [ ] The embedded profiles contain the intended bundle IDs and capabilities.
- [ ] The App Group value is identical across the app and all participating extensions.
- [x] The archive contains the widget, shield configuration, shield action, Device Activity monitor, Device Activity report, and Safari content blocker.
- [x] The archive contains no watchOS app or Network Extension.
- [x] `codesign --verify --deep --strict` succeeds on the development-signed archived app.
- [x] First-party app and extension dSYM UUIDs match every archived executable.
- [ ] Organizer validation succeeds without entitlement mismatch errors.

## Privacy Manifests

Privacy manifests are present in source for:

- the main app;
- widget;
- shield configuration;
- Device Activity monitor;
- Device Activity report; and
- Safari content blocker.

The Shield Action target does not currently use App Group `UserDefaults` or another required-reason API. Before submission:

- [x] Reconfirm the Shield Action implementation has not gained required-reason API use.
- [x] Confirm each manifest is included in the built target resource bundle.
- [x] Confirm third-party SDK privacy manifests are present in the archive.
- [ ] Resolve any Organizer privacy-manifest warning before submission.

## App Store Connect Configuration

- [ ] Select an iPhone-only build; the project currently targets device family `1`.
- [ ] Use only current iPhone screenshots that match the submitted binary.
- [ ] Privacy Policy URL is `https://theclimbapp.org/privacy`.
- [ ] Terms URL is `https://theclimbapp.org/terms`.
- [ ] Support URL is a live HTTPS page on `theclimbapp.org`.
- [ ] Support email is `support@theclimbapp.org`.
- [ ] App Privacy answers match `PRIVACY_DISCLOSURE.md` and the archived SDK set.
- [ ] Age Rating answers match `AGE_RATING_REVIEW.md`.
- [ ] App Review notes match `APP_REVIEW_NOTES.md`.
- [ ] Content rights cover all bundled fonts, iconography, scripture text, and domain-rule data.
- [ ] Export-compliance answers reflect the exact binary.

The app does not implement a proprietary encryption algorithm or a custom standard cryptographic algorithm in app code. It uses Apple platform security and encrypted network connections through system and provider SDKs. Confirm the current App Store Connect export-compliance questions against the archived binary; do not reuse a stale answer blindly.

## Free Product Confirmation

- [x] No StoreKit framework use exists in app source.
- [x] No `.storekit` configuration is shipped.
- [ ] No in-app purchase products exist for this app in App Store Connect.
- [ ] No subscription group is configured.
- [ ] No feature is presented as paid, premium, trial-only, or purchase-gated.
- [ ] App metadata states the product is free without promising that third-party connectivity has no external cost.

No separate subscription checklist is required for this release.

## Final Evidence Package

Attach or retain internally:

- [ ] App ID capability screenshots or exports.
- [ ] Distribution profile entitlement dumps for all shipping targets.
- [x] Signed archive validation log.
- [x] Archive target and bundle inventory.
- [x] Three current 1284 x 2778 iPhone screenshots.
- [ ] Physical-device test matrix with device model, OS version, build number, tester, date, and evidence.
- [ ] TestFlight smoke-test result.
- [ ] Final App Store Connect metadata review.

## Approval

| Role | Name | Date | Result |
| --- | --- | --- | --- |
| Engineering |  |  | Pending |
| Product |  |  | Pending |
| Privacy/legal |  |  | Pending |
| Release owner |  |  | Pending |
