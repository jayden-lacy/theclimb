import Foundation
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

enum ScreenTimeFeature: String, Codable, CaseIterable {
    case immediateFocus
    case recurringRhythms
    case appBoundaries
    case openBoundaries
    case permanentProtection
    case accountabilityLock
    case guardianApproval
    case safariExtension
    case networkFiltering
}

struct ScreenTimeFeatureFlags: Codable, Equatable {
    var enabledFeatures: Set<ScreenTimeFeature>

    func isEnabled(_ feature: ScreenTimeFeature) -> Bool {
        enabledFeatures.contains(feature)
    }

    static let production = ScreenTimeFeatureFlags(
        enabledFeatures: [
            .immediateFocus,
            .recurringRhythms,
            .appBoundaries,
            .permanentProtection,
            .safariExtension
        ]
    )
}

enum ProtectionSourceKind: String, Codable, CaseIterable {
    case mission
    case prayer
    case bibleStudy
    case focusSession
    case rhythm
    case boundary
    case permanentProtection
    case accountability
    case guardian
    case temporaryException

    var priority: Int {
        switch self {
        case .guardian:
            600
        case .accountability:
            550
        case .permanentProtection:
            500
        case .temporaryException:
            400
        case .boundary:
            300
        case .rhythm:
            200
        case .mission, .prayer, .bibleStudy, .focusSession:
            100
        }
    }

    var canBeTemporarilyRelaxed: Bool {
        switch self {
        case .permanentProtection, .accountability, .guardian:
            false
        default:
            true
        }
    }
}

enum ProtectionStrictness: Int, Codable, CaseIterable, Comparable {
    case flexible = 0
    case intentional = 1
    case locked = 2
    case accountabilityLocked = 3

    static func < (lhs: ProtectionStrictness, rhs: ProtectionStrictness) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ProtectionPolicy: Identifiable, Codable, Equatable {
    var id: String
    var source: ProtectionSourceKind
    var strictness: ProtectionStrictness
    var selectionReference: String?
    var blocksAdultWebContent: Bool
    var isEnabled: Bool
    var startsAt: Date?
    var endsAt: Date?
    var temporaryExceptionForPolicyID: String?
    var createdAt: Date
    var updatedAt: Date

    func isActive(at date: Date) -> Bool {
        guard isEnabled else { return false }
        if let startsAt, date < startsAt {
            return false
        }
        if let endsAt, date >= endsAt {
            return false
        }
        return true
    }

    static func mission(
        missionID: String,
        startsAt: Date,
        endsAt: Date,
        blocksAdultWebContent: Bool
    ) -> ProtectionPolicy {
        ProtectionPolicy(
            id: "mission:\(missionID)",
            source: .mission,
            strictness: .intentional,
            selectionReference: ScreenTimeSelectionReference.defaultSelection,
            blocksAdultWebContent: blocksAdultWebContent,
            isEnabled: true,
            startsAt: startsAt,
            endsAt: endsAt,
            temporaryExceptionForPolicyID: nil,
            createdAt: startsAt,
            updatedAt: startsAt
        )
    }
}

enum ScreenTimeSelectionReference {
    static let defaultSelection = "default-selection-v1"
}

struct ScreenTimeProtectionPreferences: Codable, Equatable {
    var adultContentProtectionRequested: Bool
    var hasSavedSelection: Bool
    var featureFlags: ScreenTimeFeatureFlags

    static let defaults = ScreenTimeProtectionPreferences(
        adultContentProtectionRequested: true,
        hasSavedSelection: false,
        featureFlags: .production
    )
}

struct ScreenTimePolicyEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var preferences: ScreenTimeProtectionPreferences
    var policies: [ProtectionPolicy]
    var migratedAt: Date?
    var updatedAt: Date

    static func empty(at date: Date = Date()) -> ScreenTimePolicyEnvelope {
        ScreenTimePolicyEnvelope(
            schemaVersion: currentSchemaVersion,
            preferences: .defaults,
            policies: [],
            migratedAt: nil,
            updatedAt: date
        )
    }
}

struct ProtectionPolicyResolution: Equatable {
    var activePolicyIDs: [String]
    var suppressedPolicyIDs: [String]
    var activeSelectionReferences: [String]
    var blocksAdultWebContent: Bool
    var strongestStrictness: ProtectionStrictness?
    var permanentProtectionActive: Bool
    var nextTransitionAt: Date?

    var isProtectionActive: Bool {
        !activePolicyIDs.isEmpty
    }
}

protocol ScreenTimePolicyResolving {
    func resolve(_ policies: [ProtectionPolicy], at date: Date) -> ProtectionPolicyResolution
}

struct ScreenTimePolicyResolver: ScreenTimePolicyResolving {
    func resolve(_ policies: [ProtectionPolicy], at date: Date = Date()) -> ProtectionPolicyResolution {
        let enabledPolicies = policies.filter(\.isEnabled)
        let activePolicies = enabledPolicies.filter { $0.isActive(at: date) }
        let exceptions = activePolicies.filter {
            $0.source == .temporaryException && $0.temporaryExceptionForPolicyID != nil
        }

        let suppressionTargets = Set(exceptions.compactMap(\.temporaryExceptionForPolicyID))
        var suppressedPolicyIDs: [String] = []
        let enforcingPolicies = activePolicies.filter { policy in
            guard policy.source != .temporaryException else { return false }
            guard suppressionTargets.contains(policy.id) else { return true }
            guard policy.source.canBeTemporarilyRelaxed else { return true }
            suppressedPolicyIDs.append(policy.id)
            return false
        }
        .sorted {
            if $0.source.priority == $1.source.priority {
                return $0.id < $1.id
            }
            return $0.source.priority > $1.source.priority
        }

        let transitionDates = enabledPolicies.flatMap { policy -> [Date] in
            [policy.startsAt, policy.endsAt]
                .compactMap { $0 }
                .filter { $0 > date }
        }

        return ProtectionPolicyResolution(
            activePolicyIDs: enforcingPolicies.map(\.id),
            suppressedPolicyIDs: suppressedPolicyIDs.sorted(),
            activeSelectionReferences: Array(
                Set(enforcingPolicies.compactMap(\.selectionReference))
            ).sorted(),
            blocksAdultWebContent: enforcingPolicies.contains(where: \.blocksAdultWebContent),
            strongestStrictness: enforcingPolicies.map(\.strictness).max(),
            permanentProtectionActive: enforcingPolicies.contains {
                $0.source == .permanentProtection
            },
            nextTransitionAt: transitionDates.min()
        )
    }
}

enum ScreenTimePolicyStoreError: Error, Equatable {
    case appGroupUnavailable
    case encodingFailed
    case decodingFailed
    case unsupportedSchema(Int)
    case verificationFailed
}

protocol ScreenTimePolicyStoring {
    var hasStoredEnvelope: Bool { get }
    func load() throws -> ScreenTimePolicyEnvelope
    func save(_ envelope: ScreenTimePolicyEnvelope) throws
}

final class AppGroupScreenTimePolicyStore: ScreenTimePolicyStoring {
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let envelopeKey = "the-climb.screen-time-policy-envelope.v1"

    private let defaults: UserDefaults?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppGroupScreenTimePolicyStore.appGroupID)) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    var hasStoredEnvelope: Bool {
        defaults?.data(forKey: Self.envelopeKey) != nil
    }

    func load() throws -> ScreenTimePolicyEnvelope {
        guard let defaults else {
            throw ScreenTimePolicyStoreError.appGroupUnavailable
        }
        guard let data = defaults.data(forKey: Self.envelopeKey) else {
            return .empty()
        }
        guard let envelope = try? decoder.decode(ScreenTimePolicyEnvelope.self, from: data) else {
            throw ScreenTimePolicyStoreError.decodingFailed
        }
        guard envelope.schemaVersion <= ScreenTimePolicyEnvelope.currentSchemaVersion else {
            throw ScreenTimePolicyStoreError.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope
    }

    func save(_ envelope: ScreenTimePolicyEnvelope) throws {
        guard let defaults else {
            throw ScreenTimePolicyStoreError.appGroupUnavailable
        }
        guard let data = try? encoder.encode(envelope) else {
            throw ScreenTimePolicyStoreError.encodingFailed
        }
        defaults.set(data, forKey: Self.envelopeKey)

        guard let savedData = defaults.data(forKey: Self.envelopeKey),
              let savedEnvelope = try? decoder.decode(ScreenTimePolicyEnvelope.self, from: savedData),
              savedEnvelope == envelope else {
            throw ScreenTimePolicyStoreError.verificationFailed
        }
    }
}

struct LegacyActiveFocusMission: Equatable {
    var missionID: String
    var startedAt: Date
    var endsAt: Date
}

final class ScreenTimePolicyMigrationService {
    static let legacyAdultContentKey = "the-climb.adult-web-content-filter.v1"
    static let legacySelectionKey = "the-climb.screen-time-selection.v1"
    static let legacyMissionIDKey = "the-climb.active-focus.mission-id.v1"
    static let legacyMissionStartedAtKey = "the-climb.active-focus.started-at.v1"
    static let legacyMissionEndsAtKey = "the-climb.active-focus.ends-at.v1"

    private let store: ScreenTimePolicyStoring
    private let legacyDefaults: UserDefaults?
    private let now: () -> Date

    init(
        store: ScreenTimePolicyStoring,
        legacyDefaults: UserDefaults?,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.legacyDefaults = legacyDefaults
        self.now = now
    }

    @discardableResult
    func runIfNeeded() throws -> ScreenTimePolicyEnvelope {
        var partiallyMigratedEnvelope: ScreenTimePolicyEnvelope?
        if store.hasStoredEnvelope {
            do {
                let existing = try store.load()
                if existing.schemaVersion == ScreenTimePolicyEnvelope.currentSchemaVersion,
                   existing.migratedAt != nil {
                    return existing
                }
                partiallyMigratedEnvelope = existing
            } catch let error as ScreenTimePolicyStoreError {
                if case .unsupportedSchema = error {
                    throw error
                }
                // Corrupt v1 policy data is rebuilt from the untouched legacy keys.
            }
        }

        let migrationDate = now()
        let adultProtectionRequested = legacyDefaults?.object(
            forKey: Self.legacyAdultContentKey
        ) == nil ? true : (legacyDefaults?.bool(forKey: Self.legacyAdultContentKey) ?? true)
        let hasSavedSelection = legacyDefaults?.data(forKey: Self.legacySelectionKey) != nil
        var policies = partiallyMigratedEnvelope?.policies ?? []

        if let activeMission = activeLegacyMission(at: migrationDate) {
            let migratedMission = ProtectionPolicy.mission(
                missionID: activeMission.missionID,
                startsAt: activeMission.startedAt,
                endsAt: activeMission.endsAt,
                blocksAdultWebContent: adultProtectionRequested
            )
            policies.removeAll { $0.id == migratedMission.id }
            policies.append(migratedMission)
        }

        let envelope = ScreenTimePolicyEnvelope(
            schemaVersion: ScreenTimePolicyEnvelope.currentSchemaVersion,
            preferences: partiallyMigratedEnvelope?.preferences
                ?? ScreenTimeProtectionPreferences(
                    adultContentProtectionRequested: adultProtectionRequested,
                    hasSavedSelection: hasSavedSelection,
                    featureFlags: .production
                ),
            policies: policies,
            migratedAt: migrationDate,
            updatedAt: migrationDate
        )
        try store.save(envelope)
        return try store.load()
    }

    private func activeLegacyMission(at date: Date) -> LegacyActiveFocusMission? {
        guard let defaults = legacyDefaults,
              let missionID = defaults.string(forKey: Self.legacyMissionIDKey),
              !missionID.isEmpty else {
            return nil
        }

        let startedAtTimestamp = defaults.double(forKey: Self.legacyMissionStartedAtKey)
        let endsAtTimestamp = defaults.double(forKey: Self.legacyMissionEndsAtKey)
        guard endsAtTimestamp > date.timeIntervalSince1970 else {
            return nil
        }

        return LegacyActiveFocusMission(
            missionID: missionID,
            startedAt: startedAtTimestamp > 0
                ? Date(timeIntervalSince1970: startedAtTimestamp)
                : date,
            endsAt: Date(timeIntervalSince1970: endsAtTimestamp)
        )
    }
}

final class ScreenTimePolicyCoordinator {
    private let store: ScreenTimePolicyStoring
    private let migration: ScreenTimePolicyMigrationService
    private let now: () -> Date

    init(
        store: ScreenTimePolicyStoring? = nil,
        defaults: UserDefaults? = UserDefaults(suiteName: AppGroupScreenTimePolicyStore.appGroupID),
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedStore = store ?? AppGroupScreenTimePolicyStore(defaults: defaults)
        self.store = resolvedStore
        migration = ScreenTimePolicyMigrationService(
            store: resolvedStore,
            legacyDefaults: defaults,
            now: now
        )
        self.now = now
    }

    @discardableResult
    func prepare() -> ScreenTimePolicyEnvelope {
        (try? migration.runIfNeeded()) ?? .empty(at: now())
    }

    @discardableResult
    func activateMission(
        missionID: String,
        endsAt: Date,
        blocksAdultWebContent: Bool
    ) -> ScreenTimePolicyEnvelope {
        let activationDate = now()
        var envelope = prepare()
        envelope.policies.removeAll { $0.id == "mission:\(missionID)" }
        envelope.policies.append(
            .mission(
                missionID: missionID,
                startsAt: activationDate,
                endsAt: endsAt,
                blocksAdultWebContent: blocksAdultWebContent
            )
        )
        envelope.preferences.adultContentProtectionRequested = blocksAdultWebContent
        envelope.updatedAt = activationDate
        try? store.save(envelope)
        return envelope
    }

    @discardableResult
    func upsert(_ policy: ProtectionPolicy) -> ScreenTimePolicyEnvelope {
        var envelope = prepare()
        envelope.policies.removeAll { $0.id == policy.id }
        envelope.policies.append(policy)
        envelope.updatedAt = now()
        try? store.save(envelope)
        return envelope
    }

    @discardableResult
    func removePolicy(id: String) -> ScreenTimePolicyEnvelope {
        var envelope = prepare()
        envelope.policies.removeAll { $0.id == id }
        envelope.updatedAt = now()
        try? store.save(envelope)
        return envelope
    }

    @discardableResult
    func deactivateMissionPolicies() -> ScreenTimePolicyEnvelope {
        var envelope = prepare()
        envelope.policies.removeAll { $0.source == .mission }
        envelope.updatedAt = now()
        try? store.save(envelope)
        return envelope
    }

    func resolution(at date: Date? = nil) -> ProtectionPolicyResolution {
        ScreenTimePolicyResolver().resolve(prepare().policies, at: date ?? now())
    }
}

enum ScreenTimeAuthorizationState: String, Codable, Equatable {
    case unsupported
    case notDetermined
    case denied
    case approved
    case approvedWithDataAccess

    var grantsProtectionAccess: Bool {
        self == .approved || self == .approvedWithDataAccess
    }
}

protocol ScreenTimeAuthorizationProviding {
    func currentStatus() -> ScreenTimeAuthorizationState
    func requestAuthorization() async -> ScreenTimeAuthorizationState
}

#if canImport(FamilyControls) && os(iOS)
final class AppleScreenTimeAuthorizationProvider: ScreenTimeAuthorizationProviding {
    func currentStatus() -> ScreenTimeAuthorizationState {
        Self.map(AuthorizationCenter.shared.authorizationStatus)
    }

    func requestAuthorization() async -> ScreenTimeAuthorizationState {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return currentStatus()
        } catch {
            let status = currentStatus()
            return status == .notDetermined ? .denied : status
        }
    }

    private static func map(_ status: AuthorizationStatus) -> ScreenTimeAuthorizationState {
        if #available(iOS 26.4, *) {
            switch status {
            case .approved:
                return .approved
            case .approvedWithDataAccess:
                return .approvedWithDataAccess
            case .denied:
                return .denied
            case .notDetermined:
                return .notDetermined
            @unknown default:
                return .unsupported
            }
        }

        switch status {
        case .approved:
            return .approved
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        default:
            return .unsupported
        }
    }
}
#else
final class AppleScreenTimeAuthorizationProvider: ScreenTimeAuthorizationProviding {
    func currentStatus() -> ScreenTimeAuthorizationState { .unsupported }
    func requestAuthorization() async -> ScreenTimeAuthorizationState { .unsupported }
}
#endif

enum ProtectionHealthStatus: String, Codable, Equatable {
    case fullyProtected
    case partiallyProtected
    case actionRequired
    case off
    case unavailable
}

enum ProtectionHealthReason: String, Codable, Equatable {
    case authorizationUnavailable
    case authorizationRequired
    case appGroupUnavailable
    case selectionRequired
    case policyDataMissing
    case policyDataStale
    case enforcementHeartbeatMissing
    case enforcementHeartbeatStale
    case safariLayerUnhealthy
    case networkLayerUnhealthy
}

struct ProtectionHealthSignal: Equatable {
    var authorization: ScreenTimeAuthorizationState
    var appGroupAccessible: Bool
    var hasSavedSelection: Bool
    var adultProtectionExpected: Bool
    var expectedEnforcementActive: Bool
    var policyUpdatedAt: Date?
    var enforcementHeartbeatAt: Date?
    var safariLayerConfigured: Bool
    var safariLayerHealthy: Bool
    var networkLayerConfigured: Bool
    var networkLayerHealthy: Bool
}

struct ProtectionHealthReport: Equatable {
    var status: ProtectionHealthStatus
    var reasons: [ProtectionHealthReason]
    var evaluatedAt: Date
}

struct ProtectionHealthEvaluator {
    var policyStaleInterval: TimeInterval = 24 * 60 * 60
    var heartbeatStaleInterval: TimeInterval = 10 * 60

    func evaluate(
        _ signal: ProtectionHealthSignal,
        at date: Date = Date()
    ) -> ProtectionHealthReport {
        guard signal.authorization != .unsupported else {
            return report(.unavailable, [.authorizationUnavailable], at: date)
        }
        guard signal.expectedEnforcementActive else {
            return report(.off, [], at: date)
        }

        var actionReasons: [ProtectionHealthReason] = []
        if !signal.authorization.grantsProtectionAccess {
            actionReasons.append(.authorizationRequired)
        }
        if !signal.appGroupAccessible {
            actionReasons.append(.appGroupUnavailable)
        }
        if !signal.hasSavedSelection && !signal.adultProtectionExpected {
            actionReasons.append(.selectionRequired)
        }
        if signal.policyUpdatedAt == nil {
            actionReasons.append(.policyDataMissing)
        } else if let policyUpdatedAt = signal.policyUpdatedAt,
                  date.timeIntervalSince(policyUpdatedAt) > policyStaleInterval {
            actionReasons.append(.policyDataStale)
        }
        if !actionReasons.isEmpty {
            return report(.actionRequired, actionReasons, at: date)
        }

        var partialReasons: [ProtectionHealthReason] = []
        if signal.enforcementHeartbeatAt == nil {
            partialReasons.append(.enforcementHeartbeatMissing)
        } else if let heartbeat = signal.enforcementHeartbeatAt,
                  date.timeIntervalSince(heartbeat) > heartbeatStaleInterval {
            partialReasons.append(.enforcementHeartbeatStale)
        }
        if signal.safariLayerConfigured && !signal.safariLayerHealthy {
            partialReasons.append(.safariLayerUnhealthy)
        }
        if signal.networkLayerConfigured && !signal.networkLayerHealthy {
            partialReasons.append(.networkLayerUnhealthy)
        }

        return partialReasons.isEmpty
            ? report(.fullyProtected, [], at: date)
            : report(.partiallyProtected, partialReasons, at: date)
    }

    private func report(
        _ status: ProtectionHealthStatus,
        _ reasons: [ProtectionHealthReason],
        at date: Date
    ) -> ProtectionHealthReport {
        ProtectionHealthReport(status: status, reasons: reasons, evaluatedAt: date)
    }
}

enum ScreenTimeProtectionHealthStore {
    static let enforcementHeartbeatKey = "the-climb.screen-time.enforcement-heartbeat.v1"

    static func recordEnforcementHeartbeat(
        at date: Date = Date(),
        defaults: UserDefaults? = UserDefaults(
            suiteName: AppGroupScreenTimePolicyStore.appGroupID
        )
    ) {
        defaults?.set(date.timeIntervalSince1970, forKey: enforcementHeartbeatKey)
    }

    static func enforcementHeartbeat(
        defaults: UserDefaults? = UserDefaults(
            suiteName: AppGroupScreenTimePolicyStore.appGroupID
        )
    ) -> Date? {
        guard let defaults,
              defaults.object(forKey: enforcementHeartbeatKey) != nil else {
            return nil
        }
        return Date(
            timeIntervalSince1970: defaults.double(forKey: enforcementHeartbeatKey)
        )
    }
}

struct ScreenTimeProtectionHealthReader {
    private let defaults: UserDefaults?
    private let store: ScreenTimePolicyStoring

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: AppGroupScreenTimePolicyStore.appGroupID
        ),
        store: ScreenTimePolicyStoring? = nil
    ) {
        self.defaults = defaults
        self.store = store ?? AppGroupScreenTimePolicyStore(defaults: defaults)
    }

    func report(
        authorization: ScreenTimeAuthorizationState,
        at date: Date = Date()
    ) -> ProtectionHealthReport {
        let envelope = try? store.load()
        let resolution = ScreenTimePolicyResolver().resolve(
            envelope?.policies ?? [],
            at: date
        )
        let safariState = SafariContentBlockerSharedStore.lastRecordedStatus()
        let safariStateIsFresh = safariState.map {
            date.timeIntervalSince($0.checkedAt) < 24 * 60 * 60
        } ?? false
        let safariExpected = resolution.permanentProtectionActive
            && ScreenTimeFeatureFlags.production.isEnabled(.safariExtension)
        let signal = ProtectionHealthSignal(
            authorization: authorization,
            appGroupAccessible: defaults != nil,
            hasSavedSelection: defaults?.data(
                forKey: ScreenTimePolicyMigrationService.legacySelectionKey
            ) != nil,
            adultProtectionExpected: resolution.blocksAdultWebContent,
            expectedEnforcementActive: resolution.isProtectionActive,
            policyUpdatedAt: envelope?.updatedAt,
            enforcementHeartbeatAt: ScreenTimeProtectionHealthStore.enforcementHeartbeat(
                defaults: defaults
            ),
            safariLayerConfigured: safariExpected,
            safariLayerHealthy: safariState?.status == .enabled
                && safariStateIsFresh,
            networkLayerConfigured: false,
            networkLayerHealthy: false
        )
        return ProtectionHealthEvaluator().evaluate(signal, at: date)
    }
}
