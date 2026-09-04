import Foundation
#if canImport(DeviceActivity) && canImport(FamilyControls) && os(iOS)
import DeviceActivity
import FamilyControls
import ManagedSettings
#endif

enum ClimbTimeMonitoringState: String, Equatable {
    case unavailable
    case permissionRequired
    case selectionRequired
    case scheduled
    case degraded
}

protocol ClimbTimeUsageMonitoring {
    func synchronize(
        ownerUserID: String,
        wallet: ClimbTimeWallet
    ) -> ClimbTimeMonitoringState
    func stopAndClear()
}

#if canImport(DeviceActivity) && canImport(FamilyControls) && os(iOS)
final class DeviceActivityClimbTimeUsageMonitor: ClimbTimeUsageMonitoring {
    private let center: DeviceActivityCenter
    private let sharedStore: AppGroupClimbTimeMonitorStore
    private let thresholdPlan: ClimbTimeThresholdPlan
    private let now: () -> Date

    private var activityName: DeviceActivityName {
        DeviceActivityName(ClimbTimeMonitorShared.activityName)
    }

    private var managedStore: ManagedSettingsStore {
        ManagedSettingsStore(
            named: ManagedSettingsStore.Name(
                ClimbTimeMonitorShared.managedStoreName
            )
        )
    }

    init(
        center: DeviceActivityCenter = DeviceActivityCenter(),
        sharedStore: AppGroupClimbTimeMonitorStore = AppGroupClimbTimeMonitorStore(),
        thresholdPlan: ClimbTimeThresholdPlan = ClimbTimeThresholdPlan(),
        now: @escaping () -> Date = Date.init
    ) {
        self.center = center
        self.sharedStore = sharedStore
        self.thresholdPlan = thresholdPlan
        self.now = now
    }

    func synchronize(
        ownerUserID: String,
        wallet: ClimbTimeWallet
    ) -> ClimbTimeMonitoringState {
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            stopMonitoringAndClearShield()
            return .permissionRequired
        }

        let selection = ScreenTimeActivitySelectionStore.loadSelection()
        guard selection.hasShieldableContent else {
            stopMonitoringAndClearShield()
            return .selectionRequired
        }

        let date = now()
        let hardStop = min(
            max(wallet.hardStopSeconds, wallet.baseAllowanceSeconds),
            ClimbTimeMonitorConfiguration.maximumDailySeconds
        )
        let configuration = ClimbTimeMonitorConfiguration(
            ownerUserID: ownerUserID,
            dayKey: wallet.dayKey,
            baseAllowanceSeconds: wallet.baseAllowanceSeconds,
            allowanceSeconds: min(
                wallet.baseAllowanceSeconds + wallet.earnedSeconds,
                hardStop
            ),
            hardStopSeconds: hardStop,
            updatedAt: date
        )

        do {
            try sharedStore.saveConfiguration(configuration)
            let events = makeEvents(
                selection: selection,
                configuration: configuration
            )
            guard !events.isEmpty else {
                stopMonitoringAndClearShield()
                return .degraded
            }

            center.stopMonitoring([activityName])
            try center.startMonitoring(
                activityName,
                during: dailySchedule,
                events: events
            )
            applyCurrentShieldState(
                selection: selection,
                wallet: wallet
            )
            return .scheduled
        } catch {
            stopMonitoringAndClearShield()
            return .degraded
        }
    }

    func stopAndClear() {
        stopMonitoringAndClearShield()
        try? sharedStore.clear()
    }

    private var dailySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
    }

    private func makeEvents(
        selection: FamilyActivitySelection,
        configuration: ClimbTimeMonitorConfiguration
    ) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let thresholds = thresholdPlan.thresholds(
            allowanceSeconds: configuration.allowanceSeconds,
            hardStopSeconds: configuration.hardStopSeconds
        )
        return Dictionary(uniqueKeysWithValues: thresholds.map { threshold in
            let rawName = ClimbTimeMonitorShared.eventName(for: threshold)
            let eventName = DeviceActivityEvent.Name(rawName)
            let components = DateComponents(second: threshold)
            let event: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                event = DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: components,
                    includesPastActivity: true
                )
            } else {
                event = DeviceActivityEvent(
                    applications: selection.applicationTokens,
                    categories: selection.categoryTokens,
                    webDomains: selection.webDomainTokens,
                    threshold: components
                )
            }
            return (eventName, event)
        })
    }

    private func applyCurrentShieldState(
        selection: FamilyActivitySelection,
        wallet: ClimbTimeWallet
    ) {
        guard wallet.availableSeconds <= 0 || wallet.isHardStopReached else {
            managedStore.clearAllSettings()
            return
        }
        applyShield(selection)
    }

    private func applyShield(_ selection: FamilyActivitySelection) {
        managedStore.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        managedStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        managedStore.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }

    private func stopMonitoringAndClearShield() {
        center.stopMonitoring([activityName])
        managedStore.clearAllSettings()
    }
}
#else
final class DeviceActivityClimbTimeUsageMonitor: ClimbTimeUsageMonitoring {
    func synchronize(
        ownerUserID: String,
        wallet: ClimbTimeWallet
    ) -> ClimbTimeMonitoringState {
        .unavailable
    }

    func stopAndClear() {}
}
#endif
