import Foundation

/// This behavioral consistency score never represents a person's spiritual worth.
enum StewardshipScoreMeaning: String, Codable, Equatable {
    case behavioralStewardshipNotSpiritualWorth
}

enum StewardshipScoreState: String, Codable, Equatable {
    case scored
    case insufficientData
}

enum StewardshipInsufficientDataReason: String, Codable, Equatable {
    case fewerThanThreeRecords
    case fewerThanTwoMeasuredFactors
}

enum StewardshipScoreFactor: String, Codable, CaseIterable, Equatable {
    case protectedFocus
    case rhythmAdherence
    case boundaryAdherence
    case missionCompletion
    case habitCompletion
    case reflectionCompletion

    /// Base weights total 100: focus 30, rhythms 20, boundaries 20,
    /// missions 12, habits 10, and reflections 8.
    var baseWeight: Double {
        switch self {
        case .protectedFocus:
            return 30
        case .rhythmAdherence:
            return 20
        case .boundaryAdherence:
            return 20
        case .missionCompletion:
            return 12
        case .habitCompletion:
            return 10
        case .reflectionCompletion:
            return 8
        }
    }
}

enum StewardshipFactorAvailability: String, Codable, Equatable {
    case measured
    case unavailable
}

struct StewardshipScoreFactorBreakdown: Codable, Equatable {
    var factor: StewardshipScoreFactor
    var availability: StewardshipFactorAvailability
    var evidenceCount: Int
    var factorScore: Double?
    var baseWeight: Double
    var effectiveWeight: Double
    var weightedContribution: Double
}

/// A standalone stewardship result that is neither derived from nor written to OVR.
struct StewardshipScoreResult: Codable, Equatable {
    var state: StewardshipScoreState
    var score: Int?
    var meaning: StewardshipScoreMeaning
    var intervalStart: Date
    var intervalEnd: Date
    var evaluatedAt: Date
    var evidenceCount: Int
    var measuredFactorCount: Int
    var insufficientDataReasons: [StewardshipInsufficientDataReason]
    var factors: [StewardshipScoreFactorBreakdown]

    static func insufficient(
        interval: DateInterval,
        evaluatedAt: Date,
        evidenceCount: Int,
        measuredFactorCount: Int,
        reasons: [StewardshipInsufficientDataReason],
        factors: [StewardshipScoreFactorBreakdown]
    ) -> StewardshipScoreResult {
        StewardshipScoreResult(
            state: .insufficientData,
            score: nil,
            meaning: .behavioralStewardshipNotSpiritualWorth,
            intervalStart: interval.start,
            intervalEnd: interval.end,
            evaluatedAt: evaluatedAt,
            evidenceCount: evidenceCount,
            measuredFactorCount: measuredFactorCount,
            insufficientDataReasons: reasons,
            factors: factors
        )
    }
}

enum RhythmAdherenceOutcome: String, Codable, Equatable {
    case completed
    case partiallyCompleted
    case missed
    case excused
}

struct RhythmAdherenceRecord: Identifiable, Codable, Equatable {
    var id: String
    var rhythmID: String
    var rhythmName: String?
    var scheduledStart: Date
    var scheduledEnd: Date
    var protectedDuration: TimeInterval
    var outcome: RhythmAdherenceOutcome
}

enum BoundaryAdherenceEvidenceSource: String, Codable, Equatable {
    case deviceActivityReport
    case verifiedImport
}

struct BoundaryAdherenceRecord: Identifiable, Codable, Equatable {
    var id: String
    var boundaryID: String
    var scheduleID: String
    var periodStart: Date
    var periodEnd: Date
    var allowedDuration: TimeInterval
    var observedDuration: TimeInterval
    var evidenceSource: BoundaryAdherenceEvidenceSource
    var isFinalized: Bool
}

enum StewardshipCompletionKind: String, Codable, CaseIterable, Equatable {
    case mission
    case habit
    case reflection

    var scoreFactor: StewardshipScoreFactor {
        switch self {
        case .mission:
            return .missionCompletion
        case .habit:
            return .habitCompletion
        case .reflection:
            return .reflectionCompletion
        }
    }
}

enum StewardshipCompletionOutcome: String, Codable, Equatable {
    case completed
    case missed
    case excused
}

struct StewardshipCompletionRecord: Identifiable, Codable, Equatable {
    var id: String
    var kind: StewardshipCompletionKind
    var itemID: String
    var scheduledAt: Date
    var completedAt: Date?
    var outcome: StewardshipCompletionOutcome
}

struct StewardshipScoreEvidence: Codable, Equatable {
    var protectedFocusRecords: [ProtectedTimeRecord]
    var rhythmAdherenceRecords: [RhythmAdherenceRecord]
    var boundaryAdherenceRecords: [BoundaryAdherenceRecord]
    var completionRecords: [StewardshipCompletionRecord]

    static let empty = StewardshipScoreEvidence(
        protectedFocusRecords: [],
        rhythmAdherenceRecords: [],
        boundaryAdherenceRecords: [],
        completionRecords: []
    )
}

struct StewardshipScoreEngine {
    static let minimumEvidenceCount = 3
    static let minimumMeasuredFactorCount = 2

    /// The final score is the weighted mean of measured factors. Unavailable
    /// factors are removed and the remaining base weights are normalized to 100.
    func score(
        evidence: StewardshipScoreEvidence,
        within interval: DateInterval,
        evaluatedAt: Date = Date()
    ) -> StewardshipScoreResult {
        let filtered = evidenceWithin(interval, from: evidence)
        var breakdowns = [
            protectedFocusBreakdown(filtered.protectedFocusRecords),
            rhythmBreakdown(filtered.rhythmAdherenceRecords),
            boundaryBreakdown(filtered.boundaryAdherenceRecords),
            completionBreakdown(.mission, records: filtered.completionRecords),
            completionBreakdown(.habit, records: filtered.completionRecords),
            completionBreakdown(.reflection, records: filtered.completionRecords)
        ]

        let measuredIndices = breakdowns.indices.filter {
            breakdowns[$0].availability == .measured
        }
        let measuredWeight = measuredIndices.reduce(0) {
            $0 + breakdowns[$1].baseWeight
        }

        if measuredWeight > 0 {
            for index in measuredIndices {
                let effectiveWeight = breakdowns[index].baseWeight / measuredWeight * 100
                breakdowns[index].effectiveWeight = effectiveWeight
                breakdowns[index].weightedContribution = (
                    breakdowns[index].factorScore ?? 0
                ) * effectiveWeight / 100
            }
        }

        let evidenceCount = breakdowns.reduce(0) {
            $0 + $1.evidenceCount
        }
        let measuredFactorCount = measuredIndices.count
        var insufficientReasons: [StewardshipInsufficientDataReason] = []
        if evidenceCount < Self.minimumEvidenceCount {
            insufficientReasons.append(.fewerThanThreeRecords)
        }
        if measuredFactorCount < Self.minimumMeasuredFactorCount {
            insufficientReasons.append(.fewerThanTwoMeasuredFactors)
        }

        guard insufficientReasons.isEmpty else {
            return .insufficient(
                interval: interval,
                evaluatedAt: evaluatedAt,
                evidenceCount: evidenceCount,
                measuredFactorCount: measuredFactorCount,
                reasons: insufficientReasons,
                factors: breakdowns
            )
        }

        let rawScore = breakdowns.reduce(0) {
            $0 + $1.weightedContribution
        }
        let deterministicScore = Int(
            min(100, max(0, rawScore)).rounded(.toNearestOrAwayFromZero)
        )

        return StewardshipScoreResult(
            state: .scored,
            score: deterministicScore,
            meaning: .behavioralStewardshipNotSpiritualWorth,
            intervalStart: interval.start,
            intervalEnd: interval.end,
            evaluatedAt: evaluatedAt,
            evidenceCount: evidenceCount,
            measuredFactorCount: measuredFactorCount,
            insufficientDataReasons: [],
            factors: breakdowns
        )
    }

    private func evidenceWithin(
        _ interval: DateInterval,
        from evidence: StewardshipScoreEvidence
    ) -> StewardshipScoreEvidence {
        let focusRecords = unique(
            evidence.protectedFocusRecords.filter {
                $0.endedAt >= interval.start && $0.endedAt < interval.end
            },
            id: { $0.id }
        )
        let rhythmRecords = unique(
            evidence.rhythmAdherenceRecords.filter {
                $0.scheduledStart >= interval.start
                    && $0.scheduledStart < interval.end
            },
            id: { $0.id }
        )
        let boundaryRecords = unique(
            evidence.boundaryAdherenceRecords.filter {
                $0.periodEnd >= interval.start && $0.periodEnd < interval.end
            },
            id: { $0.id }
        )
        let completions = unique(
            evidence.completionRecords.filter {
                $0.scheduledAt >= interval.start && $0.scheduledAt < interval.end
            },
            id: { $0.id }
        )

        return StewardshipScoreEvidence(
            protectedFocusRecords: focusRecords,
            rhythmAdherenceRecords: rhythmRecords,
            boundaryAdherenceRecords: boundaryRecords,
            completionRecords: completions
        )
    }

    /// Focus is planned-duration weighted: sum of capped protected duration
    /// divided by sum of valid planned duration, expressed from 0 through 100.
    private func protectedFocusBreakdown(
        _ records: [ProtectedTimeRecord]
    ) -> StewardshipScoreFactorBreakdown {
        let valid = records.filter {
            $0.plannedDuration.isFinite
                && $0.plannedDuration > 0
                && $0.protectedDuration.isFinite
                && $0.protectedDuration >= 0
                && $0.endedAt >= $0.startedAt
        }
        let planned = valid.reduce(0) { $0 + $1.plannedDuration }
        guard !valid.isEmpty, planned > 0 else {
            return unavailable(.protectedFocus)
        }

        let protected = valid.reduce(0) {
            $0 + min($1.plannedDuration, $1.protectedDuration)
        }
        return measured(
            .protectedFocus,
            evidenceCount: valid.count,
            factorScore: protected / planned * 100
        )
    }

    /// Rhythm occurrences score 100 when completed, 0 when missed, and use
    /// protected duration divided by scheduled duration when partially completed.
    /// Excused occurrences are excluded from both the numerator and denominator.
    private func rhythmBreakdown(
        _ records: [RhythmAdherenceRecord]
    ) -> StewardshipScoreFactorBreakdown {
        let scored = records.compactMap(rhythmScore)
        guard !scored.isEmpty else {
            return unavailable(.rhythmAdherence)
        }

        return measured(
            .rhythmAdherence,
            evidenceCount: scored.count,
            factorScore: scored.reduce(0, +) / Double(scored.count) * 100
        )
    }

    /// A finalized boundary period scores 100 at or below its allowance.
    /// Overage reduces the period linearly, reaching 0 at twice the allowance.
    private func boundaryBreakdown(
        _ records: [BoundaryAdherenceRecord]
    ) -> StewardshipScoreFactorBreakdown {
        let scored = records.compactMap(boundaryScore)
        guard !scored.isEmpty else {
            return unavailable(.boundaryAdherence)
        }

        return measured(
            .boundaryAdherence,
            evidenceCount: scored.count,
            factorScore: scored.reduce(0, +) / Double(scored.count) * 100
        )
    }

    /// Mission, habit, and reflection factors are independent completion rates:
    /// completed records count as 1, missed records as 0, and excused records do
    /// not participate.
    private func completionBreakdown(
        _ kind: StewardshipCompletionKind,
        records: [StewardshipCompletionRecord]
    ) -> StewardshipScoreFactorBreakdown {
        let outcomes = records
            .filter { $0.kind == kind }
            .compactMap(completionScore)
        guard !outcomes.isEmpty else {
            return unavailable(kind.scoreFactor)
        }

        return measured(
            kind.scoreFactor,
            evidenceCount: outcomes.count,
            factorScore: outcomes.reduce(0, +) / Double(outcomes.count) * 100
        )
    }

    private func rhythmScore(_ record: RhythmAdherenceRecord) -> Double? {
        let scheduledDuration = record.scheduledEnd.timeIntervalSince(
            record.scheduledStart
        )
        guard scheduledDuration.isFinite, scheduledDuration > 0 else {
            return nil
        }

        switch record.outcome {
        case .completed:
            return 1
        case .missed:
            return 0
        case .excused:
            return nil
        case .partiallyCompleted:
            guard record.protectedDuration.isFinite,
                  record.protectedDuration >= 0 else {
                return nil
            }
            return min(1, record.protectedDuration / scheduledDuration)
        }
    }

    private func boundaryScore(_ record: BoundaryAdherenceRecord) -> Double? {
        guard record.isFinalized,
              record.periodEnd > record.periodStart,
              record.allowedDuration.isFinite,
              record.allowedDuration > 0,
              record.observedDuration.isFinite,
              record.observedDuration >= 0 else {
            return nil
        }
        let periodDuration = record.periodEnd.timeIntervalSince(record.periodStart)
        guard record.allowedDuration <= periodDuration,
              record.observedDuration <= periodDuration else {
            return nil
        }
        guard record.observedDuration > record.allowedDuration else {
            return 1
        }

        let overage = record.observedDuration - record.allowedDuration
        return max(0, 1 - overage / record.allowedDuration)
    }

    private func completionScore(
        _ record: StewardshipCompletionRecord
    ) -> Double? {
        switch record.outcome {
        case .completed:
            guard let completedAt = record.completedAt,
                  completedAt >= record.scheduledAt else {
                return nil
            }
            return 1
        case .missed:
            return 0
        case .excused:
            return nil
        }
    }

    private func measured(
        _ factor: StewardshipScoreFactor,
        evidenceCount: Int,
        factorScore: Double
    ) -> StewardshipScoreFactorBreakdown {
        StewardshipScoreFactorBreakdown(
            factor: factor,
            availability: .measured,
            evidenceCount: evidenceCount,
            factorScore: min(100, max(0, factorScore)),
            baseWeight: factor.baseWeight,
            effectiveWeight: 0,
            weightedContribution: 0
        )
    }

    private func unavailable(
        _ factor: StewardshipScoreFactor
    ) -> StewardshipScoreFactorBreakdown {
        StewardshipScoreFactorBreakdown(
            factor: factor,
            availability: .unavailable,
            evidenceCount: 0,
            factorScore: nil,
            baseWeight: factor.baseWeight,
            effectiveWeight: 0,
            weightedContribution: 0
        )
    }

    private func unique<T>(
        _ values: [T],
        id: (T) -> String
    ) -> [T] {
        var seen: Set<String> = []
        return values
            .sorted { id($0) < id($1) }
            .filter { seen.insert(id($0)).inserted }
    }
}

struct DailyStewardshipScoreRecord: Identifiable, Codable, Equatable {
    var id: String
    var dayStart: Date
    var dayEnd: Date
    var result: StewardshipScoreResult
    var recordedAt: Date
}

struct WeeklyStewardshipScoreRecord: Identifiable, Codable, Equatable {
    var id: String
    var weekStart: Date
    var weekEnd: Date
    var result: StewardshipScoreResult
    var recordedAt: Date
}

struct StewardshipScoreHistory: Codable, Equatable {
    var daily: [DailyStewardshipScoreRecord]
    var weekly: [WeeklyStewardshipScoreRecord]

    static let empty = StewardshipScoreHistory(daily: [], weekly: [])
}

struct StewardshipScoreHistoryService {
    private let engine: StewardshipScoreEngine

    init(engine: StewardshipScoreEngine = StewardshipScoreEngine()) {
        self.engine = engine
    }

    func dailyRecord(
        containing date: Date,
        evidence: StewardshipScoreEvidence,
        calendar: Calendar = .current,
        recordedAt: Date = Date()
    ) -> DailyStewardshipScoreRecord? {
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            return nil
        }
        let result = engine.score(
            evidence: evidence,
            within: interval,
            evaluatedAt: recordedAt
        )
        return DailyStewardshipScoreRecord(
            id: stablePeriodID(prefix: "day", start: interval.start),
            dayStart: interval.start,
            dayEnd: interval.end,
            result: result,
            recordedAt: recordedAt
        )
    }

    func weeklyRecord(
        containing date: Date,
        evidence: StewardshipScoreEvidence,
        calendar: Calendar = .current,
        recordedAt: Date = Date()
    ) -> WeeklyStewardshipScoreRecord? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return nil
        }
        let result = engine.score(
            evidence: evidence,
            within: interval,
            evaluatedAt: recordedAt
        )
        return WeeklyStewardshipScoreRecord(
            id: stablePeriodID(prefix: "week", start: interval.start),
            weekStart: interval.start,
            weekEnd: interval.end,
            result: result,
            recordedAt: recordedAt
        )
    }

    func adding(
        _ record: DailyStewardshipScoreRecord,
        to history: StewardshipScoreHistory
    ) -> StewardshipScoreHistory {
        var updated = history
        updated.daily.removeAll { $0.id == record.id }
        updated.daily.append(record)
        updated.daily.sort { $0.dayStart < $1.dayStart }
        return updated
    }

    func adding(
        _ record: WeeklyStewardshipScoreRecord,
        to history: StewardshipScoreHistory
    ) -> StewardshipScoreHistory {
        var updated = history
        updated.weekly.removeAll { $0.id == record.id }
        updated.weekly.append(record)
        updated.weekly.sort { $0.weekStart < $1.weekStart }
        return updated
    }

    private func stablePeriodID(prefix: String, start: Date) -> String {
        "\(prefix):\(Int(start.timeIntervalSince1970))"
    }
}

struct WeeklyRhythmEvidence: Codable, Equatable {
    var rhythmID: String
    var rhythmName: String?
    var adherenceScore: Int
    var evidenceCount: Int
}

struct StewardshipWeeklyReview: Codable, Equatable {
    var weekStart: Date
    var weekEnd: Date
    var scoreResult: StewardshipScoreResult
    var scoreChangeFromPreviousWeek: Int?
    var strongestRhythm: WeeklyRhythmEvidence?
    var weakestRhythm: WeeklyRhythmEvidence?
    var generatedAt: Date
}

struct StewardshipWeeklyReviewService {
    private let scoreEngine: StewardshipScoreEngine

    init(scoreEngine: StewardshipScoreEngine = StewardshipScoreEngine()) {
        self.scoreEngine = scoreEngine
    }

    func review(
        week: DateInterval,
        evidence: StewardshipScoreEvidence,
        previousWeek: WeeklyStewardshipScoreRecord? = nil,
        generatedAt: Date = Date()
    ) -> StewardshipWeeklyReview {
        let scoreResult = scoreEngine.score(
            evidence: evidence,
            within: week,
            evaluatedAt: generatedAt
        )
        let rhythmEvidence = rhythmEvidenceWithin(
            week,
            from: evidence.rhythmAdherenceRecords
        )
        let strongest = rhythmEvidence.sorted(by: strongestFirst).first
        let weakest: WeeklyRhythmEvidence?
        if rhythmEvidence.count > 1 {
            weakest = rhythmEvidence.sorted(by: weakestFirst).first
        } else {
            weakest = nil
        }

        return StewardshipWeeklyReview(
            weekStart: week.start,
            weekEnd: week.end,
            scoreResult: scoreResult,
            scoreChangeFromPreviousWeek: scoreChange(
                current: scoreResult,
                previous: previousWeek?.result
            ),
            strongestRhythm: strongest,
            weakestRhythm: weakest,
            generatedAt: generatedAt
        )
    }

    private func rhythmEvidenceWithin(
        _ interval: DateInterval,
        from records: [RhythmAdherenceRecord]
    ) -> [WeeklyRhythmEvidence] {
        let included = records.filter {
            $0.scheduledStart >= interval.start
                && $0.scheduledStart < interval.end
                && $0.outcome != .excused
        }
        var uniqueRecords: [String: RhythmAdherenceRecord] = [:]
        for record in included where uniqueRecords[record.id] == nil {
            uniqueRecords[record.id] = record
        }

        let grouped = Dictionary(grouping: uniqueRecords.values) {
            $0.rhythmID
        }
        return grouped.keys.sorted().compactMap { rhythmID in
            let rhythmRecords = grouped[rhythmID] ?? []
            let scores = rhythmRecords.compactMap(rhythmScore)
            guard !scores.isEmpty else {
                return nil
            }
            let average = scores.reduce(0, +) / Double(scores.count) * 100
            let name = rhythmRecords
                .compactMap { normalized($0.rhythmName) }
                .sorted()
                .first
            return WeeklyRhythmEvidence(
                rhythmID: rhythmID,
                rhythmName: name,
                adherenceScore: Int(
                    min(100, max(0, average)).rounded(.toNearestOrAwayFromZero)
                ),
                evidenceCount: scores.count
            )
        }
    }

    private func rhythmScore(_ record: RhythmAdherenceRecord) -> Double? {
        let scheduled = record.scheduledEnd.timeIntervalSince(
            record.scheduledStart
        )
        guard scheduled.isFinite, scheduled > 0 else {
            return nil
        }

        switch record.outcome {
        case .completed:
            return 1
        case .missed:
            return 0
        case .excused:
            return nil
        case .partiallyCompleted:
            guard record.protectedDuration.isFinite,
                  record.protectedDuration >= 0 else {
                return nil
            }
            return min(1, record.protectedDuration / scheduled)
        }
    }

    private func strongestFirst(
        _ lhs: WeeklyRhythmEvidence,
        _ rhs: WeeklyRhythmEvidence
    ) -> Bool {
        if lhs.adherenceScore == rhs.adherenceScore {
            if lhs.evidenceCount == rhs.evidenceCount {
                return lhs.rhythmID < rhs.rhythmID
            }
            return lhs.evidenceCount > rhs.evidenceCount
        }
        return lhs.adherenceScore > rhs.adherenceScore
    }

    private func weakestFirst(
        _ lhs: WeeklyRhythmEvidence,
        _ rhs: WeeklyRhythmEvidence
    ) -> Bool {
        if lhs.adherenceScore == rhs.adherenceScore {
            if lhs.evidenceCount == rhs.evidenceCount {
                return lhs.rhythmID < rhs.rhythmID
            }
            return lhs.evidenceCount > rhs.evidenceCount
        }
        return lhs.adherenceScore < rhs.adherenceScore
    }

    private func scoreChange(
        current: StewardshipScoreResult,
        previous: StewardshipScoreResult?
    ) -> Int? {
        guard current.state == .scored,
              let currentScore = current.score,
              previous?.state == .scored,
              let previousScore = previous?.score else {
            return nil
        }
        return currentScore - previousScore
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
