import Foundation

// MARK: - Recommendation vocabulary

enum AttentionAssistRecommendationKind: String, Codable, CaseIterable {
    case boundaryApproaching
    case repeatedDistraction
    case usageAbovePersonalAverage
    case missedFocusRhythm
    case sleepGoalAtRisk
    case devotionalStillOpen
    case protectionNeedsAttention
    case focusRhythmStartingSoon
}

enum AttentionAssistPriority: Int, Codable, Comparable {
    case low = 0
    case normal = 1
    case high = 2

    static func < (lhs: AttentionAssistPriority, rhs: AttentionAssistPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AttentionAssistDestination: String, Codable {
    case boundaryDetails
    case focusSetup
    case attentionReport
    case focusRhythm
    case devotional
    case protectionHealth
}

enum AttentionAssistEvidenceSource: String, Codable {
    case deviceActivity
    case appBoundaryState
    case localScheduleAndSessionState
    case localFaithCompletionState
    case protectionHealth
}

enum AttentionAssistMeasurementQuality: String, Codable {
    case exact
    case aggregated
    case thresholdCrossing
    case stateObservation
}

struct AttentionAssistEvidenceSummary: Codable, Equatable {
    var source: AttentionAssistEvidenceSource
    var quality: AttentionAssistMeasurementQuality
    var observedAt: Date
}

struct AttentionAssistRecommendationCandidate: Identifiable, Codable, Equatable {
    var id: String
    var sourceSignalID: String
    var kind: AttentionAssistRecommendationKind
    var priority: AttentionAssistPriority
    var title: String
    var message: String
    var destination: AttentionAssistDestination
    var deduplicationKey: String
    var evidence: AttentionAssistEvidenceSummary
    var createdAt: Date
    var recommendedDeliveryAt: Date
    var expiresAt: Date
}

// MARK: - Real signal inputs

struct AttentionAssistBoundarySignal: Codable, Equatable {
    var signalID: String
    var boundaryReference: String
    var observedAt: Date
    var expiresAt: Date
    var remainingTime: TimeInterval
    var warningThreshold: TimeInterval
}

struct AttentionAssistRepeatedDistractionSignal: Codable, Equatable {
    var signalID: String
    var distractionReference: String
    var observedAt: Date
    var expiresAt: Date
    var minimumObservedOpenCount: Int
    var triggerCount: Int
    var observationWindow: TimeInterval
    var source: AttentionAssistEvidenceSource
    var quality: AttentionAssistMeasurementQuality
}

struct AttentionAssistUsageAboveAverageSignal: Codable, Equatable {
    var signalID: String
    var observedAt: Date
    var expiresAt: Date
    var observedUsage: TimeInterval
    var personalAverage: TimeInterval
    var personalAverageSampleDays: Int
    var minimumRelativeIncrease: Double
    var minimumAbsoluteIncrease: TimeInterval
    var source: AttentionAssistEvidenceSource
    var quality: AttentionAssistMeasurementQuality
}

struct AttentionAssistMissedRhythmSignal: Codable, Equatable {
    var signalID: String
    var rhythmReference: String
    var observedAt: Date
    var expiresAt: Date
    var scheduledStart: Date
    var gracePeriodEndedAt: Date
    var hasStarted: Bool
}

struct AttentionAssistSleepGoalSignal: Codable, Equatable {
    var signalID: String
    var goalReference: String
    var observedAt: Date
    var expiresAt: Date
    var observedEveningUsage: TimeInterval
    var configuredRiskThreshold: TimeInterval
    var sleepGoalAt: Date
    var source: AttentionAssistEvidenceSource
    var quality: AttentionAssistMeasurementQuality
}

struct AttentionAssistDevotionalSignal: Codable, Equatable {
    var signalID: String
    var devotionalReference: String
    var observedAt: Date
    var expiresAt: Date
    var plannedCompletionBy: Date
    var isCompleted: Bool
}

enum AttentionAssistProtectionState: String, Codable {
    case fullyProtected
    case partiallyProtected
    case actionRequired
    case off
    case unavailable
}

struct AttentionAssistProtectionSignal: Codable, Equatable {
    var signalID: String
    var protectionReference: String
    var observedAt: Date
    var expiresAt: Date
    var state: AttentionAssistProtectionState
}

struct AttentionAssistRhythmStartingSignal: Codable, Equatable {
    var signalID: String
    var rhythmReference: String
    var observedAt: Date
    var startsAt: Date
    var reminderLeadTime: TimeInterval
}

enum AttentionAssistSignal: Codable, Equatable {
    case boundaryApproaching(AttentionAssistBoundarySignal)
    case repeatedDistraction(AttentionAssistRepeatedDistractionSignal)
    case usageAbovePersonalAverage(AttentionAssistUsageAboveAverageSignal)
    case missedFocusRhythm(AttentionAssistMissedRhythmSignal)
    case sleepGoalAtRisk(AttentionAssistSleepGoalSignal)
    case devotionalStillOpen(AttentionAssistDevotionalSignal)
    case protectionNeedsAttention(AttentionAssistProtectionSignal)
    case focusRhythmStartingSoon(AttentionAssistRhythmStartingSignal)

    var kind: AttentionAssistRecommendationKind {
        switch self {
        case .boundaryApproaching:
            return .boundaryApproaching
        case .repeatedDistraction:
            return .repeatedDistraction
        case .usageAbovePersonalAverage:
            return .usageAbovePersonalAverage
        case .missedFocusRhythm:
            return .missedFocusRhythm
        case .sleepGoalAtRisk:
            return .sleepGoalAtRisk
        case .devotionalStillOpen:
            return .devotionalStillOpen
        case .protectionNeedsAttention:
            return .protectionNeedsAttention
        case .focusRhythmStartingSoon:
            return .focusRhythmStartingSoon
        }
    }

    fileprivate var signalID: String {
        switch self {
        case .boundaryApproaching(let signal):
            return signal.signalID
        case .repeatedDistraction(let signal):
            return signal.signalID
        case .usageAbovePersonalAverage(let signal):
            return signal.signalID
        case .missedFocusRhythm(let signal):
            return signal.signalID
        case .sleepGoalAtRisk(let signal):
            return signal.signalID
        case .devotionalStillOpen(let signal):
            return signal.signalID
        case .protectionNeedsAttention(let signal):
            return signal.signalID
        case .focusRhythmStartingSoon(let signal):
            return signal.signalID
        }
    }
}

// MARK: - User preferences

enum AttentionAssistFrequency: String, Codable, CaseIterable {
    case off
    case minimal
    case balanced
    case frequent
    case custom
}

struct AttentionAssistQuietHours: Codable, Equatable {
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int

    var isValid: Bool {
        (0...1_439).contains(startMinuteOfDay)
            && (0...1_439).contains(endMinuteOfDay)
    }

    fileprivate func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard isValid else {
            return true
        }
        if startMinuteOfDay == endMinuteOfDay {
            return true
        }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return true
        }
        let minuteOfDay = (hour * 60) + minute
        if startMinuteOfDay < endMinuteOfDay {
            return minuteOfDay >= startMinuteOfDay && minuteOfDay < endMinuteOfDay
        }
        return minuteOfDay >= startMinuteOfDay || minuteOfDay < endMinuteOfDay
    }

    fileprivate func nextEnd(after date: Date, calendar: Calendar) -> Date? {
        guard isValid, startMinuteOfDay != endMinuteOfDay else {
            return nil
        }
        let endHour = endMinuteOfDay / 60
        let endMinute = endMinuteOfDay % 60
        return calendar.nextDate(
            after: date,
            matching: DateComponents(hour: endHour, minute: endMinute),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}

struct AttentionAssistPreferences: Codable, Equatable {
    var isEnabled: Bool
    var frequency: AttentionAssistFrequency
    var enabledKinds: Set<AttentionAssistRecommendationKind>
    var quietHours: AttentionAssistQuietHours?
    var timeZoneIdentifier: String
    var maximumRecommendationsPerDay: Int
    var minimumIntervalBetweenRecommendations: TimeInterval
    var cooldownByKind: [AttentionAssistRecommendationKind: TimeInterval]

    static func recommended(
        frequency: AttentionAssistFrequency,
        quietHours: AttentionAssistQuietHours?,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> AttentionAssistPreferences {
        let maximumPerDay: Int
        let minimumInterval: TimeInterval
        switch frequency {
        case .off:
            maximumPerDay = 0
            minimumInterval = 0
        case .minimal:
            maximumPerDay = 2
            minimumInterval = 6 * 60 * 60
        case .balanced:
            maximumPerDay = 4
            minimumInterval = 3 * 60 * 60
        case .frequent:
            maximumPerDay = 6
            minimumInterval = 90 * 60
        case .custom:
            maximumPerDay = 4
            minimumInterval = 3 * 60 * 60
        }

        return AttentionAssistPreferences(
            isEnabled: frequency != .off,
            frequency: frequency,
            enabledKinds: Set(AttentionAssistRecommendationKind.allCases),
            quietHours: quietHours,
            timeZoneIdentifier: timeZoneIdentifier,
            maximumRecommendationsPerDay: maximumPerDay,
            minimumIntervalBetweenRecommendations: minimumInterval,
            cooldownByKind: [
                .boundaryApproaching: 4 * 60 * 60,
                .repeatedDistraction: 6 * 60 * 60,
                .usageAbovePersonalAverage: 24 * 60 * 60,
                .missedFocusRhythm: 12 * 60 * 60,
                .sleepGoalAtRisk: 24 * 60 * 60,
                .devotionalStillOpen: 24 * 60 * 60,
                .protectionNeedsAttention: 12 * 60 * 60,
                .focusRhythmStartingSoon: 4 * 60 * 60
            ]
        )
    }

    fileprivate var isValid: Bool {
        maximumRecommendationsPerDay >= 0
            && minimumIntervalBetweenRecommendations.isFinite
            && minimumIntervalBetweenRecommendations >= 0
            && TimeZone(identifier: timeZoneIdentifier) != nil
            && (quietHours?.isValid ?? true)
            && cooldownByKind.values.allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

// MARK: - Delivery history and evaluation

struct AttentionAssistDeliveryRecord: Codable, Equatable {
    var recommendationID: String
    var deduplicationKey: String
    var kind: AttentionAssistRecommendationKind
    var deliveredAt: Date
}

enum AttentionAssistSuppressionReason: String, Codable, CaseIterable {
    case disabled
    case recommendationKindDisabled
    case invalidPreferences
    case invalidSignal
    case insufficientEvidence
    case conditionNotMet
    case stale
    case duplicateCandidate
    case alreadyDelivered
    case quietHours
    case globalCooldown
    case kindCooldown
    case dailyFrequencyLimit
}

struct AttentionAssistSuppression: Codable, Equatable {
    var signalID: String
    var kind: AttentionAssistRecommendationKind
    var deduplicationKey: String?
    var reason: AttentionAssistSuppressionReason
}

struct AttentionAssistEvaluation: Codable, Equatable {
    var candidates: [AttentionAssistRecommendationCandidate]
    var suppressions: [AttentionAssistSuppression]
    var evaluatedAt: Date
}

protocol AttentionAssistEvaluating {
    func evaluate(
        signals: [AttentionAssistSignal],
        preferences: AttentionAssistPreferences,
        deliveryHistory: [AttentionAssistDeliveryRecord],
        at date: Date
    ) -> AttentionAssistEvaluation
}

struct AttentionAssistEngine: AttentionAssistEvaluating {
    func evaluate(
        signals: [AttentionAssistSignal],
        preferences: AttentionAssistPreferences,
        deliveryHistory: [AttentionAssistDeliveryRecord],
        at date: Date = Date()
    ) -> AttentionAssistEvaluation {
        guard preferences.isValid else {
            return suppressedEvaluation(
                signals: signals,
                reason: .invalidPreferences,
                at: date
            )
        }
        guard preferences.isEnabled,
              preferences.frequency != .off,
              preferences.maximumRecommendationsPerDay > 0 else {
            return suppressedEvaluation(signals: signals, reason: .disabled, at: date)
        }
        guard let timeZone = TimeZone(identifier: preferences.timeZoneIdentifier) else {
            return suppressedEvaluation(
                signals: signals,
                reason: .invalidPreferences,
                at: date
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var candidatesByKey: [String: AttentionAssistRecommendationCandidate] = [:]
        var suppressions: [AttentionAssistSuppression] = []

        for signal in signals {
            guard preferences.enabledKinds.contains(signal.kind) else {
                suppressions.append(
                    suppression(for: signal, key: nil, reason: .recommendationKindDisabled)
                )
                continue
            }

            let derivation = derive(signal, at: date, calendar: calendar)
            guard var candidate = derivation.candidate else {
                suppressions.append(
                    suppression(
                        for: signal,
                        key: derivation.deduplicationKey,
                        reason: derivation.suppressionReason ?? .invalidSignal
                    )
                )
                continue
            }

            if let quietHours = preferences.quietHours,
               quietHours.contains(candidate.recommendedDeliveryAt, calendar: calendar) {
                guard let quietHoursEnd = quietHours.nextEnd(
                    after: candidate.recommendedDeliveryAt,
                    calendar: calendar
                ),
                quietHoursEnd < candidate.expiresAt else {
                    suppressions.append(
                        suppression(
                            for: signal,
                            key: candidate.deduplicationKey,
                            reason: .quietHours
                        )
                    )
                    continue
                }
                candidate.recommendedDeliveryAt = quietHoursEnd
            }

            if let existing = candidatesByKey[candidate.deduplicationKey] {
                if candidateHasHigherPriority(candidate, than: existing) {
                    candidatesByKey[candidate.deduplicationKey] = candidate
                }
                suppressions.append(
                    suppression(
                        for: signal,
                        key: candidate.deduplicationKey,
                        reason: .duplicateCandidate
                    )
                )
            } else {
                candidatesByKey[candidate.deduplicationKey] = candidate
            }
        }

        let rankedCandidates = candidatesByKey.values.sorted {
            candidateHasHigherPriority($0, than: $1)
        }
        let deliveredHistory = deliveryHistory.filter { $0.deliveredAt <= date }
        var accepted: [AttentionAssistRecommendationCandidate] = []

        for candidate in rankedCandidates {
            if deliveredHistory.contains(where: {
                $0.deduplicationKey == candidate.deduplicationKey
            }) {
                suppressions.append(
                    suppression(for: candidate, reason: .alreadyDelivered)
                )
                continue
            }

            let comparableDeliveries = deliveredHistory.map(\.deliveredAt)
                + accepted.map(\.recommendedDeliveryAt)
            if comparableDeliveries.contains(where: {
                abs(candidate.recommendedDeliveryAt.timeIntervalSince($0))
                    < preferences.minimumIntervalBetweenRecommendations
            }) {
                suppressions.append(
                    suppression(for: candidate, reason: .globalCooldown)
                )
                continue
            }

            let kindCooldown = preferences.cooldownByKind[candidate.kind] ?? 0
            let sameKindDeliveries = deliveredHistory
                .filter { $0.kind == candidate.kind }
                .map(\.deliveredAt)
                + accepted
                    .filter { $0.kind == candidate.kind }
                    .map(\.recommendedDeliveryAt)
            if sameKindDeliveries.contains(where: {
                abs(candidate.recommendedDeliveryAt.timeIntervalSince($0)) < kindCooldown
            }) {
                suppressions.append(
                    suppression(for: candidate, reason: .kindCooldown)
                )
                continue
            }

            let deliveryDay = calendar.startOfDay(for: candidate.recommendedDeliveryAt)
            let deliveredOnDay = deliveredHistory.filter {
                calendar.startOfDay(for: $0.deliveredAt) == deliveryDay
            }.count
            let acceptedOnDay = accepted.filter {
                calendar.startOfDay(for: $0.recommendedDeliveryAt) == deliveryDay
            }.count
            guard (deliveredOnDay + acceptedOnDay)
                    < preferences.maximumRecommendationsPerDay else {
                suppressions.append(
                    suppression(for: candidate, reason: .dailyFrequencyLimit)
                )
                continue
            }

            accepted.append(candidate)
        }

        return AttentionAssistEvaluation(
            candidates: accepted.sorted {
                if $0.recommendedDeliveryAt != $1.recommendedDeliveryAt {
                    return $0.recommendedDeliveryAt < $1.recommendedDeliveryAt
                }
                return candidateHasHigherPriority($0, than: $1)
            },
            suppressions: suppressions,
            evaluatedAt: date
        )
    }

    private func derive(
        _ signal: AttentionAssistSignal,
        at date: Date,
        calendar: Calendar
    ) -> Derivation {
        switch signal {
        case .boundaryApproaching(let value):
            return deriveBoundary(value, at: date, calendar: calendar)
        case .repeatedDistraction(let value):
            return deriveRepeatedDistraction(value, at: date, calendar: calendar)
        case .usageAbovePersonalAverage(let value):
            return deriveUsageAboveAverage(value, at: date, calendar: calendar)
        case .missedFocusRhythm(let value):
            return deriveMissedRhythm(value, at: date, calendar: calendar)
        case .sleepGoalAtRisk(let value):
            return deriveSleepGoal(value, at: date, calendar: calendar)
        case .devotionalStillOpen(let value):
            return deriveDevotional(value, at: date, calendar: calendar)
        case .protectionNeedsAttention(let value):
            return deriveProtection(value, at: date, calendar: calendar)
        case .focusRhythmStartingSoon(let value):
            return deriveStartingRhythm(value, at: date, calendar: calendar)
        }
    }

    private func deriveBoundary(
        _ signal: AttentionAssistBoundarySignal,
        at date: Date,
        calendar: Calendar
    ) -> Derivation {
        let key = dailyKey(
            kind: .boundaryApproaching,
            reference: signal.boundaryReference,
            date: signal.observedAt,
            calendar: calendar
        )
        guard validIdentity(signal.signalID, signal.boundaryReference),
              validObservation(
                observedAt: signal.observedAt,
                expiresAt: signal.expiresAt,
                at: date
              ),
              signal.remainingTime.isFinite,
              signal.warningThreshold.isFinite,
              signal.remainingTime >= 0,
              signal.warningThreshold > 0 else {
            return .suppressed(key: key, reason: .invalidSignal)
        }
        guard signal.expiresAt > date else {
            return .suppressed(key: key, reason: .stale)
        }
        guard signal.remainingTime <= signal.warningThreshold else {
            return .suppressed(key: key, reason: .conditionNotMet)
        }

        let message: String
        if signal.remainingTime < 60 {
            message = "Less than a minute remains on this attention boundary."
        } else {
            let minutes = max(1, Int(ceil(signal.remainingTime / 60)))
            message = "\(minutes) minutes remain on this attention boundary."
        }
        return .candidate(
            makeCandidate(
                kind: .boundaryApproaching,
                signalID: signal.signalID,
                priority: signal.remainingTime <= 10 * 60 ? .high : .normal,
                title: "Boundary approaching",
                message: message,
                destination: .boundaryDetails,
                key: key,
                source: .appBoundaryState,
                quality: .stateObservation,
                observedAt: signal.observedAt,
                deliveryAt: date,
                expiresAt: signal.expiresAt
            )
        )
    }

    private func deriveRepeatedDistraction(
        _ signal: AttentionAssistRepeatedDistractionSignal,
        at date: Date,
        calendar: Calendar
    ) -> Derivation {
        let key = dailyKey(
            kind: .repeatedDistraction,
            reference: signal.distractionReference,
            date: signal.observedAt,
            calendar: calendar
        )
        guard validIdentity(signal.signalID, signal.distractionReference),
              validObservation(
                observedAt: signal.observedAt,
                expiresAt: signal.expiresAt,
                at: date
              ),
              signal.minimumObservedOpenCount >= 0,
              signal.triggerCount > 0,
              signal.observationWindow.isFinite,
              signal.observationWindow > 0 else {
            return .suppressed(key: key, reason: .invalidSignal)
        }
        guard signal.source == .deviceActivity,
              signal.quality == .exact || signal.quality == .thresholdCrossing else {
            return .suppressed(key: key, reason: .insufficientEvidence)
        }
        guard signal.expiresAt > date else {
            return .suppressed(key: key, reason: .stale)
        }
        guard signal.minimumObservedOpenCount >= signal.triggerCount else {
            return .suppressed(key: key, reason: .conditionNotMet)
        }

        return .candidate(
            makeCandidate(
                kind: .repeatedDistraction,
                signalID: signal.signalID,
                priority: .normal,
                title: "Pause before the next open",
                message: "A distraction threshold you set has been reached.",
                destination: .focusSetup,
                key: key,
                source: signal.source,
                quality: signal.quality,
                observedAt: signal.observedAt,
                deliveryAt: date,
                expiresAt: signal.expiresAt
            )
        )
    }

    private func deriveUsageAboveAverage(
        _ signal: AttentionAssistUsageAboveAverageSignal,
        at date: Date,
        calendar: Calendar
    ) -> Derivation {
        let key = dailyKey(
            kind: .usageAbovePersonalAverage,
            reference: "daily-usage",
            date: signal.observedAt,
            calendar: calendar
        )
        guard !signal.signalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              validObservation(
                observedAt: signal.observedAt,
                expiresAt: signal.expiresAt,
                at: date
              ),
              signal.observedUsage.isFinite,
              signal.personalAverage.isFinite,
              signal.minimumRelativeIncrease.isFinite,
              signal.minimumAbsoluteIncrease.isFinite,
              signal.observedUsage >= 0,
              signal.personalAverage > 0,
              signal.personalAverageSampleDays >= 3,
              signal.minimumRelativeIncrease >= 1,
              signal.minimumAbsoluteIncrease >= 0 else {
            return .suppressed(key: key, reason: .invalidSignal)
        }
        guard signal.source == .deviceActivity,
              signal.quality == .exact || signal.quality == .aggregated else {
            return .suppressed(key: key, reason: .insufficientEvidence)
        }
        guard signal.expiresAt > date else {
            return .suppressed(key: key, reason: .stale)
        }
        let absoluteIncrease = signal.observedUsage - signal.personalAverage
        let relativeIncrease = signal.observedUsage / signal.personalAverage
        guard absoluteIncrease >= signal.minimumAbsoluteIncrease,
              relativeIncrease >= signal.minimumRelativeIncrease else {
            return .suppressed(key: key, reason: .conditionNotMet)
        }

        return .candidate(
            makeCandidate(
                kind: .usageAbovePersonalAverage,
                signalID: signal.signalID,
                priority: .normal,
                title: "Attention check-in",
                message: "Today’s observed screen time is above your recent average.",
                destination: .attentionReport,
                key: key,
                source: signal.source,
                quality: signal.quality,
                observedAt: signal.observedAt,
                deliveryAt: date,
                expiresAt: signal.expiresAt
            )
        )
    }

    private func deriveMissedRhythm(
        _ signal: AttentionAssistMissedRhythmSignal,
        at date: Date,
        calendar: Calendar
    ) -> Derivation {
        let key = occurrenceKey(
            kind: .missedFocusRhythm,
            reference: signal.rhythmReference,
            occurrence: signal.scheduledStart
        )
        guard validIdentity(signal.signalID, signal.rhythmReference),
              validObservation(
                observedAt: signal.observedAt,
                expiresAt: signal.expiresAt,
                at: date
              ),
              signal.gracePeriodEndedAt >= signal.scheduledStart else {
            return .suppressed(key: key, reason: .invalidSignal)
        }
        guard signal.expiresAt > date else {
            return .suppressed(key: key, reason: .stale)
        }
        guard date >= signal.gracePeriodEndedAt, !signal.hasStarted else {
            return .suppressed(key: key, reason: .conditionNotMet)
        }

        return .candidate(
            makeCandidate(
                kind: .missedFocusRhythm,
                signalID: signal.signalID,
                priority: .normal,
                title: "Your rhythm is waiting",
                message: "A planned focus rhythm has not started.",
                destination: .focusRhythm,
                key: key,
                source: .localScheduleAndSessionState,
                quality: .stateObservation,
                observedAt: signal.observedAt,
                deliveryAt: date,
                expiresAt: signal.expiresAt
            )
        )
    }

    private func deriveSleepGoal(
        _ signal: AttentionAssistSleepGoalSignal,
        at date: Date,
        calendar: Calendar
    ) -> Derivation {
        let key = dailyKey(
            kind: .sleepGoalAtRisk,
            reference: signal.goalReference,
            date: signal.observedAt,
            calendar: calendar
        )
        guard validIdentity(signal.signalID, signal.goalReference),
              validObservation(
                observedAt: signal.observedAt,
                expiresAt: signal.expiresAt,
                at: date
              ),
              signal.observedEveningUsage.isFinite,
              signal.configuredRiskThreshold.isFinite,
              signal.observedEveningUsage >= 0,
              signal.configuredRiskThreshold > 0,
              signal.sleepGoalAt > signal.observedAt else {
            return .suppressed(key: key, reason: .invalidSignal)
        }
        guard signal.source == .deviceActivity,
              signal.quality == .exact || signal.quality == .aggregated else {
            return .suppressed(key: key, reason: .insufficientEvidence)
        }
        guard signal.expiresAt > date, signal.sleepGoalAt > date else {
            return .suppressed(key: key, reason: .stale)
        }
        guard signal.observedEveningUsage >= signal.configuredRiskThreshold else {
            return .suppressed(key: key, reason: .conditionNotMet)
        }

        return .candidate(
            makeCandidate(
                kind: .sleepGoalAtRisk,
                signalID: signal.signalID,
                priority: .high,
                title: "Protect tonight’s rest",
                message: "Evening screen time reached the limit you set before sleep.",
                destination: .focusSetup,
                key: key,
                source: signal.source,
                quality: signal.quality,
                observedAt: signal.observedAt,
                deliveryAt: date,
                expiresAt: min(signal.expiresAt, signal.sleepGoalAt)
            )
        )
    }

    private func deriveDevotional(
        _ signal: AttentionAssistDevotionalSignal,
        at date: Date,
        calendar: Calendar
    ) -> Derivation {
        let key = dailyKey(
            kind: .devotionalStillOpen,
            reference: signal.devotionalReference,
            date: signal.plannedCompletionBy,
            calendar: calendar
        )
        guard validIdentity(signal.signalID, signal.devotionalReference),
              validObservation(
                observedAt: signal.observedAt,
                expiresAt: signal.expiresAt,
                at: date
              ),
              signal.plannedCompletionBy <= signal.expiresAt else {
            return .suppressed(key: key, reason: .invalidSignal)
        }
        guard signal.expiresAt > date else {
            return .suppressed(key: key, reason: .stale)
        }
        guard date >= signal.plannedCompletionBy, !signal.isCompleted else {
            return .suppressed(key: key, reason: .conditionNotMet)
        }

        return .candidate(
            makeCandidate(
                kind: .devotionalStillOpen,
                signalID: signal.signalID,
                priority: .normal,
                title: "Return to the Word",
                message: "Your planned Scripture time is still open.",
                destination: .devotional,
                key: key,
                source: .localFaithCompletionState,
                quality: .stateObservation,
                observedAt: signal.observedAt,
                deliveryAt: date,
                expiresAt: signal.expiresAt
            )
        )
    }

    private func deriveProtection(
        _ signal: AttentionAssistProtectionSignal,
        at date: Date,
        calendar: Calendar
    ) -> Derivation {
        let key = dailyKey(
            kind: .protectionNeedsAttention,
            reference: signal.protectionReference,
            date: signal.observedAt,
            calendar: calendar
        )
        guard validIdentity(signal.signalID, signal.protectionReference),
              validObservation(
                observedAt: signal.observedAt,
                expiresAt: signal.expiresAt,
                at: date
              ) else {
            return .suppressed(key: key, reason: .invalidSignal)
        }
        guard signal.expiresAt > date else {
            return .suppressed(key: key, reason: .stale)
        }
        guard signal.state == .partiallyProtected || signal.state == .actionRequired else {
            return .suppressed(key: key, reason: .conditionNotMet)
        }

        return .candidate(
            makeCandidate(
                kind: .protectionNeedsAttention,
                signalID: signal.signalID,
                priority: signal.state == .actionRequired ? .high : .normal,
                title: "Protection needs attention",
                message: "Review your protection status to restore the coverage you chose.",
                destination: .protectionHealth,
                key: key,
                source: .protectionHealth,
                quality: .stateObservation,
                observedAt: signal.observedAt,
                deliveryAt: date,
                expiresAt: signal.expiresAt
            )
        )
    }

    private func deriveStartingRhythm(
        _ signal: AttentionAssistRhythmStartingSignal,
        at date: Date,
        calendar: Calendar
    ) -> Derivation {
        let key = occurrenceKey(
            kind: .focusRhythmStartingSoon,
            reference: signal.rhythmReference,
            occurrence: signal.startsAt
        )
        guard validIdentity(signal.signalID, signal.rhythmReference),
              signal.reminderLeadTime.isFinite,
              signal.reminderLeadTime > 0,
              signal.observedAt <= date,
              signal.observedAt <= signal.startsAt else {
            return .suppressed(key: key, reason: .invalidSignal)
        }
        let remaining = signal.startsAt.timeIntervalSince(date)
        guard remaining > 0 else {
            return .suppressed(key: key, reason: .stale)
        }
        guard remaining <= signal.reminderLeadTime else {
            return .suppressed(key: key, reason: .conditionNotMet)
        }

        let minutes = max(1, Int(ceil(remaining / 60)))
        return .candidate(
            makeCandidate(
                kind: .focusRhythmStartingSoon,
                signalID: signal.signalID,
                priority: .low,
                title: "Focus rhythm soon",
                message: "Your next focus rhythm begins in \(minutes) minutes.",
                destination: .focusRhythm,
                key: key,
                source: .localScheduleAndSessionState,
                quality: .stateObservation,
                observedAt: signal.observedAt,
                deliveryAt: date,
                expiresAt: signal.startsAt
            )
        )
    }

    private func makeCandidate(
        kind: AttentionAssistRecommendationKind,
        signalID: String,
        priority: AttentionAssistPriority,
        title: String,
        message: String,
        destination: AttentionAssistDestination,
        key: String,
        source: AttentionAssistEvidenceSource,
        quality: AttentionAssistMeasurementQuality,
        observedAt: Date,
        deliveryAt: Date,
        expiresAt: Date
    ) -> AttentionAssistRecommendationCandidate {
        AttentionAssistRecommendationCandidate(
            id: key,
            sourceSignalID: signalID,
            kind: kind,
            priority: priority,
            title: title,
            message: message,
            destination: destination,
            deduplicationKey: key,
            evidence: AttentionAssistEvidenceSummary(
                source: source,
                quality: quality,
                observedAt: observedAt
            ),
            createdAt: deliveryAt,
            recommendedDeliveryAt: deliveryAt,
            expiresAt: expiresAt
        )
    }

    private func validIdentity(_ signalID: String, _ reference: String) -> Bool {
        !signalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func validObservation(
        observedAt: Date,
        expiresAt: Date,
        at date: Date
    ) -> Bool {
        observedAt <= date && expiresAt > observedAt
    }

    private func dailyKey(
        kind: AttentionAssistRecommendationKind,
        reference: String,
        date: Date,
        calendar: Calendar
    ) -> String {
        let day = Int(calendar.startOfDay(for: date).timeIntervalSince1970)
        return "\(kind.rawValue):\(reference):day:\(day)"
    }

    private func occurrenceKey(
        kind: AttentionAssistRecommendationKind,
        reference: String,
        occurrence: Date
    ) -> String {
        "\(kind.rawValue):\(reference):occurrence:\(Int(occurrence.timeIntervalSince1970))"
    }

    private func candidateHasHigherPriority(
        _ lhs: AttentionAssistRecommendationCandidate,
        than rhs: AttentionAssistRecommendationCandidate
    ) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        if lhs.expiresAt != rhs.expiresAt {
            return lhs.expiresAt < rhs.expiresAt
        }
        return lhs.id < rhs.id
    }

    private func suppression(
        for signal: AttentionAssistSignal,
        key: String?,
        reason: AttentionAssistSuppressionReason
    ) -> AttentionAssistSuppression {
        AttentionAssistSuppression(
            signalID: signal.signalID,
            kind: signal.kind,
            deduplicationKey: key,
            reason: reason
        )
    }

    private func suppression(
        for candidate: AttentionAssistRecommendationCandidate,
        reason: AttentionAssistSuppressionReason
    ) -> AttentionAssistSuppression {
        AttentionAssistSuppression(
            signalID: candidate.sourceSignalID,
            kind: candidate.kind,
            deduplicationKey: candidate.deduplicationKey,
            reason: reason
        )
    }

    private func suppressedEvaluation(
        signals: [AttentionAssistSignal],
        reason: AttentionAssistSuppressionReason,
        at date: Date
    ) -> AttentionAssistEvaluation {
        AttentionAssistEvaluation(
            candidates: [],
            suppressions: signals.map {
                suppression(for: $0, key: nil, reason: reason)
            },
            evaluatedAt: date
        )
    }
}

private struct Derivation {
    var candidate: AttentionAssistRecommendationCandidate?
    var deduplicationKey: String?
    var suppressionReason: AttentionAssistSuppressionReason?

    static func candidate(
        _ candidate: AttentionAssistRecommendationCandidate
    ) -> Derivation {
        Derivation(
            candidate: candidate,
            deduplicationKey: candidate.deduplicationKey,
            suppressionReason: nil
        )
    }

    static func suppressed(
        key: String?,
        reason: AttentionAssistSuppressionReason
    ) -> Derivation {
        Derivation(
            candidate: nil,
            deduplicationKey: key,
            suppressionReason: reason
        )
    }
}

extension AttentionAssistProtectionState {
    init(_ status: ProtectionHealthStatus) {
        switch status {
        case .fullyProtected:
            self = .fullyProtected
        case .partiallyProtected:
            self = .partiallyProtected
        case .actionRequired:
            self = .actionRequired
        case .off:
            self = .off
        case .unavailable:
            self = .unavailable
        }
    }
}
