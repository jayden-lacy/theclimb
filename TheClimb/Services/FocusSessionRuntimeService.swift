import Foundation
#if canImport(DeviceActivity) && os(iOS)
import DeviceActivity
#endif
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
import ManagedSettings
#endif

enum FocusSessionRuntimeError: LocalizedError, Equatable {
    case authorizationRequired
    case authorizationDenied
    case selectionRequired
    case essentialAppsRequired
    case activeSessionAlreadyExists
    case sessionNotFound
    case scheduleFailed
    case persistenceFailed
    case unsupported
    case rhythmLimitReached
    case intentionalExitReasonRequired
    case intentionalExitDelayActive
    case lockedSessionCannotEndEarly
    case breakNotAllowed
    case breakAlreadyActive
    case breakDurationInvalid
    case rhythmPauseInvalid

    var errorDescription: String? {
        switch self {
        case .authorizationRequired:
            "Allow Screen Time access before starting a protected focus session."
        case .authorizationDenied:
            "Screen Time access is denied. You can change this in Settings."
        case .selectionRequired:
            "Choose at least one app, category, or website to block."
        case .essentialAppsRequired:
            "Choose the apps that should remain available first."
        case .activeSessionAlreadyExists:
            "End the current focus session before starting another."
        case .sessionNotFound:
            "The active focus session could not be found."
        case .scheduleFailed:
            "The focus schedule could not be registered with Screen Time."
        case .persistenceFailed:
            "The focus session could not be saved."
        case .unsupported:
            "Screen Time protection is not available on this device."
        case .rhythmLimitReached:
            "This build supports up to two Focus Rhythms."
        case .intentionalExitReasonRequired:
            "Name why you need to leave this session before ending it."
        case .intentionalExitDelayActive:
            "The intentional exit pause is still active."
        case .lockedSessionCannotEndEarly:
            "Locked sessions remain protected until their scheduled end."
        case .breakNotAllowed:
            "This session mode does not allow an unplanned break."
        case .breakAlreadyActive:
            "A break is already active for this session."
        case .breakDurationInvalid:
            "Choose a break between 1 and 10 minutes that ends before the session."
        case .rhythmPauseInvalid:
            "Choose a rhythm pause that ends in the future."
        }
    }
}

enum FocusEarlyExitResolution: Equatable {
    case pending(FocusEarlyExitRequest)
    case ended(FocusSession)
}

enum FocusSelectionMode: String, Codable {
    case blockSelected
    case allowEssentialApps
}

struct ScreenTimeScheduledActivityConfiguration: Codable, Equatable {
    var activityName: String
    var selectionMode: FocusSelectionMode
    var blocksAdultWebContent: Bool
    var updatedAt: Date
}

enum ScreenTimeScheduledActivityConfigurationStore {
    static let appGroupID = AppGroupScreenTimePolicyStore.appGroupID
    static let essentialSelectionKey = "the-climb.essential-apps-selection.v1"
    private static let configurationPrefix = "the-climb.scheduled-activity."
    private static let boundaryNamesPrefix = "the-climb.boundary-activity-names."

    static func save(
        _ configuration: ScreenTimeScheduledActivityConfiguration,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) {
        guard let defaults,
              let data = try? JSONEncoder.screenTime.encode(configuration) else {
            return
        }
        defaults.set(data, forKey: key(for: configuration.activityName))
    }

    static func remove(
        activityName: String,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) {
        defaults?.removeObject(forKey: key(for: activityName))
    }

    static func load(
        activityName: String,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) -> ScreenTimeScheduledActivityConfiguration? {
        guard let data = defaults?.data(forKey: key(for: activityName)) else {
            return nil
        }
        return try? JSONDecoder.screenTime.decode(
            ScreenTimeScheduledActivityConfiguration.self,
            from: data
        )
    }

    static func saveBoundaryActivityNames(
        _ names: [String],
        boundaryID: String,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) {
        defaults?.set(names, forKey: boundaryNamesPrefix + boundaryID)
    }

    static func boundaryActivityNames(
        boundaryID: String,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) -> [String] {
        defaults?.stringArray(forKey: boundaryNamesPrefix + boundaryID) ?? []
    }

    static func removeBoundaryActivityNames(
        boundaryID: String,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) {
        defaults?.removeObject(forKey: boundaryNamesPrefix + boundaryID)
    }

    private static func key(for activityName: String) -> String {
        configurationPrefix + activityName
    }
}

private extension JSONEncoder {
    static var screenTime: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

private extension JSONDecoder {
    static var screenTime: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

#if canImport(FamilyControls) && os(iOS)
enum EssentialAppsActivitySelectionStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: ScreenTimeScheduledActivityConfigurationStore.appGroupID)
    }

    @available(iOS 16.0, *)
    static func loadSelection() -> FamilyActivitySelection {
        guard let data = defaults?.data(
            forKey: ScreenTimeScheduledActivityConfigurationStore.essentialSelectionKey
        ) else {
            return FamilyActivitySelection()
        }
        return (try? JSONDecoder().decode(FamilyActivitySelection.self, from: data))
            ?? FamilyActivitySelection()
    }

    @available(iOS 16.0, *)
    static func saveSelection(_ selection: FamilyActivitySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults?.set(
            data,
            forKey: ScreenTimeScheduledActivityConfigurationStore.essentialSelectionKey
        )
    }
}
#endif

final class FocusSessionRuntimeService {
    private let authorizationProvider: ScreenTimeAuthorizationProviding
    private let policyCoordinator: ScreenTimePolicyCoordinator
    private let domainStore: FocusSessionDomainStoring
    private let sessionService: FocusSessionService
    private let now: () -> Date

    init(
        authorizationProvider: ScreenTimeAuthorizationProviding = AppleScreenTimeAuthorizationProvider(),
        policyCoordinator: ScreenTimePolicyCoordinator = ScreenTimePolicyCoordinator(),
        domainStore: FocusSessionDomainStoring = AppGroupFocusSessionStore(),
        sessionService: FocusSessionService = FocusSessionService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.authorizationProvider = authorizationProvider
        self.policyCoordinator = policyCoordinator
        self.domainStore = domainStore
        self.sessionService = sessionService
        self.now = now
    }

    func loadState() throws -> FocusSessionDomainEnvelope {
        try domainStore.load()
    }

    func recordProtectedMission(
        missionID: String,
        startedAt: Date,
        plannedEndAt: Date,
        endedAt: Date,
        outcome: ProtectedTimeOutcome,
        enforcementEvidence: ProtectionEnforcementEvidence
    ) throws {
        guard !missionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              endedAt > startedAt,
              plannedEndAt > startedAt else {
            throw FocusSessionRuntimeError.persistenceFailed
        }
        var envelope = try domainStore.load()
        let sourceID = FocusSourceID(rawValue: "mission:\(missionID)")
        let record = ProtectedTimeRecord(
            id: "mission:\(missionID):\(Int(startedAt.timeIntervalSince1970))",
            sourceID: sourceID,
            sourceKind: .mission,
            purpose: .mission,
            strictness: .intentional,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedDuration: plannedEndAt.timeIntervalSince(startedAt),
            outcome: outcome,
            breakSegments: [],
            enforcementEvidence: enforcementEvidence
        )
        envelope.history = ProtectedTimeHistoryService().adding(
            record,
            to: envelope.history
        )
        envelope.updatedAt = now()
        try domainStore.save(envelope)
    }

    @discardableResult
    func reconcileExpiredSessions(at date: Date? = nil) throws -> FocusSessionDomainEnvelope {
        let reconciliationDate = date ?? now()
        var envelope = try domainStore.load()
        var didMutate = false
        for index in envelope.intentionalBreaks.indices
        where envelope.intentionalBreaks[index].state == .active
            && envelope.intentionalBreaks[index].endsAt <= reconciliationDate {
            envelope.intentionalBreaks[index].state = .ended
            envelope.intentionalBreaks[index].updatedAt = reconciliationDate
            policyCoordinator.removePolicy(
                id: "intentional-break:\(envelope.intentionalBreaks[index].id)"
            )
            didMutate = true
        }
        let expired = envelope.activeSessions.filter {
            $0.isActive && $0.plannedEndAt <= reconciliationDate
        }
        guard !expired.isEmpty || didMutate else { return envelope }

        for session in expired {
            guard let ended = try? sessionService.end(
                session,
                outcome: .completed,
                at: session.plannedEndAt
            ),
            let record = try? sessionService.record(
                for: ended,
                breakSegments: breakSegments(
                    for: session,
                    in: envelope.intentionalBreaks,
                    endingAt: session.plannedEndAt
                ),
                enforcementEvidence: enforcementEvidence(for: session)
            ) else {
                continue
            }
            envelope.activeSessions.removeAll { $0.id == session.id }
            envelope.earlyExitRequests.removeAll { $0.sessionID == session.id }
            envelope.history = ProtectedTimeHistoryService().adding(
                record,
                to: envelope.history
            )
            policyCoordinator.removePolicy(id: session.sourceID.rawValue)
        }
        envelope.updatedAt = reconciliationDate
        try domainStore.save(envelope)
        return envelope
    }

    func start(_ request: FocusSessionRequest) async throws -> FocusSession {
        var envelope = try domainStore.load()
        guard !envelope.activeSessions.contains(where: \.isActive) else {
            throw FocusSessionRuntimeError.activeSessionAlreadyExists
        }

        let authorization = await authorizationProvider.requestAuthorization()
        try validateAuthorization(authorization)
        let selectionMode: FocusSelectionMode = request.essentialAppsReference == nil
            ? .blockSelected
            : .allowEssentialApps
        try validateSelection(
            mode: selectionMode,
            blocksAdultWebContent: request.blocksAdultWebContent
        )

        let session = try sessionService.start(request, at: now())
        ScreenTimeScheduledActivityConfigurationStore.save(
            ScreenTimeScheduledActivityConfiguration(
                activityName: GeneralFocusDeviceActivityScheduler.activityNameRawValue,
                selectionMode: selectionMode,
                blocksAdultWebContent: request.blocksAdultWebContent,
                updatedAt: now()
            )
        )
        guard GeneralFocusDeviceActivityScheduler.start(until: session.plannedEndAt) else {
            ScreenTimeScheduledActivityConfigurationStore.remove(
                activityName: GeneralFocusDeviceActivityScheduler.activityNameRawValue
            )
            throw FocusSessionRuntimeError.scheduleFailed
        }

        do {
            try applyImmediateProtection(
                selectionMode: selectionMode,
                blocksAdultWebContent: request.blocksAdultWebContent
            )
            envelope.activeSessions.append(session)
            envelope.updatedAt = now()
            try domainStore.save(envelope)
            policyCoordinator.upsert(session.protectionPolicy)
            ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat()
            return session
        } catch {
            clearImmediateProtection()
            GeneralFocusDeviceActivityScheduler.stop()
            ScreenTimeScheduledActivityConfigurationStore.remove(
                activityName: GeneralFocusDeviceActivityScheduler.activityNameRawValue
            )
            if let runtimeError = error as? FocusSessionRuntimeError {
                throw runtimeError
            }
            throw FocusSessionRuntimeError.persistenceFailed
        }
    }

    @discardableResult
    func end(
        sessionID: String,
        outcome: FocusSessionOutcome
    ) throws -> FocusSession {
        let envelope = try domainStore.load()
        guard let session = envelope.activeSessions.first(where: {
            $0.id == sessionID && $0.isActive
        }) else {
            throw FocusSessionRuntimeError.sessionNotFound
        }

        if now() < session.plannedEndAt {
            guard session.strictness == .flexible, outcome != .completed else {
                throw session.strictness >= .locked
                    ? FocusSessionRuntimeError.lockedSessionCannotEndEarly
                    : FocusSessionRuntimeError.intentionalExitReasonRequired
            }
        }
        return try finish(
            sessionID: sessionID,
            outcome: outcome,
            earlyExitReason: nil
        )
    }

    func requestEarlyExit(
        sessionID: String,
        reason: String?
    ) throws -> FocusEarlyExitResolution {
        var envelope = try domainStore.load()
        guard let session = envelope.activeSessions.first(where: {
            $0.id == sessionID && $0.isActive
        }) else {
            throw FocusSessionRuntimeError.sessionNotFound
        }

        let requestDate = now()
        guard requestDate < session.plannedEndAt else {
            return .ended(
                try finish(
                    sessionID: sessionID,
                    outcome: .completed,
                    earlyExitReason: nil
                )
            )
        }

        switch session.strictness {
        case .flexible:
            return .ended(
                try finish(
                    sessionID: sessionID,
                    outcome: .endedEarly,
                    earlyExitReason: reason
                )
            )
        case .locked, .accountabilityLocked:
            throw FocusSessionRuntimeError.lockedSessionCannotEndEarly
        case .intentional:
            let normalizedReason = reason?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalizedReason, !normalizedReason.isEmpty else {
                throw FocusSessionRuntimeError.intentionalExitReasonRequired
            }

            if let existing = envelope.earlyExitRequests.first(where: {
                $0.sessionID == sessionID && $0.state == .pending
            }) {
                guard existing.canExecute(at: requestDate) else {
                    return .pending(existing)
                }
                return .ended(
                    try finish(
                        sessionID: sessionID,
                        outcome: .endedEarly,
                        earlyExitReason: existing.reason
                    )
                )
            }

            let request = FocusEarlyExitRequest(
                id: UUID().uuidString,
                sessionID: sessionID,
                reason: normalizedReason,
                state: .pending,
                requestedAt: requestDate,
                earliestExecutionAt: requestDate.addingTimeInterval(5),
                updatedAt: requestDate
            )
            envelope.earlyExitRequests.append(request)
            envelope.updatedAt = requestDate
            try domainStore.save(envelope)
            return .pending(request)
        }
    }

    func startIntentionalBreak(
        sessionID: String,
        duration: TimeInterval,
        reason: String?
    ) throws -> IntentionalBreak {
        var envelope = try domainStore.load()
        guard let session = envelope.activeSessions.first(where: {
            $0.id == sessionID && $0.isActive
        }) else {
            throw FocusSessionRuntimeError.sessionNotFound
        }
        guard session.strictness == .flexible || session.strictness == .intentional else {
            throw FocusSessionRuntimeError.breakNotAllowed
        }

        let breakStart = now()
        guard IntentionalBreakService().activeBreak(
            for: session.sourceID,
            in: envelope.intentionalBreaks,
            at: breakStart
        ) == nil else {
            throw FocusSessionRuntimeError.breakAlreadyActive
        }
        let remaining = session.plannedEndAt.timeIntervalSince(breakStart)
        guard duration >= 60,
              duration <= 10 * 60,
              duration < remaining - 30 else {
            throw FocusSessionRuntimeError.breakDurationInvalid
        }
        if session.strictness == .intentional {
            let normalizedReason = reason?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedReason?.isEmpty == false else {
                throw FocusSessionRuntimeError.intentionalExitReasonRequired
            }
        }

        let intentionalBreak = try IntentionalBreakService().create(
            for: session.sourceID,
            duration: duration,
            reason: reason,
            at: breakStart
        )
        guard let configuration = ScreenTimeScheduledActivityConfigurationStore.load(
            activityName: GeneralFocusDeviceActivityScheduler.activityNameRawValue
        ) else {
            throw FocusSessionRuntimeError.persistenceFailed
        }
        guard GeneralFocusDeviceActivityScheduler.start(
            from: intentionalBreak.endsAt,
            until: session.plannedEndAt
        ) else {
            throw FocusSessionRuntimeError.scheduleFailed
        }

        envelope.intentionalBreaks.append(intentionalBreak)
        envelope.updatedAt = breakStart
        do {
            try domainStore.save(envelope)
            clearImmediateProtection()
            policyCoordinator.upsert(intentionalBreak.temporaryExceptionPolicy)
            ScreenTimeScheduledActivityConfigurationStore.save(configuration)
            ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat()
            return intentionalBreak
        } catch {
            _ = GeneralFocusDeviceActivityScheduler.start(until: session.plannedEndAt)
            try? applyImmediateProtection(
                selectionMode: configuration.selectionMode,
                blocksAdultWebContent: configuration.blocksAdultWebContent
            )
            throw FocusSessionRuntimeError.persistenceFailed
        }
    }

    func endIntentionalBreak(
        breakID: String,
        sessionID: String
    ) throws -> IntentionalBreak {
        var envelope = try domainStore.load()
        guard let session = envelope.activeSessions.first(where: {
            $0.id == sessionID && $0.isActive
        }),
        let breakIndex = envelope.intentionalBreaks.firstIndex(where: {
            $0.id == breakID && $0.targetSourceID == session.sourceID
        }) else {
            throw FocusSessionRuntimeError.sessionNotFound
        }
        guard let configuration = ScreenTimeScheduledActivityConfigurationStore.load(
            activityName: GeneralFocusDeviceActivityScheduler.activityNameRawValue
        ) else {
            throw FocusSessionRuntimeError.persistenceFailed
        }

        let endedBreak = try IntentionalBreakService().end(
            envelope.intentionalBreaks[breakIndex],
            at: now()
        )
        envelope.intentionalBreaks[breakIndex] = endedBreak
        envelope.updatedAt = now()
        try domainStore.save(envelope)

        try applyImmediateProtection(
            selectionMode: configuration.selectionMode,
            blocksAdultWebContent: configuration.blocksAdultWebContent
        )
        guard GeneralFocusDeviceActivityScheduler.start(until: session.plannedEndAt) else {
            clearImmediateProtection()
            throw FocusSessionRuntimeError.scheduleFailed
        }
        policyCoordinator.removePolicy(id: "intentional-break:\(breakID)")
        ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat()
        return endedBreak
    }

    private func finish(
        sessionID: String,
        outcome: FocusSessionOutcome,
        earlyExitReason: String?
    ) throws -> FocusSession {
        var envelope = try domainStore.load()
        guard let session = envelope.activeSessions.first(where: {
            $0.id == sessionID && $0.isActive
        }) else {
            throw FocusSessionRuntimeError.sessionNotFound
        }
        let endingDate = now()
        let ended = try sessionService.end(
            session,
            outcome: outcome,
            earlyExitReason: earlyExitReason,
            at: endingDate
        )
        let record = try sessionService.record(
            for: ended,
            breakSegments: breakSegments(
                for: session,
                in: envelope.intentionalBreaks,
                endingAt: endingDate
            ),
            enforcementEvidence: enforcementEvidence(for: session)
        )
        envelope.activeSessions.removeAll { $0.id == sessionID }
        envelope.earlyExitRequests.removeAll { $0.sessionID == sessionID }
        let sessionBreaks = envelope.intentionalBreaks.filter {
            $0.targetSourceID == session.sourceID
        }
        envelope.intentionalBreaks = envelope.intentionalBreaks.map { item in
            guard item.targetSourceID == session.sourceID,
                  item.state == .active else {
                return item
            }
            var endedItem = item
            endedItem.state = .ended
            endedItem.endsAt = min(item.endsAt, endingDate)
            endedItem.updatedAt = endingDate
            return endedItem
        }
        envelope.history = ProtectedTimeHistoryService().adding(
            record,
            to: envelope.history
        )
        envelope.updatedAt = now()
        try domainStore.save(envelope)

        clearImmediateProtection()
        GeneralFocusDeviceActivityScheduler.stop()
        ScreenTimeScheduledActivityConfigurationStore.remove(
            activityName: GeneralFocusDeviceActivityScheduler.activityNameRawValue
        )
        policyCoordinator.removePolicy(id: session.sourceID.rawValue)
        sessionBreaks.forEach {
            policyCoordinator.removePolicy(id: "intentional-break:\($0.id)")
        }
        ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat()
        return ended
    }

    func saveRhythm(_ rhythm: FocusRhythm) throws {
        try validateAuthorization(authorizationProvider.currentStatus())
        let selectionMode: FocusSelectionMode = rhythm.essentialAppsReference == nil
            ? .blockSelected
            : .allowEssentialApps
        try validateSelection(
            mode: selectionMode,
            blocksAdultWebContent: rhythm.blocksAdultWebContent
        )

        var envelope = try domainStore.load()
        let existingRhythmCount = envelope.rhythms.filter { $0.id != rhythm.id }.count
        guard existingRhythmCount < 2 else {
            throw FocusSessionRuntimeError.rhythmLimitReached
        }

        let isPaused = envelope.rhythmPause?.isActive(at: now()) == true
        if !isPaused {
            try FocusRhythmDeviceActivityScheduler.schedule(rhythm)
        }
        envelope.rhythms.removeAll { $0.id == rhythm.id }
        envelope.rhythms.append(rhythm)
        envelope.updatedAt = now()
        do {
            try domainStore.save(envelope)
        } catch {
            if !isPaused {
                FocusRhythmDeviceActivityScheduler.stop(rhythmID: rhythm.id)
            }
            throw FocusSessionRuntimeError.persistenceFailed
        }
    }

    func removeRhythm(id: String) throws {
        var envelope = try domainStore.load()
        FocusRhythmDeviceActivityScheduler.stop(rhythmID: id)
        envelope.rhythms.removeAll { $0.id == id }
        envelope.updatedAt = now()
        try domainStore.save(envelope)
    }

    @discardableResult
    func pauseRhythms(
        until resumesAt: Date,
        reason: FocusRhythmPauseReason
    ) throws -> FocusSessionDomainEnvelope {
        let date = now()
        guard resumesAt > date else {
            throw FocusSessionRuntimeError.rhythmPauseInvalid
        }

        var envelope = try domainStore.load()
        let previousPause = envelope.rhythmPause
        envelope.rhythmPause = FocusRhythmPause(
            pausedAt: date,
            resumesAt: resumesAt,
            reason: reason
        )
        envelope.updatedAt = date
        do {
            try domainStore.save(envelope)
            for rhythm in envelope.rhythms {
                FocusRhythmDeviceActivityScheduler.stop(rhythmID: rhythm.id)
                policyCoordinator.removePolicy(id: rhythm.sourceID.rawValue)
            }
            return envelope
        } catch {
            envelope.rhythmPause = previousPause
            throw FocusSessionRuntimeError.persistenceFailed
        }
    }

    @discardableResult
    func resumeRhythms() throws -> FocusSessionDomainEnvelope {
        var envelope = try domainStore.load()
        let previousPause = envelope.rhythmPause
        do {
            for rhythm in envelope.rhythms where rhythm.isEnabled {
                try FocusRhythmDeviceActivityScheduler.schedule(rhythm)
            }
            envelope.rhythmPause = nil
            envelope.updatedAt = now()
            try domainStore.save(envelope)
            try refreshRhythmPolicies(using: envelope, at: now())
            return envelope
        } catch {
            for rhythm in envelope.rhythms {
                FocusRhythmDeviceActivityScheduler.stop(rhythmID: rhythm.id)
            }
            envelope.rhythmPause = previousPause
            throw error
        }
    }

    @discardableResult
    func resumeRhythmsIfPauseExpired(
        at date: Date? = nil
    ) throws -> FocusSessionDomainEnvelope {
        let evaluationDate = date ?? now()
        let envelope = try domainStore.load()
        guard let pause = envelope.rhythmPause,
              !pause.isActive(at: evaluationDate) else {
            return envelope
        }
        return try resumeRhythms()
    }

    func saveBoundary(_ boundary: AppBoundary) throws {
        try validateAuthorization(authorizationProvider.currentStatus())
        guard boundary.essentialAppsReference == nil else {
            throw FocusSessionRuntimeError.unsupported
        }
        let selectionMode = FocusSelectionMode.blockSelected
        try validateSelection(
            mode: selectionMode,
            blocksAdultWebContent: boundary.blocksAdultWebContent
        )

        var envelope = try domainStore.load()
        guard envelope.boundaries.filter({ $0.id != boundary.id }).count < 3 else {
            throw FocusSessionRuntimeError.scheduleFailed
        }
        try AppBoundaryDeviceActivityScheduler.schedule(boundary)
        envelope.boundaries.removeAll { $0.id == boundary.id }
        envelope.boundaries.append(boundary)
        envelope.updatedAt = now()
        do {
            try domainStore.save(envelope)
        } catch {
            AppBoundaryDeviceActivityScheduler.stop(boundaryID: boundary.id)
            throw FocusSessionRuntimeError.persistenceFailed
        }
    }

    func removeBoundary(id: String) throws {
        var envelope = try domainStore.load()
        AppBoundaryDeviceActivityScheduler.stop(boundaryID: id)
        envelope.boundaries.removeAll { $0.id == id }
        envelope.updatedAt = now()
        try domainStore.save(envelope)
        policyCoordinator.removePolicy(id: FocusSourceID.boundary(id).rawValue)
    }

    func refreshRhythmPolicies(at date: Date? = nil) throws {
        let evaluationDate = date ?? now()
        let envelope = try domainStore.load()
        try refreshRhythmPolicies(using: envelope, at: evaluationDate)
    }

    private func refreshRhythmPolicies(
        using envelope: FocusSessionDomainEnvelope,
        at evaluationDate: Date
    ) throws {
        if envelope.rhythmPause?.isActive(at: evaluationDate) == true {
            for rhythm in envelope.rhythms {
                policyCoordinator.removePolicy(id: rhythm.sourceID.rawValue)
            }
            return
        }
        for rhythm in envelope.rhythms {
            let evaluation = FocusRhythmEvaluator().evaluate(rhythm, at: evaluationDate)
            if let active = evaluation.activeOccurrence {
                policyCoordinator.upsert(
                    FocusRhythmEvaluator().policy(for: rhythm, occurrence: active)
                )
            } else {
                policyCoordinator.removePolicy(id: rhythm.sourceID.rawValue)
            }
        }
    }

    private func breakSegments(
        for session: FocusSession,
        in breaks: [IntentionalBreak],
        endingAt: Date
    ) -> [ProtectedTimeBreakSegment] {
        breaks.compactMap { item in
            guard item.targetSourceID == session.sourceID,
                  item.state != .cancelled,
                  item.startsAt < endingAt else {
                return nil
            }
            var segment = item.protectedTimeSegment
            segment.endsAt = min(item.endsAt, endingAt)
            return segment.endsAt > segment.startsAt ? segment : nil
        }
    }

    private func validateAuthorization(
        _ authorization: ScreenTimeAuthorizationState
    ) throws {
        switch authorization {
        case .approved, .approvedWithDataAccess:
            return
        case .notDetermined:
            throw FocusSessionRuntimeError.authorizationRequired
        case .denied:
            throw FocusSessionRuntimeError.authorizationDenied
        case .unsupported:
            throw FocusSessionRuntimeError.unsupported
        }
    }

    private func enforcementEvidence(
        for session: FocusSession
    ) -> ProtectionEnforcementEvidence {
        guard let heartbeat = ScreenTimeProtectionHealthStore.enforcementHeartbeat(),
              heartbeat >= session.startedAt else {
            return .policyRequested
        }
        return .policyConfirmed
    }

    private func validateSelection(
        mode: FocusSelectionMode,
        blocksAdultWebContent: Bool
    ) throws {
#if canImport(FamilyControls) && os(iOS)
        guard #available(iOS 16.0, *) else {
            throw FocusSessionRuntimeError.unsupported
        }
        switch mode {
        case .blockSelected:
            let selection = ScreenTimeActivitySelectionStore.loadSelection()
            guard selection.hasShieldableContent
                    || blocksAdultWebContent
                    || !PurityProtectionPreferenceStore.protectedDomainStrings.isEmpty else {
                throw FocusSessionRuntimeError.selectionRequired
            }
        case .allowEssentialApps:
            let selection = EssentialAppsActivitySelectionStore.loadSelection()
            guard !selection.applicationTokens.isEmpty else {
                throw FocusSessionRuntimeError.essentialAppsRequired
            }
        }
#else
        throw FocusSessionRuntimeError.unsupported
#endif
    }

    private func applyImmediateProtection(
        selectionMode: FocusSelectionMode,
        blocksAdultWebContent: Bool
    ) throws {
#if canImport(FamilyControls) && os(iOS)
        guard #available(iOS 16.0, *) else {
            throw FocusSessionRuntimeError.unsupported
        }
        let store = ManagedSettingsStore(
            named: ManagedSettingsStore.Name("TheClimbFocusSession")
        )
        store.clearAllSettings()
        let purityDomains = Set(
            PurityProtectionPreferenceStore.protectedDomainStrings.map {
                WebDomain(domain: $0)
            }
        )

        switch selectionMode {
        case .blockSelected:
            let selection = ScreenTimeActivitySelectionStore.loadSelection()
            let protectedWebDomains = selection.webDomains.union(purityDomains)
            store.shield.applications = selection.applicationTokens.isEmpty
                ? nil
                : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty
                ? nil
                : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens.isEmpty
                ? nil
                : selection.webDomainTokens
            store.webContent.blockedByFilter = blocksAdultWebContent
                ? .auto(protectedWebDomains)
                : (protectedWebDomains.isEmpty ? nil : .specific(protectedWebDomains))
        case .allowEssentialApps:
            let essentials = EssentialAppsActivitySelectionStore.loadSelection()
            store.shield.applicationCategories = .all(except: essentials.applicationTokens)
            store.webContent.blockedByFilter = blocksAdultWebContent
                ? .auto(purityDomains)
                : (purityDomains.isEmpty ? nil : .specific(purityDomains))
        }
#else
        throw FocusSessionRuntimeError.unsupported
#endif
    }

    private func clearImmediateProtection() {
#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            ManagedSettingsStore(
                named: ManagedSettingsStore.Name("TheClimbFocusSession")
            ).clearAllSettings()
        }
#endif
    }
}

#if canImport(DeviceActivity) && os(iOS)
enum GeneralFocusDeviceActivityScheduler {
    static let activityNameRawValue = "the-climb.focus-session"
    private static let activityName = DeviceActivityName(activityNameRawValue)

    static func start(until endsAt: Date) -> Bool {
        start(from: Date(), until: endsAt)
    }

    static func start(from startsAt: Date, until endsAt: Date) -> Bool {
        guard #available(iOS 16.0, *),
              startsAt >= Date().addingTimeInterval(-2),
              endsAt > startsAt.addingTimeInterval(30) else {
            return false
        }
        let calendar = Calendar.current
        var start = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: startsAt
        )
        var end = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: endsAt
        )
        start.calendar = calendar
        end.calendar = calendar
        start.timeZone = .current
        end.timeZone = .current

        let center = DeviceActivityCenter()
        center.stopMonitoring([activityName])
        do {
            try center.startMonitoring(
                activityName,
                during: DeviceActivitySchedule(
                    intervalStart: start,
                    intervalEnd: end,
                    repeats: false
                )
            )
            return true
        } catch {
            center.stopMonitoring([activityName])
            return false
        }
    }

    static func stop() {
        guard #available(iOS 16.0, *) else { return }
        DeviceActivityCenter().stopMonitoring([activityName])
    }
}

enum FocusRhythmDeviceActivityScheduler {
    private static let activityPrefix = "the-climb.rhythm."

    static func schedule(_ rhythm: FocusRhythm) throws {
        guard #available(iOS 16.0, *), rhythm.isEnabled else {
            stop(rhythmID: rhythm.id)
            return
        }
        guard !rhythm.weekdays.isEmpty else {
            throw FocusSessionRuntimeError.scheduleFailed
        }

        stop(rhythmID: rhythm.id)
        let center = DeviceActivityCenter()
        var configuredNames: [DeviceActivityName] = []

        do {
            for weekday in rhythm.weekdays.sorted() {
                let name = activityName(rhythmID: rhythm.id, weekday: weekday)
                let configuration = ScreenTimeScheduledActivityConfiguration(
                    activityName: name.rawValue,
                    selectionMode: rhythm.essentialAppsReference == nil
                        ? .blockSelected
                        : .allowEssentialApps,
                    blocksAdultWebContent: rhythm.blocksAdultWebContent,
                    updatedAt: Date()
                )
                ScreenTimeScheduledActivityConfigurationStore.save(configuration)
                configuredNames.append(name)
                let schedule = DeviceActivitySchedule(
                    intervalStart: scheduleComponents(
                        weekday: weekday.calendarWeekday,
                        hour: rhythm.startTime.hour,
                        minute: rhythm.startTime.minute,
                        timeZoneIdentifier: rhythm.timeZoneIdentifier
                    ),
                    intervalEnd: scheduleComponents(
                        weekday: rhythm.crossesMidnight
                            ? weekday.next.calendarWeekday
                            : weekday.calendarWeekday,
                        hour: rhythm.endTime.hour,
                        minute: rhythm.endTime.minute,
                        timeZoneIdentifier: rhythm.timeZoneIdentifier
                    ),
                    repeats: true,
                    warningTime: DateComponents(minute: 5)
                )
                try center.startMonitoring(name, during: schedule)
            }
        } catch {
            center.stopMonitoring(configuredNames)
            for name in configuredNames {
                ScreenTimeScheduledActivityConfigurationStore.remove(
                    activityName: name.rawValue
                )
            }
            throw FocusSessionRuntimeError.scheduleFailed
        }
    }

    static func stop(rhythmID: String) {
        guard #available(iOS 16.0, *) else { return }
        let names = Weekday.allCases.map {
            activityName(rhythmID: rhythmID, weekday: $0)
        }
        DeviceActivityCenter().stopMonitoring(names)
        for name in names {
            ScreenTimeScheduledActivityConfigurationStore.remove(
                activityName: name.rawValue
            )
        }
    }

    private static func activityName(
        rhythmID: String,
        weekday: Weekday
    ) -> DeviceActivityName {
        DeviceActivityName("\(activityPrefix)\(rhythmID).\(weekday.rawValue)")
    }

    private static func scheduleComponents(
        weekday: Int,
        hour: Int,
        minute: Int,
        timeZoneIdentifier: String
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        return components
    }
}

enum AppBoundaryDeviceActivityScheduler {
    private static let activityPrefix = "the-climb.boundary."
    private static let thresholdEvent = DeviceActivityEvent.Name(
        "the-climb.boundary.limit"
    )

    static func schedule(_ boundary: AppBoundary) throws {
        guard #available(iOS 16.0, *), boundary.isEnabled else {
            stop(boundaryID: boundary.id)
            return
        }
        guard !boundary.schedules.isEmpty else {
            throw FocusSessionRuntimeError.scheduleFailed
        }

        stop(boundaryID: boundary.id)
        let center = DeviceActivityCenter()
        var configuredNames: [DeviceActivityName] = []

        do {
            for schedule in boundary.schedules where schedule.isEnabled {
                let scheduleDescriptors = descriptors(
                    boundary: boundary,
                    schedule: schedule
                )
                for descriptor in scheduleDescriptors {
                    let configuration = ScreenTimeScheduledActivityConfiguration(
                        activityName: descriptor.name.rawValue,
                        selectionMode: boundary.essentialAppsReference == nil
                            ? .blockSelected
                            : .allowEssentialApps,
                        blocksAdultWebContent: boundary.blocksAdultWebContent,
                        updatedAt: Date()
                    )
                    ScreenTimeScheduledActivityConfigurationStore.save(configuration)
                    configuredNames.append(descriptor.name)

                    let selection = ScreenTimeActivitySelectionStore.loadSelection()
                    let threshold = DateComponents(
                        second: max(Int(schedule.allowedDuration.rounded()), 1)
                    )
                    let event: DeviceActivityEvent
                    if #available(iOS 17.4, *) {
                        event = DeviceActivityEvent(
                            applications: selection.applicationTokens,
                            categories: selection.categoryTokens,
                            webDomains: selection.webDomainTokens,
                            threshold: threshold,
                            includesPastActivity: false
                        )
                    } else {
                        event = DeviceActivityEvent(
                            applications: selection.applicationTokens,
                            categories: selection.categoryTokens,
                            webDomains: selection.webDomainTokens,
                            threshold: threshold
                        )
                    }
                    try center.startMonitoring(
                        descriptor.name,
                        during: descriptor.schedule,
                        events: [thresholdEvent: event]
                    )
                }
            }
            ScreenTimeScheduledActivityConfigurationStore.saveBoundaryActivityNames(
                configuredNames.map(\.rawValue),
                boundaryID: boundary.id
            )
        } catch {
            center.stopMonitoring(configuredNames)
            configuredNames.forEach {
                ScreenTimeScheduledActivityConfigurationStore.remove(
                    activityName: $0.rawValue
                )
            }
            throw FocusSessionRuntimeError.scheduleFailed
        }
    }

    static func stop(boundaryID: String) {
        guard #available(iOS 16.0, *) else { return }
        let names = ScreenTimeScheduledActivityConfigurationStore
            .boundaryActivityNames(boundaryID: boundaryID)
            .map { DeviceActivityName($0) }
        DeviceActivityCenter().stopMonitoring(names)
        names.forEach {
            ScreenTimeScheduledActivityConfigurationStore.remove(
                activityName: $0.rawValue
            )
            ManagedSettingsStore(
                named: ManagedSettingsStore.Name(
                    storeName(for: $0.rawValue)
                )
            ).clearAllSettings()
        }
        ScreenTimeScheduledActivityConfigurationStore.removeBoundaryActivityNames(
            boundaryID: boundaryID
        )
    }

    private static func descriptors(
        boundary: AppBoundary,
        schedule: AppBoundarySchedule
    ) -> [(name: DeviceActivityName, schedule: DeviceActivitySchedule)] {
        switch schedule.cadence {
        case .daily:
            let weekdays = schedule.activeWeekdays.isEmpty
                ? Set(Weekday.allCases)
                : schedule.activeWeekdays
            return weekdays.sorted().map { weekday in
                let name = activityName(
                    boundaryID: boundary.id,
                    scheduleID: schedule.id,
                    suffix: "\(weekday.rawValue)"
                )
                return (
                    name,
                    DeviceActivitySchedule(
                        intervalStart: scheduleComponents(
                            weekday: weekday.calendarWeekday,
                            time: schedule.resetTime,
                            timeZoneIdentifier: boundary.timeZoneIdentifier
                        ),
                        intervalEnd: scheduleComponents(
                            weekday: weekday.next.calendarWeekday,
                            time: schedule.resetTime,
                            timeZoneIdentifier: boundary.timeZoneIdentifier
                        ),
                        repeats: true
                    )
                )
            }
        case .weekly:
            let endTime = oneMinuteBefore(schedule.resetTime)
            let name = activityName(
                boundaryID: boundary.id,
                scheduleID: schedule.id,
                suffix: "weekly"
            )
            return [
                (
                    name,
                    DeviceActivitySchedule(
                        intervalStart: scheduleComponents(
                            weekday: schedule.weekStartsOn.calendarWeekday,
                            time: schedule.resetTime,
                            timeZoneIdentifier: boundary.timeZoneIdentifier
                        ),
                        intervalEnd: scheduleComponents(
                            weekday: schedule.weekStartsOn.previous.calendarWeekday,
                            time: endTime,
                            timeZoneIdentifier: boundary.timeZoneIdentifier
                        ),
                        repeats: true
                    )
                )
            ]
        }
    }

    private static func activityName(
        boundaryID: String,
        scheduleID: String,
        suffix: String
    ) -> DeviceActivityName {
        DeviceActivityName(
            "\(activityPrefix)\(boundaryID).\(scheduleID).\(suffix)"
        )
    }

    private static func scheduleComponents(
        weekday: Int,
        time: LocalTime,
        timeZoneIdentifier: String
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.weekday = weekday
        components.hour = time.hour
        components.minute = time.minute
        return components
    }

    private static func storeName(for activityName: String) -> String {
        "TheClimbBoundary." + activityName
            .replacingOccurrences(of: activityPrefix, with: "")
    }

    private static func oneMinuteBefore(_ time: LocalTime) -> LocalTime {
        let totalMinutes = (time.hour * 60 + time.minute - 1 + 24 * 60) % (24 * 60)
        return (try? LocalTime(
            hour: totalMinutes / 60,
            minute: totalMinutes % 60
        )) ?? time
    }
}

private extension Weekday {
    var calendarWeekday: Int {
        switch self {
        case .sunday:
            1
        case .monday:
            2
        case .tuesday:
            3
        case .wednesday:
            4
        case .thursday:
            5
        case .friday:
            6
        case .saturday:
            7
        }
    }

    var next: Weekday {
        Weekday(rawValue: rawValue == 7 ? 1 : rawValue + 1) ?? .monday
    }
}
#else
enum GeneralFocusDeviceActivityScheduler {
    static let activityNameRawValue = "the-climb.focus-session"
    static func start(until endsAt: Date) -> Bool { false }
    static func stop() {}
}

enum FocusRhythmDeviceActivityScheduler {
    static func schedule(_ rhythm: FocusRhythm) throws {
        throw FocusSessionRuntimeError.unsupported
    }

    static func stop(rhythmID: String) {}
}

enum AppBoundaryDeviceActivityScheduler {
    static func schedule(_ boundary: AppBoundary) throws {
        throw FocusSessionRuntimeError.unsupported
    }

    static func stop(boundaryID: String) {}
}
#endif
