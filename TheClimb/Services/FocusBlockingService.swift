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
    private let authorizationProvider: ScreenTimeAuthorizationProviding
    private let policyCoordinator: ScreenTimePolicyCoordinator

    init(
        authorizationProvider: ScreenTimeAuthorizationProviding = AppleScreenTimeAuthorizationProvider(),
        policyCoordinator: ScreenTimePolicyCoordinator = ScreenTimePolicyCoordinator()
    ) {
        self.authorizationProvider = authorizationProvider
        self.policyCoordinator = policyCoordinator
    }

#if canImport(FamilyControls) && os(iOS)
    @available(iOS 16.0, *)
    private var managedSettingsStore: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("TheClimbMissionFocus"))
    }
#endif

    func refreshAuthorizationStatus() async -> FocusModeState {
        policyCoordinator.prepare()
        state = Self.focusState(for: authorizationProvider.currentStatus())
        return state
    }

    func requestAuthorization() async -> FocusModeState {
        policyCoordinator.prepare()
        state = Self.focusState(for: await authorizationProvider.requestAuthorization())
        return state
    }

    func startFocus(for mission: Mission, endsAt: Date) async -> FocusModeState {
        guard mission.appBlockingEnabled else {
            policyCoordinator.deactivateMissionPolicies()
            MissionDeviceActivityMonitorScheduler.stop()
            state = .simulated
            return state
        }

        let authorization = await requestAuthorization()
        guard authorization == .authorized else {
            policyCoordinator.deactivateMissionPolicies()
            MissionDeviceActivityMonitorScheduler.stop()
            state = authorization
            return state
        }

#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            let selection = ScreenTimeActivitySelectionStore.loadSelection()
            guard selection.hasShieldableContent || FocusAdultContentFilterStore.isEnabled else {
                policyCoordinator.deactivateMissionPolicies()
                MissionDeviceActivityMonitorScheduler.stop()
                state = .selectionRequired
                return state
            }

            guard MissionDeviceActivityMonitorScheduler.start(until: endsAt) else {
                policyCoordinator.deactivateMissionPolicies()
                managedSettingsStore.clearAllSettings()
                state = .simulated
                return state
            }

            applyShield(for: selection)
            policyCoordinator.activateMission(
                missionID: mission.id,
                endsAt: endsAt,
                blocksAdultWebContent: FocusAdultContentFilterStore.isEnabled
            )
            ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat()
            state = .active
            return state
        }
#endif

        policyCoordinator.deactivateMissionPolicies()
        ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat()
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
        policyCoordinator.deactivateMissionPolicies()
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
        let purityDomains = Set(
            PurityProtectionPreferenceStore.protectedDomainStrings.map {
                WebDomain(domain: $0)
            }
        )
        let protectedWebDomains = selection.webDomains.union(purityDomains)
        store.clearAllSettings()
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.webContent.blockedByFilter = FocusAdultContentFilterStore.isEnabled
            ? .auto(protectedWebDomains)
            : selectedWebContentFilter(for: protectedWebDomains)
    }

    @available(iOS 16.0, *)
    private func selectedWebContentFilter(
        for webDomains: Set<WebDomain>
    ) -> WebContentSettings.FilterPolicy? {
        webDomains.isEmpty ? nil : .specific(webDomains)
    }
#endif

    private static func focusState(
        for authorizationStatus: ScreenTimeAuthorizationState
    ) -> FocusModeState {
        switch authorizationStatus {
        case .approved, .approvedWithDataAccess:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .permissionRequired
        case .unsupported:
            return .unavailable
        }
    }
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

struct ActiveFocusMissionTiming: Equatable {
    let missionID: String
    let startedAt: Date
    let plannedEndAt: Date
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

    static func timing(for missionID: String) -> ActiveFocusMissionTiming? {
        guard defaults.string(forKey: missionIDKey) == missionID else {
            return nil
        }
        let startedTimestamp = defaults.double(forKey: startedAtKey)
        let endsTimestamp = defaults.double(forKey: endsAtKey)
        guard startedTimestamp > 0, endsTimestamp > startedTimestamp else {
            return nil
        }
        return ActiveFocusMissionTiming(
            missionID: missionID,
            startedAt: Date(timeIntervalSince1970: startedTimestamp),
            plannedEndAt: Date(timeIntervalSince1970: endsTimestamp)
        )
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
        var startedAt: Date
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
                startedAt: endsAt.addingTimeInterval(TimeInterval(-max(mission.durationMinutes, 1) * 60)),
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
            "Shield active"
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
                    startedAt: Date(),
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
enum FocusAdultContentFilterStore {
    private static let appGroupID = "group.com.jaydenlacy.theclimb"
    private static let storageKey = "the-climb.adult-web-content-filter.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var isEnabled: Bool {
        guard defaults.object(forKey: storageKey) != nil else { return true }
        return defaults.bool(forKey: storageKey)
    }

    static func setEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: storageKey)
        PurityProtectionPreferenceStore.setFocusFilterEnabled(isEnabled)
        defaults.synchronize()
    }
}

enum ScreenTimeActivitySelectionStore {
    private static let appGroupID = "group.com.jaydenlacy.theclimb"
    private static let storageKey = "the-climb.screen-time-selection.v1"
    private static let templatesKey = "the-climb.screen-time-templates.v1"

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

    static func loadTemplateSummaries() -> [FocusTemplateSummary] {
        guard let data = defaults.data(forKey: templatesKey) else { return [] }
        return (try? JSONDecoder().decode([FocusTemplateSummary].self, from: data)) ?? []
    }

    @available(iOS 16.0, *)
    static func saveCurrentSelectionAsTemplate(_ draft: FocusTemplateDraft) {
        let selection = loadSelection()
        guard selection.hasShieldableContent,
              let selectionData = try? JSONEncoder().encode(selection) else { return }
        var templates = loadTemplateSummaries()
        let now = Date()
        let template = FocusTemplateSummary(
            id: draft.id,
            name: draft.name,
            subtitle: draft.subtitle,
            systemImage: draft.systemImage,
            selectionData: selectionData,
            shieldableContentCount: selection.shieldableContentCount,
            createdAt: templates.first(where: { $0.id == draft.id })?.createdAt ?? now,
            updatedAt: now
        )

        templates.removeAll { $0.id == draft.id }
        templates.insert(template, at: 0)
        saveTemplateSummaries(templates)
    }

    @available(iOS 16.0, *)
    @discardableResult
    static func applyTemplate(id: String) -> FamilyActivitySelection? {
        guard let template = loadTemplateSummaries().first(where: { $0.id == id }),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: template.selectionData),
              selection.hasShieldableContent else {
            return nil
        }
        saveSelection(selection)
        return selection
    }

    static func deleteTemplate(id: String) {
        saveTemplateSummaries(loadTemplateSummaries().filter { $0.id != id })
    }

    private static func saveTemplateSummaries(_ templates: [FocusTemplateSummary]) {
        guard let data = try? JSONEncoder().encode(Array(templates.prefix(8))) else { return }
        defaults.set(data, forKey: templatesKey)
        defaults.synchronize()
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

struct FocusTemplateDraft: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let systemImage: String

    static let defaults: [FocusTemplateDraft] = [
        FocusTemplateDraft(
            id: "morning",
            name: "Morning",
            subtitle: "Protect scripture and first work",
            systemImage: "sunrise.fill"
        ),
        FocusTemplateDraft(
            id: "study",
            name: "Study",
            subtitle: "Block social apps for deep work",
            systemImage: "book.closed.fill"
        ),
        FocusTemplateDraft(
            id: "night",
            name: "Night",
            subtitle: "Keep the last hour quiet",
            systemImage: "moon.stars.fill"
        )
    ]
}

struct FocusTemplateSummary: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var subtitle: String
    var systemImage: String
    var selectionData: Data
    var shieldableContentCount: Int
    var createdAt: Date
    var updatedAt: Date
}
#endif
