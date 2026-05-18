import Foundation
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
    func startFocus(for mission: Mission) async -> FocusModeState
    func stopFocus() async
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

    func startFocus(for mission: Mission) async -> FocusModeState {
        guard mission.appBlockingEnabled else {
            state = .simulated
            return state
        }

        let authorization = await requestAuthorization()
        guard authorization == .authorized else {
            state = authorization
            return state
        }

#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            let selection = ScreenTimeActivitySelectionStore.loadSelection()
            guard selection.hasShieldableContent else {
                state = .selectionRequired
                return state
            }

            applyShield(for: selection)
            state = .active
            return state
        }
#endif

        state = .simulated
        return state
    }

    func stopFocus() async {
#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            managedSettingsStore.clearAllSettings()
        }
#endif
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
