import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
#if canImport(DeviceActivity) && os(iOS)
import DeviceActivity
#endif
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
import ManagedSettings
#endif

enum FocusModeState: Equatable {
    case unavailable
    case permissionRequired
    case selectionRequired
    case denied
    case authorized
    case simulated
    case active
}

protocol FocusBlockingService {
    var state: FocusModeState { get }
    func refreshAuthorizationStatus() async -> FocusModeState
    func requestAuthorization() async -> FocusModeState
    func startFocus(for mission: Mission, endsAt: Date) async -> FocusModeState
    func stopFocus() async
    func stopFocus(preservingTimer: Bool) async
}

extension FocusBlockingService {
    func stopFocus() async {
        await stopFocus(preservingTimer: false)
    }
}

final class ScreenTimeFocusBlockingService: FocusBlockingService {
    private(set) var state: FocusModeState = .unavailable
#if canImport(FamilyControls) && os(iOS)
    @available(iOS 16.0, *)
    private var managedSettingsStore: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("TheClimbMissionFocus"))
    }
#endif

    func refreshAuthorizationStatus() async -> FocusModeState {
#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            state = Self.focusState(for: AuthorizationCenter.shared.authorizationStatus)
        } else {
            state = .unavailable
        }
#else
        state = .unavailable
#endif
        return state
    }

    func requestAuthorization() async -> FocusModeState {
#if canImport(FamilyControls) && os(iOS)
        guard #available(iOS 16.0, *) else {
            state = .unavailable
            return state
        }

        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            state = Self.focusState(for: AuthorizationCenter.shared.authorizationStatus)
        } catch {
            let currentState = Self.focusState(for: AuthorizationCenter.shared.authorizationStatus)
            state = currentState == .permissionRequired ? .denied : currentState
        }
#else
        state = .simulated
#endif
        return state
    }

    func startFocus(for mission: Mission, endsAt: Date) async -> FocusModeState {
        guard mission.appBlockingEnabled else {
            MissionDeviceActivityMonitorScheduler.stop()
            state = .simulated
            return state
        }

        let authorization = await requestAuthorization()
        guard authorization == .authorized else {
            MissionDeviceActivityMonitorScheduler.stop()
            state = authorization
            return state
        }

#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            let selection = ScreenTimeActivitySelectionStore.loadSelection()
            guard selection.hasShieldableContent else {
                MissionDeviceActivityMonitorScheduler.stop()
                state = .selectionRequired
                return state
            }

            guard MissionDeviceActivityMonitorScheduler.start(until: endsAt) else {
                managedSettingsStore.clearAllSettings()
                state = .simulated
                return state
            }

            applyShield(for: selection)
            state = .active
            return state
        }
#endif

        MissionDeviceActivityMonitorScheduler.stop()
        state = .simulated
        return state
    }

    func stopFocus(preservingTimer: Bool = false) async {
#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            managedSettingsStore.clearAllSettings()
        }
#endif
        MissionDeviceActivityMonitorScheduler.stop()
        if !preservingTimer {
            ActiveFocusMissionTimerStore.clear()
        }
        state = await refreshAuthorizationStatus()
    }

#if canImport(FamilyControls) && os(iOS)
    @available(iOS 16.0, *)
    private func applyShield(for selection: FamilyActivitySelection) {
        let store = managedSettingsStore
        store.clearAllSettings()
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    @available(iOS 16.0, *)
    private static func focusState(for authorizationStatus: AuthorizationStatus) -> FocusModeState {
        if #available(iOS 26.4, *) {
            switch authorizationStatus {
            case .approved, .approvedWithDataAccess:
                return .authorized
            case .denied:
                return .denied
            case .notDetermined:
                return .permissionRequired
            @unknown default:
                return .unavailable
            }
        }

        switch authorizationStatus {
        case .approved:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .permissionRequired
        default:
            return .unavailable
        }
    }
#endif
}

#if canImport(DeviceActivity) && os(iOS)
enum MissionDeviceActivityMonitorScheduler {
    static let activityName = DeviceActivityName("the-climb.mission-focus")

    static func start(until endsAt: Date) -> Bool {
        guard #available(iOS 16.0, *) else { return false }
        guard endsAt > Date().addingTimeInterval(30) else {
            stop()
            return false
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: components(for: Date()),
            intervalEnd: components(for: endsAt),
            repeats: false
        )

        let center = DeviceActivityCenter()
        center.stopMonitoring([activityName])
        do {
            try center.startMonitoring(activityName, during: schedule)
            return true
        } catch {
            #if DEBUG
            print("Failed to start mission DeviceActivity monitor: \(error.localizedDescription)")
            #endif
            stop()
            return false
        }
    }

    static func stop() {
        guard #available(iOS 16.0, *) else { return }
        DeviceActivityCenter().stopMonitoring([activityName])
    }

    private static func components(for date: Date) -> DateComponents {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar
        components.timeZone = TimeZone.current
        return components
    }
}
#else
enum MissionDeviceActivityMonitorScheduler {
    static func start(until endsAt: Date) -> Bool { false }
    static func stop() {}
}
#endif

struct ActiveFocusMissionEndHandoff: Equatable {
    let missionID: String
    let endedAt: Date
    let reason: String
}

enum ActiveFocusMissionTimerStore {
    private static let appGroupID = "group.com.jaydenlacy.theclimb"
    private static let missionIDKey = "the-climb.active-focus.mission-id.v1"
    private static let titleKey = "the-climb.active-focus.title.v1"
    private static let startedAtKey = "the-climb.active-focus.started-at.v1"
    private static let endsAtKey = "the-climb.active-focus.ends-at.v1"
    private static let durationMinutesKey = "the-climb.active-focus.duration-minutes.v1"
    private static let monitorEndedMissionIDKey = "the-climb.active-focus.monitor-ended-mission-id.v1"
    private static let monitorEndedAtKey = "the-climb.active-focus.monitor-ended-at.v1"
    private static let monitorEndedReasonKey = "the-climb.active-focus.monitor-ended-reason.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func save(mission: Mission, startedAt: Date = Date(), endsAt: Date) {
        clearMonitorEndHandoff()
        defaults.set(mission.id, forKey: missionIDKey)
        defaults.set(mission.title, forKey: titleKey)
        defaults.set(startedAt.timeIntervalSince1970, forKey: startedAtKey)
        defaults.set(endsAt.timeIntervalSince1970, forKey: endsAtKey)
        defaults.set(mission.durationMinutes, forKey: durationMinutesKey)
        defaults.synchronize()
    }

    static func endDate(for missionID: String? = nil) -> Date? {
        if let missionID, defaults.string(forKey: missionIDKey) != missionID {
            return nil
        }

        let timestamp = defaults.double(forKey: endsAtKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func consumeMonitorEndHandoff() -> ActiveFocusMissionEndHandoff? {
        guard let missionID = defaults.string(forKey: monitorEndedMissionIDKey),
              !missionID.isEmpty else {
            return nil
        }

        let timestamp = defaults.double(forKey: monitorEndedAtKey)
        let reason = defaults.string(forKey: monitorEndedReasonKey) ?? "device-activity-ended"
        clearMonitorEndHandoff()
        defaults.synchronize()
        return ActiveFocusMissionEndHandoff(
            missionID: missionID,
            endedAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date(),
            reason: reason
        )
    }

    static func clear() {
        defaults.removeObject(forKey: missionIDKey)
        defaults.removeObject(forKey: titleKey)
        defaults.removeObject(forKey: startedAtKey)
        defaults.removeObject(forKey: endsAtKey)
        defaults.removeObject(forKey: durationMinutesKey)
        clearMonitorEndHandoff()
        defaults.synchronize()
    }

    private static func clearMonitorEndHandoff() {
        defaults.removeObject(forKey: monitorEndedMissionIDKey)
        defaults.removeObject(forKey: monitorEndedAtKey)
        defaults.removeObject(forKey: monitorEndedReasonKey)
    }
}

#if canImport(ActivityKit) && os(iOS)
struct ClimbMissionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        var focusLabel: String
    }

    var missionID: String
    var missionTitle: String
    var durationMinutes: Int
    var appBlockingEnabled: Bool
    var isBlockingActive: Bool
}

enum MissionLiveActivityService {
    @available(iOS 16.1, *)
    static func start(for mission: Mission, endsAt: Date, focusState: FocusModeState) async {
        guard endsAt > Date() else {
            await end(missionID: mission.id)
            return
        }

        await end()

        let attributes = ClimbMissionAttributes(
            missionID: mission.id,
            missionTitle: mission.title,
            durationMinutes: mission.durationMinutes,
            appBlockingEnabled: mission.appBlockingEnabled,
            isBlockingActive: focusState == .active
        )
        let content = ActivityContent(
            state: ClimbMissionAttributes.ContentState(
                endsAt: endsAt,
                focusLabel: focusLabel(for: mission, focusState: focusState)
            ),
            staleDate: endsAt
        )

        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            #if DEBUG
            print("Failed to start mission Live Activity: \(error.localizedDescription)")
            #endif
        }
    }

    @available(iOS 16.1, *)
    private static func focusLabel(for mission: Mission, focusState: FocusModeState) -> String {
        switch focusState {
        case .active:
            "Apps blocked"
        case .selectionRequired:
            "Choose apps"
        case .permissionRequired:
            "Needs permission"
        case .denied:
            "Blocking off"
        case .authorized:
            mission.appBlockingEnabled ? "Blocking ready" : "Focus timer"
        case .simulated:
            "Focus timer"
        case .unavailable:
            "Mission timer"
        }
    }

    @available(iOS 16.1, *)
    static func end(missionID: String? = nil) async {
        for activity in Activity<ClimbMissionAttributes>.activities where missionID == nil || activity.attributes.missionID == missionID {
            let content = ActivityContent(
                state: ClimbMissionAttributes.ContentState(
                    endsAt: Date(),
                    focusLabel: "Complete"
                ),
                staleDate: nil
            )
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
#else
enum MissionLiveActivityService {
    static func start(for mission: Mission, endsAt: Date, focusState: FocusModeState) async {}
    static func end(missionID: String? = nil) async {}
}
#endif

#if canImport(FamilyControls) && os(iOS)
enum ScreenTimeActivitySelectionStore {
    private static let appGroupID = "group.com.jaydenlacy.theclimb"
    private static let storageKey = "the-climb.screen-time-selection.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    @available(iOS 16.0, *)
    static func loadSelection() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: storageKey) else {
            return FamilyActivitySelection()
        }

        return (try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)) ?? FamilyActivitySelection()
    }

    @available(iOS 16.0, *)
    static func saveSelection(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

@available(iOS 16.0, *)
extension FamilyActivitySelection {
    var hasShieldableContent: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }

    var shieldableContentCount: Int {
        applicationTokens.count + categoryTokens.count + webDomainTokens.count
    }
}
#endif
