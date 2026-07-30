import Foundation
import UserNotifications

enum AttentionAssistNotificationPermission: String, Codable, Equatable {
    case notDetermined
    case denied
    case authorized
    case unavailable
}

enum AttentionAssistRuntimeError: LocalizedError, Equatable {
    case appGroupUnavailable
    case stateEncodingFailed
    case stateDecodingFailed
    case stateVerificationFailed
    case unsupportedStateSchema(Int)
    case invalidPreferences(String)
    case unverifiedEvidence(AttentionAssistRecommendationKind)
    case notificationPermissionNotDetermined
    case notificationPermissionDenied
    case notificationPermissionUnavailable
    case notificationSchedulingFailed(String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Attention Assist could not access its shared app storage."
        case .stateEncodingFailed:
            return "Attention Assist could not prepare its settings for storage."
        case .stateDecodingFailed:
            return "Attention Assist could not read its saved settings."
        case .stateVerificationFailed:
            return "Attention Assist could not verify its saved settings."
        case .unsupportedStateSchema(let version):
            return "Attention Assist data uses an unsupported format (version \(version))."
        case .invalidPreferences(let reason):
            return "Attention Assist settings are invalid: \(reason)"
        case .unverifiedEvidence(let kind):
            return "Attention Assist did not schedule \(kind.displayName) because its evidence was not verified."
        case .notificationPermissionNotDetermined:
            return "Turn on notifications before enabling Attention Assist."
        case .notificationPermissionDenied:
            return "Attention Assist notifications are disabled in Settings."
        case .notificationPermissionUnavailable:
            return "Notification permission is currently unavailable."
        case .notificationSchedulingFailed(let reason):
            return "Attention Assist could not schedule a notification: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .appGroupUnavailable,
             .stateEncodingFailed,
             .stateDecodingFailed,
             .stateVerificationFailed,
             .unsupportedStateSchema:
            return "Close and reopen The Climb. If the issue continues, contact support."
        case .invalidPreferences:
            return "Review the frequency, quiet hours, and enabled recommendation types."
        case .unverifiedEvidence:
            return "Refresh the underlying protection, rhythm, or Device Activity data and try again."
        case .notificationPermissionNotDetermined:
            return "Use the Attention Assist permission control to choose whether notifications are allowed."
        case .notificationPermissionDenied:
            return "Open Settings, select The Climb, then enable Notifications."
        case .notificationPermissionUnavailable:
            return "Try again after notification services become available."
        case .notificationSchedulingFailed:
            return "Try reconciling Attention Assist again."
        }
    }
}

struct AttentionAssistRuntimeReconciliation: Equatable {
    var evaluation: AttentionAssistEvaluation
    var scheduledRecommendationIDs: [String]
    var retainedRecommendationIDs: [String]
    var cancelledRecommendationIDs: [String]
}

actor AttentionAssistRuntimeService {
    static let appGroupID = "group.com.jaydenlacy.theclimb"

    private static let notificationIdentifierPrefix = "attention-assist."
    private static let threadIdentifier = "attention-assist"
    private static let maximumRecommendationsPerDay = 8
    private static let maximumPendingRecommendations = 16
    private static let maximumDeliveryHistoryRecords = 256
    private static let historyRetention: TimeInterval = 45 * 24 * 60 * 60
    private static let maximumSchedulingHorizon: TimeInterval = 7 * 24 * 60 * 60
    private static let minimumCustomInterval: TimeInterval = 15 * 60

    private let engine: AttentionAssistEvaluating
    private let notificationCenter: UNUserNotificationCenter
    private let store: AttentionAssistRuntimeStore
    private let now: () -> Date

    init(
        engine: AttentionAssistEvaluating = AttentionAssistEngine(),
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults? = UserDefaults(
            suiteName: AttentionAssistRuntimeService.appGroupID
        ),
        now: @escaping () -> Date = Date.init
    ) {
        self.engine = engine
        self.notificationCenter = notificationCenter
        store = AttentionAssistRuntimeStore(defaults: defaults)
        self.now = now
    }

    func preferences() throws -> AttentionAssistPreferences {
        try store.load().preferences
    }

    func deliveryHistory() throws -> [AttentionAssistDeliveryRecord] {
        try store.load().deliveryHistory
    }

    func notificationPermission() async -> AttentionAssistNotificationPermission {
        let settings = await notificationCenter.notificationSettings()
        return Self.permission(from: settings.authorizationStatus)
    }

    /// Call only from a user-initiated opt-in control.
    func requestNotificationPermission() async throws -> AttentionAssistNotificationPermission {
        let permission = await notificationPermission()
        if permission != .notDetermined {
            return permission
        }

        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        } catch {
            throw AttentionAssistRuntimeError.notificationPermissionUnavailable
        }

        let updatedPermission = await notificationPermission()
        if updatedPermission == .unavailable {
            throw AttentionAssistRuntimeError.notificationPermissionUnavailable
        }
        return updatedPermission
    }

    func savePreferences(_ preferences: AttentionAssistPreferences) async throws {
        try Self.validate(preferences)

        if preferences.isEnabled {
            try await requireNotificationPermission()
        }

        var state = try store.load()
        state.preferences = preferences

        if !preferences.isEnabled || preferences.frequency == .off {
            let ownedIdentifiers = await ownedPendingRequests().map(\.identifier)
            notificationCenter.removePendingNotificationRequests(
                withIdentifiers: ownedIdentifiers
            )
            state.pendingNotifications = []
        }

        try store.save(state)
    }

    /// Reconciles all Attention Assist notifications from a complete, current set
    /// of observed signals. Call this on launch after rebuilding local evidence.
    @discardableResult
    func reconcile(
        signals: [AttentionAssistSignal],
        at evaluationDate: Date? = nil
    ) async throws -> AttentionAssistRuntimeReconciliation {
        let date = evaluationDate ?? now()
        var state = try store.load()
        try Self.validate(state.preferences)

        let pendingRequests = await ownedPendingRequests()
        state = Self.settlePendingNotifications(
            in: state,
            systemPendingIdentifiers: Set(pendingRequests.map(\.identifier)),
            at: date
        )
        state.deliveryHistory = Self.prunedHistory(
            state.deliveryHistory,
            at: date
        )

        guard state.preferences.isEnabled,
              state.preferences.frequency != .off else {
            notificationCenter.removePendingNotificationRequests(
                withIdentifiers: pendingRequests.map(\.identifier)
            )
            state.pendingNotifications = []
            try store.save(state)

            return AttentionAssistRuntimeReconciliation(
                evaluation: engine.evaluate(
                    signals: signals,
                    preferences: state.preferences,
                    deliveryHistory: state.deliveryHistory,
                    at: date
                ),
                scheduledRecommendationIDs: [],
                retainedRecommendationIDs: [],
                cancelledRecommendationIDs: pendingRequests.map(\.identifier)
            )
        }

        try await requireNotificationPermission()
        try signals.forEach { try Self.validateEvidence(in: $0) }

        let evaluation = engine.evaluate(
            signals: signals,
            preferences: state.preferences,
            deliveryHistory: state.deliveryHistory,
            at: date
        )
        let candidates = evaluation.candidates
            .filter {
                $0.expiresAt > date
                    && $0.recommendedDeliveryAt < $0.expiresAt
                    && $0.recommendedDeliveryAt.timeIntervalSince(date)
                        <= Self.maximumSchedulingHorizon
            }
            .prefix(Self.maximumPendingRecommendations)

        let systemPendingIdentifiers = Set(pendingRequests.map(\.identifier))
        var desiredIdentifiers = Set<String>()
        var scheduledRecommendationIDs: [String] = []
        var retainedRecommendationIDs: [String] = []
        var nextPendingRecords: [AttentionAssistPendingNotification] = []

        for candidate in candidates {
            let identifier = Self.notificationIdentifier(
                for: candidate.deduplicationKey
            )
            desiredIdentifiers.insert(identifier)

            if systemPendingIdentifiers.contains(identifier) {
                retainedRecommendationIDs.append(candidate.id)
                nextPendingRecords.append(
                    AttentionAssistPendingNotification(
                        notificationIdentifier: identifier,
                        candidate: candidate,
                        scheduledAt: date
                    )
                )
                continue
            }

            do {
                try await notificationCenter.add(
                    Self.notificationRequest(
                        identifier: identifier,
                        candidate: candidate,
                        now: date
                    )
                )
            } catch {
                state.pendingNotifications = Self.mergePendingRecords(
                    existing: state.pendingNotifications,
                    replacements: nextPendingRecords
                )
                try store.save(state)
                throw AttentionAssistRuntimeError.notificationSchedulingFailed(
                    error.localizedDescription
                )
            }

            scheduledRecommendationIDs.append(candidate.id)
            nextPendingRecords.append(
                AttentionAssistPendingNotification(
                    notificationIdentifier: identifier,
                    candidate: candidate,
                    scheduledAt: date
                )
            )
        }

        let obsoleteRequests = pendingRequests.filter {
            !desiredIdentifiers.contains($0.identifier)
        }
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: obsoleteRequests.map(\.identifier)
        )

        state.pendingNotifications = nextPendingRecords
        try store.save(state)

        return AttentionAssistRuntimeReconciliation(
            evaluation: evaluation,
            scheduledRecommendationIDs: scheduledRecommendationIDs,
            retainedRecommendationIDs: retainedRecommendationIDs,
            cancelledRecommendationIDs: obsoleteRequests.map(\.identifier)
        )
    }

    @discardableResult
    func reconcileForLaunch(
        signals: [AttentionAssistSignal],
        at evaluationDate: Date? = nil
    ) async throws -> AttentionAssistRuntimeReconciliation {
        try await reconcile(signals: signals, at: evaluationDate)
    }

    func disable() async throws {
        var state = try store.load()
        state.preferences.isEnabled = false
        state.preferences.frequency = .off
        state.preferences.maximumRecommendationsPerDay = 0

        let identifiers = await ownedPendingRequests().map(\.identifier)
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
        state.pendingNotifications = []
        try store.save(state)
    }

    func clearStoredData() async throws {
        let identifiers = await ownedPendingRequests().map(\.identifier)
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
        try store.clear()
    }

    private func requireNotificationPermission() async throws {
        switch await notificationPermission() {
        case .authorized:
            return
        case .notDetermined:
            throw AttentionAssistRuntimeError.notificationPermissionNotDetermined
        case .denied:
            throw AttentionAssistRuntimeError.notificationPermissionDenied
        case .unavailable:
            throw AttentionAssistRuntimeError.notificationPermissionUnavailable
        }
    }

    private func ownedPendingRequests() async -> [UNNotificationRequest] {
        let requests = await notificationCenter.pendingNotificationRequests()
        return requests.filter {
            $0.identifier.hasPrefix(Self.notificationIdentifierPrefix)
        }
    }
}

struct AttentionAssistSignalSource {
    private let focusStore: FocusSessionDomainStoring
    private let adultRuntime: AdultProtectionRuntimeService
    private let now: () -> Date

    init(
        focusStore: FocusSessionDomainStoring = AppGroupFocusSessionStore(),
        adultRuntime: AdultProtectionRuntimeService = AdultProtectionRuntimeService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.focusStore = focusStore
        self.adultRuntime = adultRuntime
        self.now = now
    }

    func currentSignals() -> [AttentionAssistSignal] {
        let date = now()
        var signals: [AttentionAssistSignal] = []

        if let envelope = try? focusStore.load(),
           envelope.rhythmPause?.isActive(at: date) != true {
            for rhythm in envelope.rhythms where rhythm.isEnabled {
                let evaluation = FocusRhythmEvaluator().evaluate(
                    rhythm,
                    at: date
                )
                guard let next = evaluation.nextOccurrence,
                      next.startsAt > date,
                      next.startsAt.timeIntervalSince(date) <= 15 * 60 else {
                    continue
                }
                signals.append(
                    .focusRhythmStartingSoon(
                        AttentionAssistRhythmStartingSignal(
                            signalID: "rhythm-soon:\(rhythm.id):\(Int(next.startsAt.timeIntervalSince1970))",
                            rhythmReference: rhythm.id,
                            observedAt: date,
                            startsAt: next.startsAt,
                            reminderLeadTime: 15 * 60
                        )
                    )
                )
            }
        }

        if let adultEnvelope = try? adultRuntime.loadState(),
           adultEnvelope.configuration?.isEnabled == true {
            let report = adultRuntime.healthReport()
            let state: AttentionAssistProtectionState
            switch report.status {
            case .fullyProtected:
                state = .fullyProtected
            case .partiallyProtected:
                state = .partiallyProtected
            case .actionRequired:
                state = .actionRequired
            case .off:
                state = .off
            case .unavailable:
                state = .unavailable
            }
            signals.append(
                .protectionNeedsAttention(
                    AttentionAssistProtectionSignal(
                        signalID: "protection-health:\(Int(date.timeIntervalSince1970 / 3_600))",
                        protectionReference: "permanent-protection",
                        observedAt: date,
                        expiresAt: date.addingTimeInterval(12 * 60 * 60),
                        state: state
                    )
                )
            )
        }

        return signals
    }
}

private extension AttentionAssistRuntimeService {
    static func validate(_ preferences: AttentionAssistPreferences) throws {
        guard TimeZone(identifier: preferences.timeZoneIdentifier) != nil else {
            throw AttentionAssistRuntimeError.invalidPreferences(
                "the selected time zone is unavailable"
            )
        }
        guard preferences.quietHours?.isValid ?? true else {
            throw AttentionAssistRuntimeError.invalidPreferences(
                "quiet hours must use valid hours and minutes"
            )
        }
        guard preferences.maximumRecommendationsPerDay >= 0,
              preferences.maximumRecommendationsPerDay
                <= maximumRecommendationsPerDay else {
            throw AttentionAssistRuntimeError.invalidPreferences(
                "daily frequency must be between 0 and \(maximumRecommendationsPerDay)"
            )
        }
        guard preferences.minimumIntervalBetweenRecommendations.isFinite,
              preferences.minimumIntervalBetweenRecommendations >= 0 else {
            throw AttentionAssistRuntimeError.invalidPreferences(
                "the minimum interval must be a finite positive duration"
            )
        }
        guard preferences.cooldownByKind.values.allSatisfy({
            $0.isFinite && $0 >= 0 && $0 <= historyRetention
        }) else {
            throw AttentionAssistRuntimeError.invalidPreferences(
                "recommendation cooldowns must be between 0 and 45 days"
            )
        }

        if preferences.isEnabled {
            guard preferences.frequency != .off else {
                throw AttentionAssistRuntimeError.invalidPreferences(
                    "an enabled assistant must have a notification frequency"
                )
            }
            guard preferences.maximumRecommendationsPerDay > 0 else {
                throw AttentionAssistRuntimeError.invalidPreferences(
                    "an enabled assistant must allow at least one recommendation per day"
                )
            }
            guard preferences.minimumIntervalBetweenRecommendations
                    >= minimumCustomInterval else {
                throw AttentionAssistRuntimeError.invalidPreferences(
                    "recommendations must be at least 15 minutes apart"
                )
            }
            guard !preferences.enabledKinds.isEmpty else {
                throw AttentionAssistRuntimeError.invalidPreferences(
                    "at least one recommendation type must be enabled"
                )
            }
        }
    }

    static func validateEvidence(in signal: AttentionAssistSignal) throws {
        let hasVerifiedEvidence: Bool

        switch signal {
        case .boundaryApproaching:
            hasVerifiedEvidence = true
        case .repeatedDistraction(let evidence):
            hasVerifiedEvidence = evidence.source == .deviceActivity
                && (evidence.quality == .exact
                    || evidence.quality == .thresholdCrossing)
        case .usageAbovePersonalAverage(let evidence):
            hasVerifiedEvidence = evidence.source == .deviceActivity
                && (evidence.quality == .exact
                    || evidence.quality == .aggregated)
                && evidence.personalAverageSampleDays >= 3
        case .missedFocusRhythm:
            hasVerifiedEvidence = true
        case .sleepGoalAtRisk(let evidence):
            hasVerifiedEvidence = evidence.source == .deviceActivity
                && (evidence.quality == .exact
                    || evidence.quality == .aggregated)
        case .devotionalStillOpen,
             .protectionNeedsAttention,
             .focusRhythmStartingSoon:
            hasVerifiedEvidence = true
        }

        guard hasVerifiedEvidence else {
            throw AttentionAssistRuntimeError.unverifiedEvidence(signal.kind)
        }
    }

    static func permission(
        from status: UNAuthorizationStatus
    ) -> AttentionAssistNotificationPermission {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unavailable
        }
    }

    static func notificationRequest(
        identifier: String,
        candidate: AttentionAssistRecommendationCandidate,
        now: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.message
        content.threadIdentifier = threadIdentifier
        content.targetContentIdentifier = candidate.destination.rawValue
        content.userInfo = [
            "attentionAssist": true,
            "recommendationID": candidate.id,
            "kind": candidate.kind.rawValue,
            "destination": candidate.destination.rawValue,
            "evidenceSource": candidate.evidence.source.rawValue
        ]

        switch candidate.priority {
        case .high:
            content.interruptionLevel = .active
            content.relevanceScore = 1
            content.sound = .default
        case .normal:
            content.interruptionLevel = .active
            content.relevanceScore = 0.7
            content.sound = .default
        case .low:
            content.interruptionLevel = .passive
            content.relevanceScore = 0.4
        }

        let interval = max(
            1,
            candidate.recommendedDeliveryAt.timeIntervalSince(now)
        )
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval,
            repeats: false
        )
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
    }

    static func notificationIdentifier(for deduplicationKey: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in deduplicationKey.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return notificationIdentifierPrefix + String(hash, radix: 16)
    }

    static func settlePendingNotifications(
        in state: AttentionAssistRuntimeState,
        systemPendingIdentifiers: Set<String>,
        at date: Date
    ) -> AttentionAssistRuntimeState {
        var updatedState = state
        var retainedPending: [AttentionAssistPendingNotification] = []
        var history = state.deliveryHistory

        for pending in state.pendingNotifications {
            if systemPendingIdentifiers.contains(pending.notificationIdentifier) {
                retainedPending.append(pending)
                continue
            }

            guard pending.candidate.recommendedDeliveryAt <= date else {
                continue
            }
            history.append(
                AttentionAssistDeliveryRecord(
                    recommendationID: pending.candidate.id,
                    deduplicationKey: pending.candidate.deduplicationKey,
                    kind: pending.candidate.kind,
                    deliveredAt: pending.candidate.recommendedDeliveryAt
                )
            )
        }

        updatedState.pendingNotifications = retainedPending
        updatedState.deliveryHistory = prunedHistory(history, at: date)
        return updatedState
    }

    static func prunedHistory(
        _ history: [AttentionAssistDeliveryRecord],
        at date: Date
    ) -> [AttentionAssistDeliveryRecord] {
        let earliestAllowedDate = date.addingTimeInterval(-historyRetention)
        var recordsByKey: [String: AttentionAssistDeliveryRecord] = [:]

        for record in history where record.deliveredAt >= earliestAllowedDate {
            let key = "\(record.deduplicationKey)|\(record.deliveredAt.timeIntervalSince1970)"
            recordsByKey[key] = record
        }

        return recordsByKey.values
            .sorted { $0.deliveredAt > $1.deliveredAt }
            .prefix(maximumDeliveryHistoryRecords)
            .map { $0 }
    }

    static func mergePendingRecords(
        existing: [AttentionAssistPendingNotification],
        replacements: [AttentionAssistPendingNotification]
    ) -> [AttentionAssistPendingNotification] {
        var recordsByIdentifier = Dictionary(
            uniqueKeysWithValues: existing.map {
                ($0.notificationIdentifier, $0)
            }
        )
        for replacement in replacements {
            recordsByIdentifier[replacement.notificationIdentifier] = replacement
        }
        return recordsByIdentifier.values
            .sorted { $0.candidate.recommendedDeliveryAt < $1.candidate.recommendedDeliveryAt }
            .prefix(maximumPendingRecommendations)
            .map { $0 }
    }
}

private struct AttentionAssistPendingNotification: Codable, Equatable {
    var notificationIdentifier: String
    var candidate: AttentionAssistRecommendationCandidate
    var scheduledAt: Date
}

private struct AttentionAssistRuntimeState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var preferences: AttentionAssistPreferences
    var deliveryHistory: [AttentionAssistDeliveryRecord]
    var pendingNotifications: [AttentionAssistPendingNotification]

    static func initial() -> AttentionAssistRuntimeState {
        AttentionAssistRuntimeState(
            schemaVersion: currentSchemaVersion,
            preferences: .recommended(frequency: .off, quietHours: nil),
            deliveryHistory: [],
            pendingNotifications: []
        )
    }
}

private final class AttentionAssistRuntimeStore {
    private static let stateKey = "the-climb.attention-assist-runtime-state.v1"

    private let defaults: UserDefaults?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    func load() throws -> AttentionAssistRuntimeState {
        guard let defaults else {
            throw AttentionAssistRuntimeError.appGroupUnavailable
        }
        guard let data = defaults.data(forKey: Self.stateKey) else {
            return .initial()
        }

        let state: AttentionAssistRuntimeState
        do {
            state = try decoder.decode(AttentionAssistRuntimeState.self, from: data)
        } catch {
            throw AttentionAssistRuntimeError.stateDecodingFailed
        }
        guard state.schemaVersion <= AttentionAssistRuntimeState.currentSchemaVersion else {
            throw AttentionAssistRuntimeError.unsupportedStateSchema(
                state.schemaVersion
            )
        }
        return state
    }

    func save(_ state: AttentionAssistRuntimeState) throws {
        guard let defaults else {
            throw AttentionAssistRuntimeError.appGroupUnavailable
        }

        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw AttentionAssistRuntimeError.stateEncodingFailed
        }
        defaults.set(data, forKey: Self.stateKey)

        guard let persistedData = defaults.data(forKey: Self.stateKey),
              let persistedState = try? decoder.decode(
                AttentionAssistRuntimeState.self,
                from: persistedData
              ),
              persistedState == state else {
            throw AttentionAssistRuntimeError.stateVerificationFailed
        }
    }

    func clear() throws {
        guard let defaults else {
            throw AttentionAssistRuntimeError.appGroupUnavailable
        }
        defaults.removeObject(forKey: Self.stateKey)
        guard defaults.object(forKey: Self.stateKey) == nil else {
            throw AttentionAssistRuntimeError.stateVerificationFailed
        }
    }
}

private extension AttentionAssistRecommendationKind {
    var displayName: String {
        switch self {
        case .boundaryApproaching:
            return "boundary reminder"
        case .repeatedDistraction:
            return "distraction reminder"
        case .usageAbovePersonalAverage:
            return "screen time comparison"
        case .missedFocusRhythm:
            return "focus rhythm reminder"
        case .sleepGoalAtRisk:
            return "sleep goal reminder"
        case .devotionalStillOpen:
            return "devotional reminder"
        case .protectionNeedsAttention:
            return "protection reminder"
        case .focusRhythmStartingSoon:
            return "upcoming focus rhythm reminder"
        }
    }
}
