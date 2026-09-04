import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications

private enum MissionFocusMonitorConstants {
    static let activityName = DeviceActivityName("the-climb.mission-focus")
    static let managedStoreName = ManagedSettingsStore.Name("TheClimbMissionFocus")
    static let generalFocusActivityName = DeviceActivityName("the-climb.focus-session")
    static let generalFocusStoreName = ManagedSettingsStore.Name("TheClimbFocusSession")
    static let rhythmActivityPrefix = "the-climb.rhythm."
    static let rhythmStorePrefix = "TheClimbRhythm."
    static let boundaryActivityPrefix = "the-climb.boundary."
    static let boundaryStorePrefix = "TheClimbBoundary."
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let selectionKey = "the-climb.screen-time-selection.v1"
    static let essentialSelectionKey = "the-climb.essential-apps-selection.v1"
    static let activityConfigurationPrefix = "the-climb.scheduled-activity."
    static let adultContentKey = "the-climb.adult-web-content-filter.v1"
    static let purityProtectionEnabledKey = "the-climb.purity-protection.enabled.v1"
    static let purityProtectionDomainsKey = "the-climb.purity-protection.domains.v1"
    static let heartbeatKey = "the-climb.screen-time.enforcement-heartbeat.v1"
    static let missionIDKey = "the-climb.active-focus.mission-id.v1"
    static let titleKey = "the-climb.active-focus.title.v1"
    static let startedAtKey = "the-climb.active-focus.started-at.v1"
    static let endsAtKey = "the-climb.active-focus.ends-at.v1"
    static let durationMinutesKey = "the-climb.active-focus.duration-minutes.v1"
    static let monitorEndedMissionIDKey = "the-climb.active-focus.monitor-ended-mission-id.v1"
    static let monitorEndedAtKey = "the-climb.active-focus.monitor-ended-at.v1"
    static let monitorEndedReasonKey = "the-climb.active-focus.monitor-ended-reason.v1"
}

private enum ExtensionFocusSelectionMode: String, Codable {
    case blockSelected
    case allowEssentialApps
}

private struct ExtensionScheduledActivityConfiguration: Codable {
    var activityName: String
    var selectionMode: ExtensionFocusSelectionMode
    var blocksAdultWebContent: Bool
    var updatedAt: Date
}

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        if activity.rawValue == ClimbTimeMonitorShared.activityName {
            reconcileClimbTimeShield(for: activity)
            recordHeartbeat()
            return
        }

        if activity == MissionFocusMonitorConstants.generalFocusActivityName {
            applySavedProtection(
                for: activity,
                to: ManagedSettingsStore(
                    named: MissionFocusMonitorConstants.generalFocusStoreName
                )
            )
            recordHeartbeat()
            return
        }

        if let boundaryID = boundaryID(for: activity) {
            ManagedSettingsStore(
                named: ManagedSettingsStore.Name(
                    MissionFocusMonitorConstants.boundaryStorePrefix + boundaryID
                )
            ).clearAllSettings()
            recordHeartbeat()
            return
        }

        guard let rhythmID = rhythmID(for: activity) else { return }
        applySavedProtection(
            for: activity,
            to: ManagedSettingsStore(
                named: ManagedSettingsStore.Name(
                    MissionFocusMonitorConstants.rhythmStorePrefix + rhythmID
                )
            )
        )
        recordHeartbeat()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        if activity.rawValue == ClimbTimeMonitorShared.activityName {
            ManagedSettingsStore(
                named: ManagedSettingsStore.Name(
                    ClimbTimeMonitorShared.managedStoreName
                )
            ).clearAllSettings()
            recordHeartbeat()
            return
        }

        if activity == MissionFocusMonitorConstants.activityName {
            recordMissionEndHandoff(reason: "interval-ended")
            clearMissionShield()
            DeviceActivityCenter().stopMonitoring([activity])
            recordHeartbeat()
            return
        }

        if activity == MissionFocusMonitorConstants.generalFocusActivityName {
            ManagedSettingsStore(
                named: MissionFocusMonitorConstants.generalFocusStoreName
            ).clearAllSettings()
            DeviceActivityCenter().stopMonitoring([activity])
            recordHeartbeat()
            return
        }

        if let boundaryID = boundaryID(for: activity) {
            ManagedSettingsStore(
                named: ManagedSettingsStore.Name(
                    MissionFocusMonitorConstants.boundaryStorePrefix + boundaryID
                )
            ).clearAllSettings()
            recordHeartbeat()
            return
        }

        guard let rhythmID = rhythmID(for: activity) else { return }
        ManagedSettingsStore(
            named: ManagedSettingsStore.Name(
                MissionFocusMonitorConstants.rhythmStorePrefix + rhythmID
            )
        ).clearAllSettings()
        recordHeartbeat()
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        recordHeartbeat()
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        recordHeartbeat()
    }

    override func eventWillReachThresholdWarning(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        if boundaryID(for: activity) != nil {
            postNotification(
                id: "boundary-warning-\(activity.rawValue)",
                title: "Boundary almost reached",
                body: "Choose your next step before selected distractions become unavailable."
            )
        }
        recordHeartbeat()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        if activity.rawValue == ClimbTimeMonitorShared.activityName {
            handleClimbTimeThreshold(event, activity: activity)
            recordHeartbeat()
            return
        }

        if let boundaryID = boundaryID(for: activity) {
            applySavedProtection(
                for: activity,
                to: ManagedSettingsStore(
                    named: ManagedSettingsStore.Name(
                        MissionFocusMonitorConstants.boundaryStorePrefix + boundaryID
                    )
                )
            )
            postNotification(
                id: "boundary-reached-\(activity.rawValue)",
                title: "Boundary reached",
                body: "Your selected distractions are protected until the next reset."
            )
            recordHeartbeat()
            return
        }

        guard activity == MissionFocusMonitorConstants.activityName else {
            recordHeartbeat()
            return
        }

        recordMissionEndHandoff(reason: "threshold-reached")
        clearMissionShield()
        DeviceActivityCenter().stopMonitoring([activity])
        recordHeartbeat()
    }

    private func reconcileClimbTimeShield(for activity: DeviceActivityName) {
        let sharedStore = AppGroupClimbTimeMonitorStore()
        guard let configuration = try? sharedStore.loadConfiguration() else {
            clearClimbTimeShield()
            return
        }

        let date = Date()
        let currentDayKey = ClimbTimeMonitorShared.dayKey(for: date)
        let evidence: ClimbTimeUsageEvidence
        if let stored = try? sharedStore.loadEvidence(),
           stored.ownerUserID == configuration.ownerUserID,
           stored.dayKey == currentDayKey {
            evidence = stored
        } else if let transition = try? sharedStore.recordThreshold(
            ownerUserID: configuration.ownerUserID,
            dayKey: currentDayKey,
            thresholdSeconds: 0,
            callbackID: "interval-start:\(currentDayKey)",
            at: date
        ) {
            evidence = transition.evidence
        } else {
            clearClimbTimeShield()
            return
        }

        let allowance = configuration.effectiveAllowance(for: currentDayKey)
        if allowance == 0 || evidence.observedSeconds >= allowance {
            applyClimbTimeShield(for: activity)
        } else {
            clearClimbTimeShield()
        }
    }

    private func handleClimbTimeThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        guard let thresholdSeconds = ClimbTimeMonitorShared.thresholdSeconds(
            from: event.rawValue
        ) else {
            return
        }

        let sharedStore = AppGroupClimbTimeMonitorStore()
        guard let configuration = try? sharedStore.loadConfiguration() else {
            clearClimbTimeShield()
            return
        }

        let date = Date()
        let currentDayKey = ClimbTimeMonitorShared.dayKey(for: date)
        guard let transition = try? sharedStore.recordThreshold(
            ownerUserID: configuration.ownerUserID,
            dayKey: currentDayKey,
            thresholdSeconds: thresholdSeconds,
            callbackID: "\(currentDayKey):\(event.rawValue)",
            at: date
        ) else {
            return
        }

        let allowance = configuration.effectiveAllowance(for: currentDayKey)
        guard allowance == 0 || transition.evidence.observedSeconds >= allowance else {
            return
        }

        applyClimbTimeShield(for: activity)
        if transition.previousObservedSeconds < allowance {
            postNotification(
                id: "climb-time-used-\(currentDayKey)",
                title: "Climb Time complete",
                body: "Your selected distractions are protected for the rest of this allowance."
            )
        }
    }

    private func applyClimbTimeShield(for activity: DeviceActivityName) {
        guard let defaults = UserDefaults(
            suiteName: ClimbTimeMonitorShared.appGroupID
        ),
        let data = defaults.data(forKey: ClimbTimeMonitorShared.selectionKey),
        let selection = try? JSONDecoder().decode(
            FamilyActivitySelection.self,
            from: data
        ) else {
            clearClimbTimeShield()
            return
        }

        let store = ManagedSettingsStore(
            named: ManagedSettingsStore.Name(
                ClimbTimeMonitorShared.managedStoreName
            )
        )
        store.clearAllSettings()
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }

    private func clearClimbTimeShield() {
        ManagedSettingsStore(
            named: ManagedSettingsStore.Name(
                ClimbTimeMonitorShared.managedStoreName
            )
        ).clearAllSettings()
    }

    private func clearMissionShield() {
        ManagedSettingsStore(named: MissionFocusMonitorConstants.managedStoreName).clearAllSettings()
    }

    private func applySavedProtection(
        for activity: DeviceActivityName,
        to store: ManagedSettingsStore
    ) {
        guard let defaults = UserDefaults(suiteName: MissionFocusMonitorConstants.appGroupID) else {
            store.clearAllSettings()
            return
        }

        let configuration = scheduledConfiguration(
            for: activity.rawValue,
            defaults: defaults
        )
        let selectionKey = configuration?.selectionMode == .allowEssentialApps
            ? MissionFocusMonitorConstants.essentialSelectionKey
            : MissionFocusMonitorConstants.selectionKey
        let selection: FamilyActivitySelection
        if let data = defaults.data(forKey: selectionKey),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = decoded
        } else {
            selection = FamilyActivitySelection()
        }
        let blocksAdultContent = configuration?.blocksAdultWebContent
            ?? (defaults.object(forKey: MissionFocusMonitorConstants.adultContentKey) == nil
                ? true
                : defaults.bool(forKey: MissionFocusMonitorConstants.adultContentKey))
        let purityDomains: Set<WebDomain>
        if defaults.bool(forKey: MissionFocusMonitorConstants.purityProtectionEnabledKey) {
            purityDomains = Set(
                (defaults.stringArray(
                    forKey: MissionFocusMonitorConstants.purityProtectionDomainsKey
                ) ?? []).map { WebDomain(domain: $0) }
            )
        } else {
            purityDomains = []
        }

        store.clearAllSettings()
        if configuration?.selectionMode == .allowEssentialApps {
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
            store.webContent.blockedByFilter = blocksAdultContent
                ? .auto(purityDomains)
                : (purityDomains.isEmpty ? nil : .specific(purityDomains))
        } else {
            let protectedWebDomains = selection.webDomains.union(purityDomains)
            store.shield.applications = selection.applicationTokens.isEmpty
                ? nil
                : selection.applicationTokens
            store.shield.webDomains = selection.webDomainTokens.isEmpty
                ? nil
                : selection.webDomainTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty
                ? nil
                : .specific(selection.categoryTokens)
            store.webContent.blockedByFilter = blocksAdultContent
                ? .auto(protectedWebDomains)
                : (protectedWebDomains.isEmpty ? nil : .specific(protectedWebDomains))
        }
    }

    private func scheduledConfiguration(
        for activityName: String,
        defaults: UserDefaults
    ) -> ExtensionScheduledActivityConfiguration? {
        let key = MissionFocusMonitorConstants.activityConfigurationPrefix + activityName
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(
            ExtensionScheduledActivityConfiguration.self,
            from: data
        )
    }

    private func rhythmID(for activity: DeviceActivityName) -> String? {
        let rawValue = activity.rawValue
        guard rawValue.hasPrefix(MissionFocusMonitorConstants.rhythmActivityPrefix) else {
            return nil
        }
        let rhythmID = String(rawValue.dropFirst(MissionFocusMonitorConstants.rhythmActivityPrefix.count))
        return rhythmID.isEmpty ? nil : rhythmID
    }

    private func boundaryID(for activity: DeviceActivityName) -> String? {
        let rawValue = activity.rawValue
        guard rawValue.hasPrefix(MissionFocusMonitorConstants.boundaryActivityPrefix) else {
            return nil
        }
        let boundaryID = String(
            rawValue.dropFirst(MissionFocusMonitorConstants.boundaryActivityPrefix.count)
        )
        return boundaryID.isEmpty ? nil : boundaryID
    }

    private func postNotification(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: nil
            )
        )
    }

    private func recordHeartbeat() {
        let defaults = UserDefaults(suiteName: MissionFocusMonitorConstants.appGroupID)
        defaults?.set(
            Date().timeIntervalSince1970,
            forKey: MissionFocusMonitorConstants.heartbeatKey
        )
    }

    private func recordMissionEndHandoff(reason: String) {
        guard let defaults = UserDefaults(suiteName: MissionFocusMonitorConstants.appGroupID) else {
            return
        }
        guard let missionID = defaults.string(forKey: MissionFocusMonitorConstants.missionIDKey),
              !missionID.isEmpty else {
            return
        }

        let scheduledEndTimestamp = defaults.double(forKey: MissionFocusMonitorConstants.endsAtKey)
        defaults.set(missionID, forKey: MissionFocusMonitorConstants.monitorEndedMissionIDKey)
        defaults.set(
            scheduledEndTimestamp > 0 ? scheduledEndTimestamp : Date().timeIntervalSince1970,
            forKey: MissionFocusMonitorConstants.monitorEndedAtKey
        )
        defaults.set(reason, forKey: MissionFocusMonitorConstants.monitorEndedReasonKey)
        defaults.synchronize()
    }
}
