import DeviceActivity
import Foundation
import ManagedSettings

private enum MissionFocusMonitorConstants {
    static let activityName = DeviceActivityName("the-climb.mission-focus")
    static let managedStoreName = ManagedSettingsStore.Name("TheClimbMissionFocus")
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let missionIDKey = "the-climb.active-focus.mission-id.v1"
    static let titleKey = "the-climb.active-focus.title.v1"
    static let startedAtKey = "the-climb.active-focus.started-at.v1"
    static let endsAtKey = "the-climb.active-focus.ends-at.v1"
    static let durationMinutesKey = "the-climb.active-focus.duration-minutes.v1"
    static let monitorEndedMissionIDKey = "the-climb.active-focus.monitor-ended-mission-id.v1"
    static let monitorEndedAtKey = "the-climb.active-focus.monitor-ended-at.v1"
    static let monitorEndedReasonKey = "the-climb.active-focus.monitor-ended-reason.v1"
}

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == MissionFocusMonitorConstants.activityName else { return }

        recordMissionEndHandoff(reason: "interval-ended")
        clearMissionShield()
        DeviceActivityCenter().stopMonitoring([activity])
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == MissionFocusMonitorConstants.activityName else { return }

        recordMissionEndHandoff(reason: "threshold-reached")
        clearMissionShield()
        DeviceActivityCenter().stopMonitoring([activity])
    }

    private func clearMissionShield() {
        ManagedSettingsStore(named: MissionFocusMonitorConstants.managedStoreName).clearAllSettings()
    }

    private func recordMissionEndHandoff(reason: String) {
        let defaults = UserDefaults(suiteName: MissionFocusMonitorConstants.appGroupID) ?? .standard
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
