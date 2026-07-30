import Foundation

struct FocusSourceID: RawRepresentable, Codable, Hashable, Comparable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func session(_ id: String) -> FocusSourceID {
        FocusSourceID(rawValue: "focus-session:\(id)")
    }

    static func rhythm(_ id: String) -> FocusSourceID {
        FocusSourceID(rawValue: "focus-rhythm:\(id)")
    }

    static func boundary(_ id: String) -> FocusSourceID {
        FocusSourceID(rawValue: "app-boundary:\(id)")
    }

    static func < (lhs: FocusSourceID, rhs: FocusSourceID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct FocusSelectionReference: RawRepresentable, Codable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct EssentialAppsSelectionReference: RawRepresentable, Codable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum FocusPurpose: String, Codable, CaseIterable {
    case mission
    case prayer
    case bibleStudy
    case worship
    case church
    case family
    case exercise
    case deepWork
    case school
    case homework
    case creativeWork
    case personalGrowth
    case rest
    case sleep
    case custom

    var protectionSource: ProtectionSourceKind {
        switch self {
        case .mission:
            return .mission
        case .prayer:
            return .prayer
        case .bibleStudy:
            return .bibleStudy
        case .worship,
             .church,
             .family,
             .exercise,
             .deepWork,
             .school,
             .homework,
             .creativeWork,
             .personalGrowth,
             .rest,
             .sleep,
             .custom:
            return .focusSession
        }
    }

    var protectedTimeSource: ProtectedTimeSourceKind {
        switch self {
        case .mission:
            return .mission
        case .prayer:
            return .prayer
        case .bibleStudy:
            return .bibleStudy
        case .worship,
             .church,
             .family,
             .exercise,
             .deepWork,
             .school,
             .homework,
             .creativeWork,
             .personalGrowth,
             .rest,
             .sleep,
             .custom:
            return .focusSession
        }
    }
}

enum FocusStrictness: String, Codable, CaseIterable, Comparable {
    case flexible
    case intentional
    case locked
    case accountabilityLocked

    var protectionStrictness: ProtectionStrictness {
        switch self {
        case .flexible:
            return .flexible
        case .intentional:
            return .intentional
        case .locked:
            return .locked
        case .accountabilityLocked:
            return .accountabilityLocked
        }
    }

    init(protectionStrictness: ProtectionStrictness) {
        switch protectionStrictness {
        case .flexible:
            self = .flexible
        case .intentional:
            self = .intentional
        case .locked:
            self = .locked
        case .accountabilityLocked:
            self = .accountabilityLocked
        }
    }

    static func < (lhs: FocusStrictness, rhs: FocusStrictness) -> Bool {
        lhs.protectionStrictness < rhs.protectionStrictness
    }
}

enum FocusSessionState: String, Codable {
    case active
    case completed
    case endedEarly
    case cancelled
}

enum FocusSessionOutcome: String, Codable {
    case completed
    case endedEarly
    case cancelled
}

struct FocusSessionRequest: Codable, Equatable {
    var purpose: FocusPurpose
    var customPurposeName: String?
    var plannedDuration: TimeInterval
    var strictness: FocusStrictness
    var selectionReference: FocusSelectionReference?
    var essentialAppsReference: EssentialAppsSelectionReference?
    var blocksAdultWebContent: Bool
}

struct FocusSession: Identifiable, Codable, Equatable {
    var id: String
    var sourceID: FocusSourceID
    var purpose: FocusPurpose
    var customPurposeName: String?
    var plannedDuration: TimeInterval
    var strictness: FocusStrictness
    var selectionReference: FocusSelectionReference?
    var essentialAppsReference: EssentialAppsSelectionReference?
    var blocksAdultWebContent: Bool
    var state: FocusSessionState
    var startedAt: Date
    var plannedEndAt: Date
    var endedAt: Date?
    var earlyExitReason: String? = nil
    var createdAt: Date
    var updatedAt: Date

    var elapsedDuration: TimeInterval {
        max(0, (endedAt ?? plannedEndAt).timeIntervalSince(startedAt))
    }

    var isActive: Bool {
        state == .active
    }

    var protectionPolicy: ProtectionPolicy {
        ProtectionPolicy(
            id: sourceID.rawValue,
            source: purpose.protectionSource,
            strictness: strictness.protectionStrictness,
            selectionReference: selectionReference?.rawValue,
            blocksAdultWebContent: blocksAdultWebContent,
            isEnabled: isActive,
            startsAt: startedAt,
            endsAt: endedAt ?? plannedEndAt,
            temporaryExceptionForPolicyID: nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

enum FocusSessionServiceError: Error, Equatable {
    case invalidIdentifier
    case invalidDuration
    case sessionNotActive
    case endPrecedesStart
    case sessionHasNotEnded
}

struct FocusSessionService {
    private let identifier: () -> String

    init(identifier: @escaping () -> String = { UUID().uuidString }) {
        self.identifier = identifier
    }

    func start(
        _ request: FocusSessionRequest,
        at date: Date = Date()
    ) throws -> FocusSession {
        guard request.plannedDuration.isFinite, request.plannedDuration > 0 else {
            throw FocusSessionServiceError.invalidDuration
        }

        let id = identifier().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw FocusSessionServiceError.invalidIdentifier
        }

        return FocusSession(
            id: id,
            sourceID: .session(id),
            purpose: request.purpose,
            customPurposeName: normalized(request.customPurposeName),
            plannedDuration: request.plannedDuration,
            strictness: request.strictness,
            selectionReference: request.selectionReference,
            essentialAppsReference: request.essentialAppsReference,
            blocksAdultWebContent: request.blocksAdultWebContent,
            state: .active,
            startedAt: date,
            plannedEndAt: date.addingTimeInterval(request.plannedDuration),
            endedAt: nil,
            earlyExitReason: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    func end(
        _ session: FocusSession,
        outcome: FocusSessionOutcome,
        earlyExitReason: String? = nil,
        at date: Date = Date()
    ) throws -> FocusSession {
        guard session.isActive else {
            throw FocusSessionServiceError.sessionNotActive
        }
        guard date >= session.startedAt else {
            throw FocusSessionServiceError.endPrecedesStart
        }

        var updated = session
        updated.state = state(for: outcome)
        updated.endedAt = date
        updated.earlyExitReason = normalized(earlyExitReason)
        updated.updatedAt = date
        return updated
    }

    func record(
        for session: FocusSession,
        breakSegments: [ProtectedTimeBreakSegment] = [],
        enforcementEvidence: ProtectionEnforcementEvidence = .notObserved
    ) throws -> ProtectedTimeRecord {
        guard let endedAt = session.endedAt else {
            throw FocusSessionServiceError.sessionHasNotEnded
        }

        return ProtectedTimeRecord(
            id: session.id,
            sourceID: session.sourceID,
            sourceKind: session.purpose.protectedTimeSource,
            purpose: session.purpose,
            strictness: session.strictness,
            startedAt: session.startedAt,
            endedAt: endedAt,
            plannedDuration: session.plannedDuration,
            outcome: recordOutcome(for: session.state),
            breakSegments: breakSegments.filter {
                $0.sourceID == session.sourceID
            },
            enforcementEvidence: enforcementEvidence,
            earlyExitReason: session.earlyExitReason
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func state(for outcome: FocusSessionOutcome) -> FocusSessionState {
        switch outcome {
        case .completed:
            return .completed
        case .endedEarly:
            return .endedEarly
        case .cancelled:
            return .cancelled
        }
    }

    private func recordOutcome(for state: FocusSessionState) -> ProtectedTimeOutcome {
        switch state {
        case .completed:
            return .completed
        case .endedEarly:
            return .endedEarly
        case .cancelled:
            return .cancelled
        case .active:
            return .interrupted
        }
    }
}

enum Weekday: Int, Codable, CaseIterable, Comparable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1:
            self = .sunday
        case 2:
            self = .monday
        case 3:
            self = .tuesday
        case 4:
            self = .wednesday
        case 5:
            self = .thursday
        case 6:
            self = .friday
        case 7:
            self = .saturday
        default:
            return nil
        }
    }

    var previous: Weekday {
        Weekday(rawValue: rawValue == 1 ? 7 : rawValue - 1) ?? .sunday
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum LocalTimeError: Error, Equatable {
    case invalidHour
    case invalidMinute
}

struct LocalTime: Codable, Equatable, Comparable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour) else {
            throw LocalTimeError.invalidHour
        }
        guard (0...59).contains(minute) else {
            throw LocalTimeError.invalidMinute
        }
        self.hour = hour
        self.minute = minute
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedHour = try container.decode(Int.self, forKey: .hour)
        let decodedMinute = try container.decode(Int.self, forKey: .minute)
        guard (0...23).contains(decodedHour) else {
            throw DecodingError.dataCorruptedError(
                forKey: .hour,
                in: container,
                debugDescription: "Hour must be between 0 and 23."
            )
        }
        guard (0...59).contains(decodedMinute) else {
            throw DecodingError.dataCorruptedError(
                forKey: .minute,
                in: container,
                debugDescription: "Minute must be between 0 and 59."
            )
        }
        hour = decodedHour
        minute = decodedMinute
    }

    static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        if lhs.hour == rhs.hour {
            return lhs.minute < rhs.minute
        }
        return lhs.hour < rhs.hour
    }
}

struct FocusRhythm: Identifiable, Codable, Equatable {
    var id: String
    var sourceID: FocusSourceID
    var name: String
    var purpose: FocusPurpose
    var strictness: FocusStrictness
    var weekdays: Set<Weekday>
    var startTime: LocalTime
    var endTime: LocalTime
    var timeZoneIdentifier: String
    var selectionReference: FocusSelectionReference?
    var essentialAppsReference: EssentialAppsSelectionReference?
    var blocksAdultWebContent: Bool
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Equal or earlier end times belong to the calendar day after the start.
    var crossesMidnight: Bool {
        endTime <= startTime
    }
}

enum FocusRhythmPauseReason: String, Codable, CaseIterable {
    case travel
    case vacation
    case scheduleChanged
    case rest
    case other
}

struct FocusRhythmPause: Codable, Equatable {
    var pausedAt: Date
    var resumesAt: Date
    var reason: FocusRhythmPauseReason

    func isActive(at date: Date) -> Bool {
        date >= pausedAt && date < resumesAt
    }
}

struct FocusRhythmOccurrence: Codable, Equatable {
    var rhythmID: String
    var sourceID: FocusSourceID
    var startsAt: Date
    var endsAt: Date

    func contains(_ date: Date) -> Bool {
        date >= startsAt && date < endsAt
    }
}

struct FocusRhythmEvaluation: Equatable {
    var activeOccurrence: FocusRhythmOccurrence?
    var nextOccurrence: FocusRhythmOccurrence?

    var isActive: Bool {
        activeOccurrence != nil
    }
}

struct FocusRhythmEvaluator {
    func evaluate(
        _ rhythm: FocusRhythm,
        at date: Date = Date()
    ) -> FocusRhythmEvaluation {
        guard rhythm.isEnabled, let calendar = calendar(for: rhythm) else {
            return FocusRhythmEvaluation(activeOccurrence: nil, nextOccurrence: nil)
        }

        let active = occurrence(containing: date, rhythm: rhythm, calendar: calendar)
        let next = occurrence(onOrAfter: date, rhythm: rhythm, calendar: calendar)
        return FocusRhythmEvaluation(activeOccurrence: active, nextOccurrence: next)
    }

    func policy(
        for rhythm: FocusRhythm,
        occurrence: FocusRhythmOccurrence
    ) -> ProtectionPolicy {
        ProtectionPolicy(
            id: rhythm.sourceID.rawValue,
            source: .rhythm,
            strictness: rhythm.strictness.protectionStrictness,
            selectionReference: rhythm.selectionReference?.rawValue,
            blocksAdultWebContent: rhythm.blocksAdultWebContent,
            isEnabled: rhythm.isEnabled,
            startsAt: occurrence.startsAt,
            endsAt: occurrence.endsAt,
            temporaryExceptionForPolicyID: nil,
            createdAt: rhythm.createdAt,
            updatedAt: rhythm.updatedAt
        )
    }

    private func calendar(for rhythm: FocusRhythm) -> Calendar? {
        guard let timeZone = TimeZone(identifier: rhythm.timeZoneIdentifier) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func occurrence(
        containing date: Date,
        rhythm: FocusRhythm,
        calendar: Calendar
    ) -> FocusRhythmOccurrence? {
        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let candidateDays = [yesterday, today].compactMap { $0 }

        return candidateDays
            .compactMap { occurrence(startingOn: $0, rhythm: rhythm, calendar: calendar) }
            .first { $0.contains(date) }
    }

    private func occurrence(
        onOrAfter date: Date,
        rhythm: FocusRhythm,
        calendar: Calendar
    ) -> FocusRhythmOccurrence? {
        let today = calendar.startOfDay(for: date)
        var candidates: [FocusRhythmOccurrence] = []

        for offset in -1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let candidate = occurrence(
                    startingOn: day,
                    rhythm: rhythm,
                    calendar: calendar
                  ),
                  candidate.endsAt > date else {
                continue
            }
            candidates.append(candidate)
        }

        return candidates.sorted { $0.startsAt < $1.startsAt }.first
    }

    private func occurrence(
        startingOn day: Date,
        rhythm: FocusRhythm,
        calendar: Calendar
    ) -> FocusRhythmOccurrence? {
        guard let weekday = Weekday(
            calendarWeekday: calendar.component(.weekday, from: day)
        ),
        rhythm.weekdays.contains(weekday),
        let start = calendar.date(
            bySettingHour: rhythm.startTime.hour,
            minute: rhythm.startTime.minute,
            second: 0,
            of: day
        ) else {
            return nil
        }

        let endDay: Date
        if rhythm.crossesMidnight {
            guard let followingDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                return nil
            }
            endDay = followingDay
        } else {
            endDay = day
        }

        guard let end = calendar.date(
            bySettingHour: rhythm.endTime.hour,
            minute: rhythm.endTime.minute,
            second: 0,
            of: endDay
        ),
        end > start else {
            return nil
        }

        return FocusRhythmOccurrence(
            rhythmID: rhythm.id,
            sourceID: rhythm.sourceID,
            startsAt: start,
            endsAt: end
        )
    }
}

enum BoundaryScheduleCadence: String, Codable {
    case daily
    case weekly
}

struct AppBoundarySchedule: Identifiable, Codable, Equatable {
    var id: String
    var cadence: BoundaryScheduleCadence
    var allowedDuration: TimeInterval
    var resetTime: LocalTime
    var activeWeekdays: Set<Weekday>
    var weekStartsOn: Weekday
    var isEnabled: Bool
}

struct BoundaryWarningThreshold: Identifiable, Codable, Equatable {
    var id: String
    var remainingDuration: TimeInterval
}

struct AppBoundary: Identifiable, Codable, Equatable {
    var id: String
    var sourceID: FocusSourceID
    var name: String
    var selectionReference: FocusSelectionReference
    var essentialAppsReference: EssentialAppsSelectionReference?
    var strictness: FocusStrictness
    var schedules: [AppBoundarySchedule]
    var warningThresholds: [BoundaryWarningThreshold]
    var timeZoneIdentifier: String
    var blocksAdultWebContent: Bool
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
}

enum BoundaryUsageProvenance: String, Codable {
    case deviceActivityReport
    case importedMeasurement
}

struct BoundaryUsageMeasurement: Identifiable, Codable, Equatable {
    var id: String
    var intervalStart: Date
    var intervalEnd: Date
    var observedDuration: TimeInterval
    var provenance: BoundaryUsageProvenance
}

enum AppBoundaryScheduleState: String, Codable {
    case inactive
    case withinLimit
    case warning
    case limitReached
    case invalid
}

struct AppBoundaryScheduleEvaluation: Codable, Equatable {
    var scheduleID: String
    var state: AppBoundaryScheduleState
    var intervalStart: Date?
    var intervalEnd: Date?
    var observedDuration: TimeInterval
    var allowedDuration: TimeInterval
    var remainingDuration: TimeInterval
    var crossedWarningIDs: [String]
}

struct AppBoundaryEvaluation: Codable, Equatable {
    var boundaryID: String
    var evaluatedAt: Date
    var scheduleEvaluations: [AppBoundaryScheduleEvaluation]

    var hasReachedLimit: Bool {
        scheduleEvaluations.contains { $0.state == .limitReached }
    }

    var nextResetAt: Date? {
        scheduleEvaluations.compactMap(\.intervalEnd).min()
    }

    var enforcementEndsAt: Date? {
        scheduleEvaluations
            .filter { $0.state == .limitReached }
            .compactMap(\.intervalEnd)
            .max()
    }
}

struct AppBoundaryEvaluator {
    func evaluate(
        _ boundary: AppBoundary,
        measurements: [BoundaryUsageMeasurement],
        at date: Date = Date()
    ) -> AppBoundaryEvaluation {
        guard boundary.isEnabled,
              let timeZone = TimeZone(identifier: boundary.timeZoneIdentifier) else {
            return AppBoundaryEvaluation(
                boundaryID: boundary.id,
                evaluatedAt: date,
                scheduleEvaluations: boundary.schedules.map {
                    inactiveEvaluation(for: $0)
                }
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let evaluations = boundary.schedules.map { schedule in
            evaluate(
                schedule,
                measurements: measurements,
                warningThresholds: boundary.warningThresholds,
                at: date,
                calendar: calendar
            )
        }

        return AppBoundaryEvaluation(
            boundaryID: boundary.id,
            evaluatedAt: date,
            scheduleEvaluations: evaluations
        )
    }

    func protectionPolicy(
        for boundary: AppBoundary,
        evaluation: AppBoundaryEvaluation,
        at date: Date = Date()
    ) -> ProtectionPolicy {
        ProtectionPolicy(
            id: boundary.sourceID.rawValue,
            source: .boundary,
            strictness: boundary.strictness.protectionStrictness,
            selectionReference: boundary.selectionReference.rawValue,
            blocksAdultWebContent: boundary.blocksAdultWebContent,
            isEnabled: boundary.isEnabled && evaluation.hasReachedLimit,
            startsAt: evaluation.hasReachedLimit ? date : nil,
            endsAt: evaluation.enforcementEndsAt,
            temporaryExceptionForPolicyID: nil,
            createdAt: boundary.createdAt,
            updatedAt: boundary.updatedAt
        )
    }

    private func evaluate(
        _ schedule: AppBoundarySchedule,
        measurements: [BoundaryUsageMeasurement],
        warningThresholds: [BoundaryWarningThreshold],
        at date: Date,
        calendar: Calendar
    ) -> AppBoundaryScheduleEvaluation {
        guard schedule.isEnabled else {
            return inactiveEvaluation(for: schedule)
        }
        guard schedule.allowedDuration.isFinite, schedule.allowedDuration > 0,
              let interval = interval(for: schedule, at: date, calendar: calendar) else {
            return invalidEvaluation(for: schedule)
        }

        if schedule.cadence == .daily,
           !schedule.activeWeekdays.isEmpty,
           let weekday = Weekday(
               calendarWeekday: calendar.component(.weekday, from: interval.start)
           ),
           !schedule.activeWeekdays.contains(weekday) {
            return inactiveEvaluation(for: schedule)
        }

        let observed = measurements.reduce(0) { partial, measurement in
            partial + observedDuration(from: measurement, within: interval)
        }
        let boundedObserved = min(interval.duration, max(0, observed))
        let remaining = max(0, schedule.allowedDuration - boundedObserved)
        let crossedWarnings = warningThresholds
            .filter {
                $0.remainingDuration.isFinite
                    && $0.remainingDuration >= 0
                    && $0.remainingDuration <= schedule.allowedDuration
                    && remaining <= $0.remainingDuration
                    && boundedObserved < schedule.allowedDuration
            }
            .sorted { $0.remainingDuration > $1.remainingDuration }
            .map(\.id)

        let state: AppBoundaryScheduleState
        if boundedObserved >= schedule.allowedDuration {
            state = .limitReached
        } else if !crossedWarnings.isEmpty {
            state = .warning
        } else {
            state = .withinLimit
        }

        return AppBoundaryScheduleEvaluation(
            scheduleID: schedule.id,
            state: state,
            intervalStart: interval.start,
            intervalEnd: interval.end,
            observedDuration: boundedObserved,
            allowedDuration: schedule.allowedDuration,
            remainingDuration: remaining,
            crossedWarningIDs: crossedWarnings
        )
    }

    private func interval(
        for schedule: AppBoundarySchedule,
        at date: Date,
        calendar: Calendar
    ) -> DateInterval? {
        switch schedule.cadence {
        case .daily:
            return dailyInterval(for: schedule, at: date, calendar: calendar)
        case .weekly:
            return weeklyInterval(for: schedule, at: date, calendar: calendar)
        }
    }

    private func dailyInterval(
        for schedule: AppBoundarySchedule,
        at date: Date,
        calendar: Calendar
    ) -> DateInterval? {
        var resetDay = calendar.startOfDay(for: date)
        guard var start = calendar.date(
            bySettingHour: schedule.resetTime.hour,
            minute: schedule.resetTime.minute,
            second: 0,
            of: resetDay
        ) else {
            return nil
        }

        if date < start {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: resetDay),
                  let previousReset = calendar.date(
                      bySettingHour: schedule.resetTime.hour,
                      minute: schedule.resetTime.minute,
                      second: 0,
                      of: previousDay
                  ) else {
                return nil
            }
            resetDay = previousDay
            start = previousReset
        }

        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: resetDay),
              let end = calendar.date(
                  bySettingHour: schedule.resetTime.hour,
                  minute: schedule.resetTime.minute,
                  second: 0,
                  of: nextDay
              ),
              end > start else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private func weeklyInterval(
        for schedule: AppBoundarySchedule,
        at date: Date,
        calendar: Calendar
    ) -> DateInterval? {
        let today = calendar.startOfDay(for: date)
        guard let todayWeekday = Weekday(
            calendarWeekday: calendar.component(.weekday, from: today)
        ) else {
            return nil
        }

        let daysSinceReset = (
            todayWeekday.rawValue - schedule.weekStartsOn.rawValue + 7
        ) % 7
        guard var resetDay = calendar.date(
            byAdding: .day,
            value: -daysSinceReset,
            to: today
        ),
        var start = calendar.date(
            bySettingHour: schedule.resetTime.hour,
            minute: schedule.resetTime.minute,
            second: 0,
            of: resetDay
        ) else {
            return nil
        }

        if date < start {
            guard let previousWeek = calendar.date(byAdding: .day, value: -7, to: resetDay),
                  let previousReset = calendar.date(
                      bySettingHour: schedule.resetTime.hour,
                      minute: schedule.resetTime.minute,
                      second: 0,
                      of: previousWeek
                  ) else {
                return nil
            }
            resetDay = previousWeek
            start = previousReset
        }

        guard let followingWeek = calendar.date(byAdding: .day, value: 7, to: resetDay),
              let end = calendar.date(
                  bySettingHour: schedule.resetTime.hour,
                  minute: schedule.resetTime.minute,
                  second: 0,
                  of: followingWeek
              ),
              end > start else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private func observedDuration(
        from measurement: BoundaryUsageMeasurement,
        within interval: DateInterval
    ) -> TimeInterval {
        guard measurement.observedDuration.isFinite,
              measurement.observedDuration > 0,
              measurement.intervalEnd > measurement.intervalStart else {
            return 0
        }

        let measurementInterval = DateInterval(
            start: measurement.intervalStart,
            end: measurement.intervalEnd
        )
        guard let overlap = measurementInterval.intersection(with: interval) else {
            return 0
        }

        let measurementSpan = measurementInterval.duration
        guard measurementSpan > 0 else {
            return 0
        }
        let normalizedDuration = min(measurement.observedDuration, measurementSpan)
        return normalizedDuration * (overlap.duration / measurementSpan)
    }

    private func inactiveEvaluation(
        for schedule: AppBoundarySchedule
    ) -> AppBoundaryScheduleEvaluation {
        AppBoundaryScheduleEvaluation(
            scheduleID: schedule.id,
            state: .inactive,
            intervalStart: nil,
            intervalEnd: nil,
            observedDuration: 0,
            allowedDuration: max(0, schedule.allowedDuration),
            remainingDuration: max(0, schedule.allowedDuration),
            crossedWarningIDs: []
        )
    }

    private func invalidEvaluation(
        for schedule: AppBoundarySchedule
    ) -> AppBoundaryScheduleEvaluation {
        AppBoundaryScheduleEvaluation(
            scheduleID: schedule.id,
            state: .invalid,
            intervalStart: nil,
            intervalEnd: nil,
            observedDuration: 0,
            allowedDuration: max(0, schedule.allowedDuration),
            remainingDuration: max(0, schedule.allowedDuration),
            crossedWarningIDs: []
        )
    }
}

enum IntentionalBreakState: String, Codable {
    case scheduled
    case active
    case ended
    case cancelled
}

enum FocusEarlyExitRequestState: String, Codable {
    case pending
    case executed
    case cancelled
}

struct FocusEarlyExitRequest: Identifiable, Codable, Equatable {
    var id: String
    var sessionID: String
    var reason: String
    var state: FocusEarlyExitRequestState
    var requestedAt: Date
    var earliestExecutionAt: Date
    var updatedAt: Date

    func canExecute(at date: Date) -> Bool {
        state == .pending && date >= earliestExecutionAt
    }
}

struct IntentionalBreak: Identifiable, Codable, Equatable {
    var id: String
    var targetSourceID: FocusSourceID
    var reason: String?
    var state: IntentionalBreakState
    var startsAt: Date
    var endsAt: Date
    var createdAt: Date
    var updatedAt: Date

    func isActive(at date: Date) -> Bool {
        state != .cancelled && date >= startsAt && date < endsAt
    }

    var temporaryExceptionPolicy: ProtectionPolicy {
        ProtectionPolicy(
            id: "intentional-break:\(id)",
            source: .temporaryException,
            strictness: .intentional,
            selectionReference: nil,
            blocksAdultWebContent: false,
            isEnabled: state != .cancelled,
            startsAt: startsAt,
            endsAt: endsAt,
            temporaryExceptionForPolicyID: targetSourceID.rawValue,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    var protectedTimeSegment: ProtectedTimeBreakSegment {
        ProtectedTimeBreakSegment(
            id: id,
            sourceID: targetSourceID,
            startsAt: startsAt,
            endsAt: endsAt
        )
    }
}

enum IntentionalBreakServiceError: Error, Equatable {
    case invalidIdentifier
    case invalidSource
    case invalidDuration
    case breakNotActive
    case endPrecedesStart
}

struct IntentionalBreakService {
    private let identifier: () -> String

    init(identifier: @escaping () -> String = { UUID().uuidString }) {
        self.identifier = identifier
    }

    func create(
        for sourceID: FocusSourceID,
        duration: TimeInterval,
        reason: String? = nil,
        at date: Date = Date()
    ) throws -> IntentionalBreak {
        guard !sourceID.rawValue.isEmpty else {
            throw IntentionalBreakServiceError.invalidSource
        }
        guard duration.isFinite, duration > 0 else {
            throw IntentionalBreakServiceError.invalidDuration
        }
        let id = identifier().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw IntentionalBreakServiceError.invalidIdentifier
        }

        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        return IntentionalBreak(
            id: id,
            targetSourceID: sourceID,
            reason: trimmedReason?.isEmpty == false ? trimmedReason : nil,
            state: .active,
            startsAt: date,
            endsAt: date.addingTimeInterval(duration),
            createdAt: date,
            updatedAt: date
        )
    }

    func end(
        _ intentionalBreak: IntentionalBreak,
        at date: Date = Date()
    ) throws -> IntentionalBreak {
        guard intentionalBreak.state == .active else {
            throw IntentionalBreakServiceError.breakNotActive
        }
        guard date >= intentionalBreak.startsAt else {
            throw IntentionalBreakServiceError.endPrecedesStart
        }

        var updated = intentionalBreak
        updated.state = .ended
        updated.endsAt = min(date, intentionalBreak.endsAt)
        updated.updatedAt = date
        return updated
    }

    func activeBreak(
        for sourceID: FocusSourceID,
        in breaks: [IntentionalBreak],
        at date: Date = Date()
    ) -> IntentionalBreak? {
        breaks
            .filter { $0.targetSourceID == sourceID && $0.isActive(at: date) }
            .sorted { $0.startsAt < $1.startsAt }
            .first
    }
}

enum ProtectedTimeSourceKind: String, Codable {
    case focusSession
    case rhythm
    case boundary
    case mission
    case prayer
    case bibleStudy
}

enum ProtectedTimeOutcome: String, Codable {
    case completed
    case endedEarly
    case cancelled
    case interrupted
}

enum ProtectionEnforcementEvidence: String, Codable {
    case notObserved
    case policyRequested
    case policyConfirmed
}

struct ProtectedTimeBreakSegment: Identifiable, Codable, Equatable {
    var id: String
    var sourceID: FocusSourceID
    var startsAt: Date
    var endsAt: Date
}

struct ProtectedTimeRecord: Identifiable, Codable, Equatable {
    var id: String
    var sourceID: FocusSourceID
    var sourceKind: ProtectedTimeSourceKind
    var purpose: FocusPurpose
    var strictness: FocusStrictness
    var startedAt: Date
    var endedAt: Date
    var plannedDuration: TimeInterval
    var outcome: ProtectedTimeOutcome
    var breakSegments: [ProtectedTimeBreakSegment]
    var enforcementEvidence: ProtectionEnforcementEvidence
    var earlyExitReason: String? = nil

    var elapsedDuration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    var protectedDuration: TimeInterval {
        ProtectedTimeIntervalMath.activeIntervals(for: self)
            .reduce(0) { $0 + $1.duration }
    }
}

struct ProtectedTimeHistory: Codable, Equatable {
    var records: [ProtectedTimeRecord]

    static let empty = ProtectedTimeHistory(records: [])
}

struct ProtectedTimeHistoryService {
    func adding(
        _ record: ProtectedTimeRecord,
        to history: ProtectedTimeHistory
    ) -> ProtectedTimeHistory {
        var records = history.records.filter { $0.id != record.id }
        records.append(record)
        records.sort {
            if $0.startedAt == $1.startedAt {
                return $0.id < $1.id
            }
            return $0.startedAt < $1.startedAt
        }
        return ProtectedTimeHistory(records: records)
    }

    func removing(
        recordID: String,
        from history: ProtectedTimeHistory
    ) -> ProtectedTimeHistory {
        ProtectedTimeHistory(
            records: history.records.filter { $0.id != recordID }
        )
    }
}

struct ProtectedTimePurposeAggregate: Codable, Equatable {
    var purpose: FocusPurpose
    var protectedDuration: TimeInterval
    var sessionCount: Int
}

struct ProtectedTimeDayAggregate: Codable, Equatable {
    var dayStart: Date
    var protectedDuration: TimeInterval
}

enum AttentionReportEvidence: String, Codable {
    case protectedTimeRecords
}

struct AttentionReport: Codable, Equatable {
    var intervalStart: Date
    var intervalEnd: Date
    var evidence: AttentionReportEvidence
    var recordCount: Int
    var completedRecordCount: Int
    var protectedDuration: TimeInterval
    var completedProtectedDuration: TimeInterval
    var averageProtectedDuration: TimeInterval
    var longestProtectedDuration: TimeInterval
    var completionRate: Double
    var activeDayCount: Int
    var byPurpose: [ProtectedTimePurposeAggregate]
    var byDay: [ProtectedTimeDayAggregate]

    static func empty(for interval: DateInterval) -> AttentionReport {
        AttentionReport(
            intervalStart: interval.start,
            intervalEnd: interval.end,
            evidence: .protectedTimeRecords,
            recordCount: 0,
            completedRecordCount: 0,
            protectedDuration: 0,
            completedProtectedDuration: 0,
            averageProtectedDuration: 0,
            longestProtectedDuration: 0,
            completionRate: 0,
            activeDayCount: 0,
            byPurpose: [],
            byDay: []
        )
    }
}

struct AttentionReportService {
    func report(
        from records: [ProtectedTimeRecord],
        within interval: DateInterval,
        calendar suppliedCalendar: Calendar = .current
    ) -> AttentionReport {
        guard interval.duration > 0 else {
            return .empty(for: interval)
        }

        let includedRecords = records.filter {
            $0.endedAt > interval.start && $0.startedAt < interval.end
        }
        guard !includedRecords.isEmpty else {
            return .empty(for: interval)
        }

        var purposeDurations: [FocusPurpose: TimeInterval] = [:]
        var purposeCounts: [FocusPurpose: Int] = [:]
        var dayDurations: [Date: TimeInterval] = [:]
        var recordDurations: [String: TimeInterval] = [:]
        var calendar = suppliedCalendar
        calendar.locale = Locale(identifier: "en_US_POSIX")

        for record in includedRecords {
            let activeIntervals = ProtectedTimeIntervalMath
                .activeIntervals(for: record)
                .compactMap { $0.intersection(with: interval) }
            let duration = activeIntervals.reduce(0) { $0 + $1.duration }
            recordDurations[record.id] = duration
            purposeDurations[record.purpose, default: 0] += duration
            purposeCounts[record.purpose, default: 0] += 1

            for activeInterval in activeIntervals {
                add(
                    activeInterval,
                    to: &dayDurations,
                    calendar: calendar
                )
            }
        }

        let totalDuration = recordDurations.values.reduce(0, +)
        let completedRecords = includedRecords.filter {
            $0.outcome == .completed
        }
        let completedDuration = completedRecords.reduce(0) {
            $0 + (recordDurations[$1.id] ?? 0)
        }
        let count = includedRecords.count
        let byPurpose = purposeDurations.keys.sorted {
            $0.rawValue < $1.rawValue
        }.map {
            ProtectedTimePurposeAggregate(
                purpose: $0,
                protectedDuration: purposeDurations[$0] ?? 0,
                sessionCount: purposeCounts[$0] ?? 0
            )
        }
        let byDay = dayDurations.keys.sorted().map {
            ProtectedTimeDayAggregate(
                dayStart: $0,
                protectedDuration: dayDurations[$0] ?? 0
            )
        }

        return AttentionReport(
            intervalStart: interval.start,
            intervalEnd: interval.end,
            evidence: .protectedTimeRecords,
            recordCount: count,
            completedRecordCount: completedRecords.count,
            protectedDuration: totalDuration,
            completedProtectedDuration: completedDuration,
            averageProtectedDuration: count > 0 ? totalDuration / Double(count) : 0,
            longestProtectedDuration: recordDurations.values.max() ?? 0,
            completionRate: count > 0
                ? Double(completedRecords.count) / Double(count)
                : 0,
            activeDayCount: dayDurations.values.filter { $0 > 0 }.count,
            byPurpose: byPurpose,
            byDay: byDay
        )
    }

    private func add(
        _ interval: DateInterval,
        to dayDurations: inout [Date: TimeInterval],
        calendar: Calendar
    ) {
        var cursor = interval.start
        while cursor < interval.end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                return
            }
            let segmentEnd = min(interval.end, nextDay)
            dayDurations[dayStart, default: 0] += max(
                0,
                segmentEnd.timeIntervalSince(cursor)
            )
            cursor = segmentEnd
        }
    }
}

private enum ProtectedTimeIntervalMath {
    static func activeIntervals(for record: ProtectedTimeRecord) -> [DateInterval] {
        guard record.endedAt > record.startedAt else {
            return []
        }

        let recordInterval = DateInterval(
            start: record.startedAt,
            end: record.endedAt
        )
        let breaks = mergedBreaks(
            record.breakSegments
                .filter { $0.sourceID == record.sourceID && $0.endsAt > $0.startsAt }
                .compactMap {
                    DateInterval(start: $0.startsAt, end: $0.endsAt)
                        .intersection(with: recordInterval)
                }
        )

        guard !breaks.isEmpty else {
            return [recordInterval]
        }

        var intervals: [DateInterval] = []
        var cursor = recordInterval.start
        for breakInterval in breaks {
            if breakInterval.start > cursor {
                intervals.append(
                    DateInterval(start: cursor, end: breakInterval.start)
                )
            }
            cursor = max(cursor, breakInterval.end)
        }
        if cursor < recordInterval.end {
            intervals.append(
                DateInterval(start: cursor, end: recordInterval.end)
            )
        }
        return intervals
    }

    private static func mergedBreaks(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}

struct FocusSessionDomainEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var activeSessions: [FocusSession]
    var rhythms: [FocusRhythm]
    var rhythmPause: FocusRhythmPause?
    var boundaries: [AppBoundary]
    var intentionalBreaks: [IntentionalBreak]
    var earlyExitRequests: [FocusEarlyExitRequest]
    var history: ProtectedTimeHistory
    var createdAt: Date
    var updatedAt: Date
    var migratedAt: Date?

    init(
        schemaVersion: Int = FocusSessionDomainEnvelope.currentSchemaVersion,
        activeSessions: [FocusSession] = [],
        rhythms: [FocusRhythm] = [],
        rhythmPause: FocusRhythmPause? = nil,
        boundaries: [AppBoundary] = [],
        intentionalBreaks: [IntentionalBreak] = [],
        earlyExitRequests: [FocusEarlyExitRequest] = [],
        history: ProtectedTimeHistory = .empty,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        migratedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.activeSessions = activeSessions
        self.rhythms = rhythms
        self.rhythmPause = rhythmPause
        self.boundaries = boundaries
        self.intentionalBreaks = intentionalBreaks
        self.earlyExitRequests = earlyExitRequests
        self.history = history
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.migratedAt = migratedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 0
        activeSessions = try container.decodeIfPresent(
            [FocusSession].self,
            forKey: .activeSessions
        ) ?? []
        rhythms = try container.decodeIfPresent(
            [FocusRhythm].self,
            forKey: .rhythms
        ) ?? []
        rhythmPause = try container.decodeIfPresent(
            FocusRhythmPause.self,
            forKey: .rhythmPause
        )
        boundaries = try container.decodeIfPresent(
            [AppBoundary].self,
            forKey: .boundaries
        ) ?? []
        intentionalBreaks = try container.decodeIfPresent(
            [IntentionalBreak].self,
            forKey: .intentionalBreaks
        ) ?? []
        earlyExitRequests = try container.decodeIfPresent(
            [FocusEarlyExitRequest].self,
            forKey: .earlyExitRequests
        ) ?? []
        history = try container.decodeIfPresent(
            ProtectedTimeHistory.self,
            forKey: .history
        ) ?? .empty
        createdAt = try container.decodeIfPresent(
            Date.self,
            forKey: .createdAt
        ) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .updatedAt
        ) ?? createdAt
        migratedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .migratedAt
        )
    }
}

enum FocusSessionStoreError: Error, Equatable {
    case appGroupUnavailable
    case encodingFailed
    case decodingFailed
    case unsupportedSchema(Int)
    case verificationFailed
}

protocol FocusSessionDomainStoring {
    var hasStoredEnvelope: Bool { get }
    func load() throws -> FocusSessionDomainEnvelope
    func save(_ envelope: FocusSessionDomainEnvelope) throws
}

struct FocusSessionDomainMigrator {
    func migrate(
        _ envelope: FocusSessionDomainEnvelope,
        at date: Date = Date()
    ) throws -> FocusSessionDomainEnvelope {
        guard envelope.schemaVersion <= FocusSessionDomainEnvelope.currentSchemaVersion else {
            throw FocusSessionStoreError.unsupportedSchema(envelope.schemaVersion)
        }

        var migrated = envelope
        if migrated.schemaVersion < 1 {
            migrated.schemaVersion = 1
            migrated.migratedAt = date
            migrated.updatedAt = date
            if migrated.createdAt == Date(timeIntervalSince1970: 0) {
                migrated.createdAt = date
            }
        }
        return migrated
    }
}

final class AppGroupFocusSessionStore: FocusSessionDomainStoring {
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let envelopeKey = "the-climb.focus-session-domain.envelope"
    static let legacyEnvelopeKeys = [
        "the-climb.focus-session-domain.envelope.v1"
    ]

    private let defaults: UserDefaults?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let migrator: FocusSessionDomainMigrator
    private let now: () -> Date

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: AppGroupFocusSessionStore.appGroupID
        ),
        migrator: FocusSessionDomainMigrator = FocusSessionDomainMigrator(),
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.migrator = migrator
        self.now = now
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    var hasStoredEnvelope: Bool {
        guard let defaults = defaults else {
            return false
        }
        if defaults.data(forKey: Self.envelopeKey) != nil {
            return true
        }
        return Self.legacyEnvelopeKeys.contains {
            defaults.data(forKey: $0) != nil
        }
    }

    func load() throws -> FocusSessionDomainEnvelope {
        guard let defaults = defaults else {
            throw FocusSessionStoreError.appGroupUnavailable
        }
        guard let stored = storedData(in: defaults) else {
            return FocusSessionDomainEnvelope()
        }
        guard let decoded = try? decoder.decode(
            FocusSessionDomainEnvelope.self,
            from: stored.data
        ) else {
            throw FocusSessionStoreError.decodingFailed
        }

        let migrated = try migrator.migrate(decoded, at: now())
        if stored.key != Self.envelopeKey || migrated != decoded {
            try persist(migrated, in: defaults)
        }
        return migrated
    }

    func save(_ envelope: FocusSessionDomainEnvelope) throws {
        guard let defaults = defaults else {
            throw FocusSessionStoreError.appGroupUnavailable
        }
        let migrated = try migrator.migrate(envelope, at: now())
        try persist(migrated, in: defaults)
    }

    private func storedData(in defaults: UserDefaults) -> (key: String, data: Data)? {
        if let data = defaults.data(forKey: Self.envelopeKey) {
            return (Self.envelopeKey, data)
        }
        for key in Self.legacyEnvelopeKeys {
            if let data = defaults.data(forKey: key) {
                return (key, data)
            }
        }
        return nil
    }

    private func persist(
        _ envelope: FocusSessionDomainEnvelope,
        in defaults: UserDefaults
    ) throws {
        guard let data = try? encoder.encode(envelope) else {
            throw FocusSessionStoreError.encodingFailed
        }
        defaults.set(data, forKey: Self.envelopeKey)
        defaults.set(
            FocusSessionDomainEnvelope.currentSchemaVersion,
            forKey: "\(Self.envelopeKey).schema-version"
        )
        defaults.synchronize()

        guard let savedData = defaults.data(forKey: Self.envelopeKey),
              let savedEnvelope = try? decoder.decode(
                  FocusSessionDomainEnvelope.self,
                  from: savedData
              ),
              savedEnvelope == envelope else {
            throw FocusSessionStoreError.verificationFailed
        }
    }
}
