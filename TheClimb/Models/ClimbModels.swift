import Foundation

enum AgeGroup: String, CaseIterable, Codable, Identifiable {
    case earlyTeen = "13 - 15"
    case lateTeen = "16 - 18"
    case teen = "Teen"
    case college = "College"
    case youngAdult = "Young Adult"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .earlyTeen:
            "13 - 15"
        case .lateTeen:
            "16 - 18"
        case .teen:
            "Teen"
        case .college:
            "19 - 24"
        case .youngAdult:
            "25+"
        }
    }

    var maturityTitle: String {
        switch self {
        case .earlyTeen:
            "foundation"
        case .lateTeen, .teen:
            "identity and responsibility"
        case .college:
            "independence and ownership"
        case .youngAdult:
            "vocation and leadership"
        }
    }

    var difficultyAdjustment: Int {
        switch self {
        case .earlyTeen:
            -1
        case .teen, .lateTeen, .college:
            0
        case .youngAdult:
            1
        }
    }

    var baseMissionMinutes: Int {
        switch self {
        case .earlyTeen:
            15
        case .teen, .lateTeen:
            20
        case .college:
            25
        case .youngAdult:
            30
        }
    }

    var lessonMaturityLine: String {
        switch self {
        case .earlyTeen:
            "In this stage, growth usually starts with one clear choice made honestly before God, not with carrying pressure meant for someone older."
        case .lateTeen, .teen:
            "This season is forming identity, so the small choices around attention, pressure, temptation, and responsibility are shaping the kind of person you are becoming."
        case .college:
            "Independence reveals what you actually value, so faith has to become private discipline when nobody is managing your schedule for you."
        case .youngAdult:
            "Mature faith becomes stewardship: the way you handle work, money, relationships, leadership, and hidden integrity starts affecting more than only you."
        }
    }

    var missionMaturityLine: String {
        switch self {
        case .earlyTeen:
            "Keep the success condition simple enough to finish, then reflect honestly instead of trying to prove everything at once."
        case .lateTeen, .teen:
            "Make the boundary visible and finish one specific action that trains character under pressure."
        case .college:
            "Own the block before it starts: plan it, remove the distraction, finish the measurable work, and report the result honestly."
        case .youngAdult:
            "Treat this as stewardship: protect the full window, remove the known escape route, and follow through like someone else may be strengthened by your consistency."
        }
    }
}

enum Struggle: String, CaseIterable, Codable, Identifiable {
    case focus = "Focus"
    case discipline = "Discipline"
    case consistency = "Consistency"
    case purity = "Purity / Self-control"
    case prayer = "Prayer"
    case scripture = "Scripture"
    case socialPressure = "Social Pressure"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .purity:
            "Self-control"
        case .socialPressure:
            "Social"
        default:
            rawValue
        }
    }
}

enum MissionCategory: String, CaseIterable, Codable, Identifiable {
    case focus = "Focus"
    case faith = "Faith"
    case discipline = "Discipline"
    case selfControl = "Self-control"
    case social = "Social"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .focus: "timer"
        case .faith: "book.closed"
        case .discipline: "checkmark.seal"
        case .selfControl: "shield"
        case .social: "person.2"
        }
    }
}

enum MissionStatus: String, Codable {
    case pending
    case active
    case completed
    case failed
    case recovered
}

enum MoodRating: String, CaseIterable, Codable, Identifiable {
    case low = "Low"
    case steady = "Steady"
    case strong = "Strong"

    var id: String { rawValue }
}

struct UserProfile: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var ageGroup: AgeGroup
    var goals: [String]
    var mainStruggle: Struggle
    var streakGoal: Int
    var notificationHour: Int
    var notificationMinute: Int
    var ovrScore: Int
    var currentStreak: Int
    var longestStreak: Int
    var recoveryStreak: Int
    var appBlockingEnabled: Bool
    var joinedAt: Date
}

struct GrowthPathPersonalization: Equatable {
    var primaryGoal: String
    var category: MissionCategory
    var headline: String
    var planSummary: String
    var missionCue: String
    var devotionalFocus: String
    var reflectionPrompt: String
    var practicalAction: String
    var fallbackSummary: String
    var habitTitle: String
    var challengeTitle: String
    var previewMissionTitle: String
    var preparationChecklist: [String]

    static func resolve(for profile: UserProfile) -> GrowthPathPersonalization {
        resolve(
            goals: profile.goals,
            struggle: profile.mainStruggle,
            streakGoal: profile.streakGoal,
            ageGroup: profile.ageGroup
        )
    }

    static func resolve(
        goals: [String],
        struggle: Struggle,
        streakGoal: Int,
        ageGroup: AgeGroup
    ) -> GrowthPathPersonalization {
        let cleanedGoals = goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let primaryGoal = prioritizedGoal(from: cleanedGoals, struggle: struggle)
        let pace = paceLine(ageGroup: ageGroup, streakGoal: streakGoal)
        let intensity = intensityLine(streakGoal: streakGoal)

        let base: GrowthPathPersonalization
        switch primaryGoal.lowercased() {
        case let goal where goal.contains("phone"):
            base = GrowthPathPersonalization(
                primaryGoal: primaryGoal,
                category: .focus,
                headline: "Phone boundaries first",
                planSummary: "Missions will bias toward protected focus blocks, app blocking, and a cleaner morning phone rhythm.",
                missionCue: " This is tuned to your phone-use goal: remove the device, block the usual scroll apps, and protect the mission window.",
                devotionalFocus: "attention before God instead of reaction to your phone",
                reflectionPrompt: "What did your phone promise you, and what did obedience actually require?",
                practicalAction: "Choose the apps that pull you off course, block them during the mission, and keep the phone outside arm's reach.",
                fallbackSummary: "Block one distracting app, move your phone across the room, and complete five focused minutes before checking it again.",
                habitTitle: "Phone away before mission",
                challengeTitle: "Phone Boundary",
                previewMissionTitle: "Phone-free focus block",
                preparationChecklist: []
            )
        case let goal where goal.contains("procrastinating"):
            base = GrowthPathPersonalization(
                primaryGoal: primaryGoal,
                category: .discipline,
                headline: "Delayed tasks become the target",
                planSummary: "Missions will push one avoided responsibility into motion before easier work or entertainment.",
                missionCue: " This is tuned to your procrastination goal: name the delayed task, start before negotiating, and reach a visible stopping point.",
                devotionalFocus: "faithfulness in the task you keep delaying",
                reflectionPrompt: "What excuse sounded reasonable before you started?",
                practicalAction: "Write the delayed task in one sentence, set a timer, and complete the first meaningful step before anything easier.",
                fallbackSummary: "Work ten honest minutes on the delayed task, then write the next smallest step.",
                habitTitle: "Hard thing before easy thing",
                challengeTitle: "Delayed Task",
                previewMissionTitle: "First hard step",
                preparationChecklist: []
            )
        case let goal where goal.contains("prayer"):
            base = GrowthPathPersonalization(
                primaryGoal: primaryGoal,
                category: .faith,
                headline: "Prayer becomes the anchor",
                planSummary: "Missions will create simple prayer rhythms before the day gets noisy.",
                missionCue: " This is tuned to your prayer goal: begin with honest prayer, name one pressure, and turn it into one obedient next step.",
                devotionalFocus: "returning to God before the pressure grows",
                reflectionPrompt: "What did you bring to God instead of carrying alone?",
                practicalAction: "Pray out loud for two minutes, naming one desire, one fear, and one act of obedience.",
                fallbackSummary: "Pray three honest sentences: confession, help, and the next obedient step.",
                habitTitle: "Two-minute honest prayer",
                challengeTitle: "Prayer Rhythm",
                previewMissionTitle: "Prayer before pressure",
                preparationChecklist: []
            )
        case let goal where goal.contains("self-control") || goal.contains("bad habits"):
            base = GrowthPathPersonalization(
                primaryGoal: primaryGoal,
                category: .selfControl,
                headline: "Triggers get a plan",
                planSummary: "Missions will identify the first trigger, change the environment, and replace the habit with a better action.",
                missionCue: " This is tuned to your self-control goal: move before the trigger gets loud and choose the replacement action on purpose.",
                devotionalFocus: "a clean heart and a prepared boundary",
                reflectionPrompt: "Where did the first trigger show up, and how quickly did you move?",
                practicalAction: "Name the trigger, change locations, and do the replacement action for the full mission window.",
                fallbackSummary: "Change rooms, remove one trigger, pray honestly, and do a better action for five minutes.",
                habitTitle: "Trigger reset",
                challengeTitle: "Guardrail",
                previewMissionTitle: "Trigger reset block",
                preparationChecklist: []
            )
        case let goal where goal.contains("focus"):
            base = GrowthPathPersonalization(
                primaryGoal: primaryGoal,
                category: .focus,
                headline: "Focus gets protected",
                planSummary: "Missions will use one clear task, one protected timer, and fewer context switches.",
                missionCue: " This is tuned to your focus goal: choose one task, remove switches, and stay with it until the timer ends.",
                devotionalFocus: "undivided attention as obedience",
                reflectionPrompt: "What tried to pull your attention away first?",
                practicalAction: "Pick one task, close every unrelated app, and work until the timer ends.",
                fallbackSummary: "Close the extra tabs, set a five-minute timer, and complete the first visible step.",
                habitTitle: "One-task focus start",
                challengeTitle: "Deep Work",
                previewMissionTitle: "One-task focus block",
                preparationChecklist: []
            )
        case let goal where goal.contains("confidence"):
            base = GrowthPathPersonalization(
                primaryGoal: primaryGoal,
                category: .social,
                headline: "Courage becomes visible",
                planSummary: "Missions will build confidence through honest action, encouragement, and small visible steps.",
                missionCue: " This is tuned to your confidence goal: do one visible action that matches your values before waiting to feel ready.",
                devotionalFocus: "courage formed by truth instead of approval",
                reflectionPrompt: "What did you do before confidence showed up?",
                practicalAction: "Choose one honest message, apology, encouragement, or responsibility and act on it today.",
                fallbackSummary: "Send one sincere encouragement or take one visible step you have been avoiding.",
                habitTitle: "One courage step",
                challengeTitle: "Courage Step",
                previewMissionTitle: "One visible act",
                preparationChecklist: []
            )
        case let goal where goal.contains("consistent"):
            base = GrowthPathPersonalization(
                primaryGoal: primaryGoal,
                category: .discipline,
                headline: "Consistency gets simple",
                planSummary: "Missions will prioritize repeatable wins that protect the streak without overcomplicating the day.",
                missionCue: " This is tuned to your consistency goal: make the faithful version small enough to repeat and complete it today.",
                devotionalFocus: "showing up again when motivation drops",
                reflectionPrompt: "What made today's promise repeatable?",
                practicalAction: "Choose the smallest faithful version of the mission and complete it at the same time you want to repeat tomorrow.",
                fallbackSummary: "Complete the smallest honest version of the mission and schedule tomorrow's repeat.",
                habitTitle: "Same-time small win",
                challengeTitle: "No-Zero Chain",
                previewMissionTitle: "No-zero day",
                preparationChecklist: []
            )
        case let goal where goal.contains("god"):
            base = GrowthPathPersonalization(
                primaryGoal: primaryGoal,
                category: .faith,
                headline: "Faith leads the system",
                planSummary: "Missions will connect devotion, obedience, and a practical action instead of separating faith from discipline.",
                missionCue: " This is tuned to your faith goal: read, pray, and turn conviction into one concrete action.",
                devotionalFocus: "obedience that makes your faith practical",
                reflectionPrompt: "Where did devotion need to become action today?",
                practicalAction: "Read the verse slowly, pray one honest sentence, and take the action it points toward.",
                fallbackSummary: "Read one verse, pray one sentence, and do one concrete act of obedience.",
                habitTitle: "Verse into action",
                challengeTitle: "Obedience Practice",
                previewMissionTitle: "Scripture into action",
                preparationChecklist: []
            )
        default:
            base = GrowthPathPersonalization(
                primaryGoal: primaryGoal,
                category: .discipline,
                headline: "Discipline becomes daily",
                planSummary: "Missions will train one concrete act of obedience before the day drifts.",
                missionCue: " This is tuned to your discipline goal: choose the next right thing and finish it before negotiating with your mood.",
                devotionalFocus: "faithfulness in the small thing",
                reflectionPrompt: "What did you do before motivation caught up?",
                practicalAction: "Name the next right thing, start immediately, and finish one clear step.",
                fallbackSummary: "Do five minutes of the next right thing and write why it mattered.",
                habitTitle: "Next right thing",
                challengeTitle: "Hard Thing First",
                previewMissionTitle: "Next right thing",
                preparationChecklist: []
            )
        }

        return GrowthPathPersonalization(
            primaryGoal: base.primaryGoal,
            category: base.category,
            headline: base.headline,
            planSummary: "\(base.planSummary) \(pace) \(intensity)",
            missionCue: "\(base.missionCue) Your current struggle is \(struggle.shortLabel.lowercased()), so the plan will train that pressure point directly.",
            devotionalFocus: base.devotionalFocus,
            reflectionPrompt: base.reflectionPrompt,
            practicalAction: base.practicalAction,
            fallbackSummary: base.fallbackSummary,
            habitTitle: base.habitTitle,
            challengeTitle: base.challengeTitle,
            previewMissionTitle: base.previewMissionTitle,
            preparationChecklist: [
                "Prioritizing \(base.primaryGoal)",
                "Training \(struggle.shortLabel) with \(base.challengeTitle.lowercased()) missions",
                "Setting a \(streakGoal)-day streak rhythm",
                "Matching the pace to \(ageGroup.rawValue.lowercased()) life"
            ]
        )
    }

    private static func prioritizedGoal(from goals: [String], struggle: Struggle) -> String {
        let fallback = fallbackGoal(for: struggle)
        guard !goals.isEmpty else { return fallback }
        let priorityTerms = [
            "phone",
            "procrastinating",
            "prayer",
            "self-control",
            "bad habits",
            "focus",
            "confidence",
            "consistent",
            "god",
            "discipline"
        ]

        for term in priorityTerms {
            if let match = goals.first(where: { $0.lowercased().contains(term) }) {
                return match
            }
        }

        return goals[0]
    }

    private static func fallbackGoal(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "Improve focus"
        case .discipline:
            "Build discipline"
        case .consistency:
            "Become consistent"
        case .purity:
            "Strengthen self-control"
        case .prayer:
            "Improve prayer life"
        case .scripture:
            "Grow closer to God"
        case .socialPressure:
            "Build confidence"
        }
    }

    private static func paceLine(ageGroup: AgeGroup, streakGoal: Int) -> String {
        switch ageGroup {
        case .earlyTeen:
            "The first missions stay concrete, short, and clear enough to win around school, practice, or family routines."
        case .teen, .lateTeen:
            "The first missions stay concrete and short enough to win after school or practice."
        case .college:
            "The plan expects busier days, so missions use clear blocks that fit around class and work."
        case .youngAdult:
            "The plan uses a mature rhythm with slightly longer blocks and stronger follow-through."
        }
    }

    private static func intensityLine(streakGoal: Int) -> String {
        switch streakGoal {
        case ..<15:
            "Your streak goal starts with quick proof, not heavy pressure."
        case 15..<45:
            "Your streak goal is set for a serious reset."
        default:
            "Your streak goal is long-term, so difficulty will rise more deliberately as consistency grows."
        }
    }
}

struct Devotional: Identifiable, Codable, Equatable {
    var id: String
    var date: Date
    var title: String
    var bibleVerse: String
    var verseText: String?
    var explanation: String
    var reflectionQuestion: String
    var practicalAction: String
    var struggle: Struggle
}

enum DailyContentKind: String, Codable, CaseIterable, Identifiable {
    case mission
    case devotional

    var id: String { rawValue }
}

enum DailyContentFeedbackRating: String, Codable, CaseIterable, Identifiable {
    case good
    case tooEasy
    case tooHard
    case notRelevant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .good:
            "Good"
        case .tooEasy:
            "Too easy"
        case .tooHard:
            "Too hard"
        case .notRelevant:
            "Not relevant"
        }
    }
}

struct DailyContentFeedback: Identifiable, Codable, Equatable {
    var id: String
    var contentID: String
    var contentKind: DailyContentKind
    var rating: DailyContentFeedbackRating
    var titleSnapshot: String
    var createdAt: Date
}

struct Mission: Identifiable, Codable, Equatable {
    var id: String
    var date: Date
    var title: String
    var summary: String
    var category: MissionCategory
    var durationMinutes: Int
    var difficulty: Int
    var status: MissionStatus
    var fallbackTitle: String
    var fallbackSummary: String
    var extraChallenges: [String]
    var devotionalID: String
    var appBlockingEnabled: Bool
}

struct ReflectionEntry: Identifiable, Codable, Equatable {
    var id: String
    var date: Date
    var missionID: String
    var hardestPart: String
    var lessonLearned: String
    var effortRating: Int
    var improvementPlan: String
    var mood: MoodRating
    var failureReason: String?
}

struct MemorizedVerse: Identifiable, Codable, Equatable {
    var id: String
    var reference: String
    var text: String
    var sourceTitle: String
    var struggle: Struggle?
    var addedAt: Date
    var lastReviewedAt: Date?
    var nextReviewAt: Date
    var reviewCount: Int
    var correctCount: Int
    var isArchived: Bool

    var mastery: Double {
        guard reviewCount > 0 else { return 0 }
        let accuracy = Double(correctCount) / Double(max(reviewCount, 1))
        let repetition = min(Double(reviewCount) / 5.0, 1)
        return min(max((accuracy * 0.70) + (repetition * 0.30), 0), 1)
    }

    var isDue: Bool {
        !isArchived && nextReviewAt <= Date()
    }

    var nextReviewLabel: String {
        if isDue { return "Due now" }
        if Calendar.current.isDateInTomorrow(nextReviewAt) { return "Tomorrow" }
        if Calendar.current.isDate(nextReviewAt, inSameDayAs: Date()) { return "Today" }
        return nextReviewAt.formatted(date: .abbreviated, time: .omitted)
    }
}

struct ProgressSnapshot: Identifiable, Codable, Equatable {
    var id: String
    var date: Date
    var ovrScore: Int
    var currentStreak: Int
    var completionRate: Double
    var completedMissions: Int
    var failedMissions: Int
}

struct NotificationFatigueState: Codable, Equatable {
    var ignoredDailyReminderDates: [Date]
    var engagedReminderDates: [Date]
    var dailyReminderPausedUntil: Date?

    init(
        ignoredDailyReminderDates: [Date] = [],
        engagedReminderDates: [Date] = [],
        dailyReminderPausedUntil: Date? = nil
    ) {
        self.ignoredDailyReminderDates = Self.normalizedDays(ignoredDailyReminderDates)
        self.engagedReminderDates = Self.normalizedDays(engagedReminderDates)
        self.dailyReminderPausedUntil = dailyReminderPausedUntil
    }

    mutating func recordIgnoredDailyReminder(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard !ignoredDailyReminderDates.contains(where: { calendar.isDate($0, inSameDayAs: day) }) else {
            return false
        }

        ignoredDailyReminderDates.append(day)
        ignoredDailyReminderDates = Self.recentDays(ignoredDailyReminderDates, endingAt: date, calendar: calendar)

        if ignoredCount(inLastDays: 7, endingAt: date, calendar: calendar) >= 4 {
            dailyReminderPausedUntil = calendar.date(byAdding: .day, value: 2, to: day)
        }
        return true
    }

    mutating func recordReminderEngagement(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        var didChange = false
        if !engagedReminderDates.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            engagedReminderDates.append(day)
            engagedReminderDates = Self.recentDays(engagedReminderDates, endingAt: date, calendar: calendar)
            didChange = true
        }

        if dailyReminderPausedUntil != nil {
            dailyReminderPausedUntil = nil
            didChange = true
        }

        return didChange
    }

    func shouldSendDailyReminder(now: Date = Date()) -> Bool {
        guard let dailyReminderPausedUntil else { return true }
        return dailyReminderPausedUntil <= now
    }

    func shouldSendSecondaryNudges(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        ignoredCount(inLastDays: 7, endingAt: now, calendar: calendar) < 3
    }

    func ignoredCount(inLastDays days: Int, endingAt date: Date = Date(), calendar: Calendar = .current) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -max(days - 1, 0), to: calendar.startOfDay(for: date)) ?? date
        return ignoredDailyReminderDates.filter { $0 >= cutoff }.count
    }

    private static func normalizedDays(_ dates: [Date], calendar: Calendar = .current) -> [Date] {
        Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
    }

    private static func recentDays(_ dates: [Date], endingAt date: Date, calendar: Calendar) -> [Date] {
        let cutoff = calendar.date(byAdding: .day, value: -20, to: calendar.startOfDay(for: date)) ?? date
        return normalizedDays(dates, calendar: calendar).filter { $0 >= cutoff }
    }
}

struct GrowthHabit: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var cadence: String
    var isEnabled: Bool
    var completedDates: [Date]
    var lastCompletedAt: Date?

    init(
        id: String,
        title: String,
        cadence: String,
        isEnabled: Bool,
        completedDates: [Date] = [],
        lastCompletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.cadence = cadence
        self.isEnabled = isEnabled
        self.completedDates = Self.normalizedCompletionDates(completedDates)
        self.lastCompletedAt = lastCompletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case cadence
        case isEnabled
        case completedDates
        case lastCompletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        cadence = try container.decode(String.self, forKey: .cadence)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        completedDates = Self.normalizedCompletionDates(
            try container.decodeIfPresent([Date].self, forKey: .completedDates) ?? []
        )
        lastCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastCompletedAt)
    }

    func isCompleted(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        return completedDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    func completionsInLastSevenDays(endingAt date: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: date)
        let visibleDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        return visibleDays.filter { day in
            completedDates.contains { calendar.isDate($0, inSameDayAs: day) }
        }.count
    }

    func completionRateInLastSevenDays(endingAt date: Date = Date(), calendar: Calendar = .current) -> Double {
        Double(completionsInLastSevenDays(endingAt: date, calendar: calendar)) / 7
    }

    func streak(endingAt date: Date = Date(), calendar: Calendar = .current) -> Int {
        let completedDays = Set(completedDates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let startDay: Date

        if completedDays.contains(today) {
            startDay = today
        } else if completedDays.contains(yesterday) {
            startDay = yesterday
        } else {
            return 0
        }

        var count = 0
        var cursor = startDay
        while completedDays.contains(cursor) {
            count += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }
        return count
    }

    func bestStreak(calendar: Calendar = .current) -> Int {
        let days = Self.normalizedCompletionDates(completedDates)
        guard !days.isEmpty else { return 0 }

        var best = 1
        var current = 1
        for index in days.indices.dropFirst() {
            let previous = days[days.index(before: index)]
            let expected = calendar.date(byAdding: .day, value: 1, to: previous) ?? previous
            if calendar.isDate(days[index], inSameDayAs: expected) {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
        }
        return best
    }

    mutating func toggleCompletion(on date: Date = Date(), calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        if let index = completedDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: day) }) {
            completedDates.remove(at: index)
            if let lastCompletedAt, calendar.isDate(lastCompletedAt, inSameDayAs: day) {
                self.lastCompletedAt = completedDates.sorted().last
            }
        } else {
            completedDates.append(day)
            lastCompletedAt = date
        }
        completedDates = Self.normalizedCompletionDates(completedDates, calendar: calendar)
    }

    private static func normalizedCompletionDates(_ dates: [Date], calendar: Calendar = .current) -> [Date] {
        Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted()
    }
}

struct GrowthChallenge: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var detail: String
    var category: MissionCategory
    var daysRemaining: Int
    var difficulty: Int
    var targetCompletions: Int
    var completedCount: Int

    init(
        id: String,
        title: String,
        detail: String,
        category: MissionCategory,
        daysRemaining: Int,
        difficulty: Int = 1,
        targetCompletions: Int = 3,
        completedCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.daysRemaining = daysRemaining
        self.difficulty = min(max(difficulty, 1), 5)
        self.targetCompletions = max(targetCompletions, 1)
        self.completedCount = min(max(completedCount, 0), max(targetCompletions, 1))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case category
        case daysRemaining
        case difficulty
        case targetCompletions
        case completedCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        category = try container.decode(MissionCategory.self, forKey: .category)
        daysRemaining = try container.decode(Int.self, forKey: .daysRemaining)
        difficulty = min(max(try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1, 1), 5)
        targetCompletions = max(try container.decodeIfPresent(Int.self, forKey: .targetCompletions) ?? 3, 1)
        completedCount = min(
            max(try container.decodeIfPresent(Int.self, forKey: .completedCount) ?? 0, 0),
            targetCompletions
        )
    }

    var progress: Double {
        guard targetCompletions > 0 else { return 0 }
        return min(Double(completedCount) / Double(targetCompletions), 1)
    }

    var isComplete: Bool {
        completedCount >= targetCompletions
    }
}

struct AccountabilityPartner: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var focus: Struggle
    var lastCheckIn: String
    var checkInCount: Int
    var nudgeCount: Int
    var encouragementCount: Int
    var lastInteraction: String
    var inviteCode: String?
    var linkedUserID: String?
    var isPending: Bool
    var lastCheckInDate: Date?
    var sharedStreak: Int
    var weeklyCompletions: Int

    init(
        id: String,
        name: String,
        focus: Struggle,
        lastCheckIn: String,
        checkInCount: Int = 0,
        nudgeCount: Int = 0,
        encouragementCount: Int = 0,
        lastInteraction: String = "No action yet",
        inviteCode: String? = nil,
        linkedUserID: String? = nil,
        isPending: Bool = false,
        lastCheckInDate: Date? = nil,
        sharedStreak: Int = 0,
        weeklyCompletions: Int = 0
    ) {
        self.id = id
        self.name = name
        self.focus = focus
        self.lastCheckIn = lastCheckIn
        self.checkInCount = checkInCount
        self.nudgeCount = nudgeCount
        self.encouragementCount = encouragementCount
        self.lastInteraction = lastInteraction
        self.inviteCode = inviteCode
        self.linkedUserID = linkedUserID
        self.isPending = isPending
        self.lastCheckInDate = lastCheckInDate
        self.sharedStreak = max(0, sharedStreak)
        self.weeklyCompletions = min(max(weeklyCompletions, 0), 7)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case focus
        case lastCheckIn
        case checkInCount
        case nudgeCount
        case encouragementCount
        case lastInteraction
        case inviteCode
        case linkedUserID
        case isPending
        case lastCheckInDate
        case sharedStreak
        case weeklyCompletions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        focus = try container.decode(Struggle.self, forKey: .focus)
        lastCheckIn = try container.decode(String.self, forKey: .lastCheckIn)
        checkInCount = try container.decodeIfPresent(Int.self, forKey: .checkInCount) ?? 0
        nudgeCount = try container.decodeIfPresent(Int.self, forKey: .nudgeCount) ?? 0
        encouragementCount = try container.decodeIfPresent(Int.self, forKey: .encouragementCount) ?? 0
        lastInteraction = try container.decodeIfPresent(String.self, forKey: .lastInteraction) ?? "No action yet"
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode)
        linkedUserID = try container.decodeIfPresent(String.self, forKey: .linkedUserID)
        isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
        lastCheckInDate = try container.decodeIfPresent(Date.self, forKey: .lastCheckInDate)
        sharedStreak = max(0, try container.decodeIfPresent(Int.self, forKey: .sharedStreak) ?? 0)
        weeklyCompletions = min(max(try container.decodeIfPresent(Int.self, forKey: .weeklyCompletions) ?? 0, 0), 7)
    }
}

enum AccountabilityPartnerAction: String, Codable {
    case checkIn
    case nudge
    case encouragement
}

struct ClimbGroup: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var subtitle: String
    var members: Int
    var activeChallenge: String
    var isJoined: Bool
    var ownerID: String
    var adminIDs: [String]
    var memberIDs: [String]
    var memberNames: [String: String]

    init(
        id: String,
        name: String,
        subtitle: String,
        members: Int,
        activeChallenge: String,
        isJoined: Bool = false,
        ownerID: String = "",
        adminIDs: [String] = [],
        memberIDs: [String] = [],
        memberNames: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.members = members
        self.activeChallenge = activeChallenge
        self.isJoined = isJoined
        self.ownerID = ownerID
        self.adminIDs = adminIDs
        self.memberIDs = memberIDs
        self.memberNames = memberNames
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case subtitle
        case members
        case activeChallenge
        case isJoined
        case ownerID
        case adminIDs
        case memberIDs
        case memberNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        members = try container.decode(Int.self, forKey: .members)
        activeChallenge = try container.decode(String.self, forKey: .activeChallenge)
        isJoined = try container.decodeIfPresent(Bool.self, forKey: .isJoined) ?? false
        ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID) ?? ""
        adminIDs = try container.decodeIfPresent([String].self, forKey: .adminIDs) ?? []
        memberIDs = try container.decodeIfPresent([String].self, forKey: .memberIDs) ?? []
        memberNames = try container.decodeIfPresent([String: String].self, forKey: .memberNames) ?? [:]
    }

    func isOwner(_ userID: String?) -> Bool {
        guard let userID else { return false }
        return ownerID == userID
    }

    func isAdmin(_ userID: String?) -> Bool {
        guard let userID else { return false }
        return ownerID == userID || adminIDs.contains(userID)
    }

    func displayName(for memberID: String) -> String {
        let name = memberNames[memberID]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        return "Member \(memberID.prefix(6))"
    }

    var normalizedMemberIDs: [String] {
        if memberIDs.isEmpty, ownerID.isEmpty == false {
            return [ownerID]
        }
        return memberIDs
    }
}

struct EncouragementPost: Identifiable, Codable, Equatable {
    var id: String
    var authorID: String
    var author: String
    var body: String
    var createdAt: Date
    var amenCount: Int

    init(
        id: String,
        authorID: String,
        author: String,
        body: String,
        createdAt: Date,
        amenCount: Int
    ) {
        self.id = id
        self.authorID = authorID
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.amenCount = amenCount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case authorID
        case author
        case body
        case createdAt
        case amenCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decode(String.self, forKey: .author)
        authorID = try container.decodeIfPresent(String.self, forKey: .authorID) ?? "legacy-\(author.lowercased())"
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        amenCount = try container.decode(Int.self, forKey: .amenCount)
    }
}

enum ModerationReason: String, Codable, CaseIterable, Identifiable {
    case harassment
    case hate
    case sexualContent
    case spam
    case selfHarm
    case unsafe
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .harassment:
            "Harassment"
        case .hate:
            "Hate or slurs"
        case .sexualContent:
            "Sexual content"
        case .spam:
            "Spam"
        case .selfHarm:
            "Self-harm"
        case .unsafe:
            "Unsafe content"
        case .other:
            "Other"
        }
    }
}

enum ModerationSeverity: String, Codable {
    case low
    case medium
    case high
    case urgent
}

enum ModerationStatus: String, Codable {
    case submitted
    case hiddenLocally
    case reviewed
}

struct ModerationReport: Identifiable, Codable, Equatable {
    var id: String
    var postID: String
    var reportedUserID: String
    var reportedByUserID: String
    var reason: String
    var category: ModerationReason
    var severity: ModerationSeverity
    var status: ModerationStatus
    var postBody: String
    var postAuthorName: String
    var createdAt: Date

    init(
        id: String,
        postID: String,
        reportedUserID: String,
        reportedByUserID: String,
        reason: String,
        category: ModerationReason = .other,
        severity: ModerationSeverity = .medium,
        status: ModerationStatus = .submitted,
        postBody: String,
        postAuthorName: String = "",
        createdAt: Date
    ) {
        self.id = id
        self.postID = postID
        self.reportedUserID = reportedUserID
        self.reportedByUserID = reportedByUserID
        self.reason = reason
        self.category = category
        self.severity = severity
        self.status = status
        self.postBody = postBody
        self.postAuthorName = postAuthorName
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case postID
        case reportedUserID
        case reportedByUserID
        case reason
        case category
        case severity
        case status
        case postBody
        case postAuthorName
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        postID = try container.decode(String.self, forKey: .postID)
        reportedUserID = try container.decode(String.self, forKey: .reportedUserID)
        reportedByUserID = try container.decode(String.self, forKey: .reportedByUserID)
        reason = try container.decode(String.self, forKey: .reason)
        category = try container.decodeIfPresent(ModerationReason.self, forKey: .category) ?? .other
        severity = try container.decodeIfPresent(ModerationSeverity.self, forKey: .severity) ?? .medium
        status = try container.decodeIfPresent(ModerationStatus.self, forKey: .status) ?? .submitted
        postBody = try container.decode(String.self, forKey: .postBody)
        postAuthorName = try container.decodeIfPresent(String.self, forKey: .postAuthorName) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

struct LeaderboardEntry: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var ovrScore: Int
    var streak: Int
}

extension Array where Element == LeaderboardEntry {
    var sortedForGlobalRank: [LeaderboardEntry] {
        sorted {
            if $0.ovrScore == $1.ovrScore {
                if $0.streak == $1.streak {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.streak > $1.streak
            }
            return $0.ovrScore > $1.ovrScore
        }
    }
}

struct MonthlyReflectionLetter: Identifiable, Codable, Equatable {
    var id: String
    var monthStart: Date
    var title: String
    var opening: String
    var body: String
    var scriptureReference: String
    var closingPrompt: String
    var generatedAt: Date
    var completedMissions: Int
    var failedMissions: Int
    var ovrDelta: Int
    var averageEffort: Double

    init(
        id: String,
        monthStart: Date,
        title: String,
        opening: String,
        body: String,
        scriptureReference: String,
        closingPrompt: String,
        generatedAt: Date,
        completedMissions: Int,
        failedMissions: Int,
        ovrDelta: Int,
        averageEffort: Double
    ) {
        self.id = id
        self.monthStart = monthStart
        self.title = title
        self.opening = opening
        self.body = body
        self.scriptureReference = scriptureReference
        self.closingPrompt = closingPrompt
        self.generatedAt = generatedAt
        self.completedMissions = completedMissions
        self.failedMissions = failedMissions
        self.ovrDelta = ovrDelta
        self.averageEffort = averageEffort
    }
}

enum AchievementCategory: String, CaseIterable, Codable, Identifiable, Equatable {
    case focus = "Focus"
    case streak = "Streak"
    case prayer = "Prayer"
    case scripture = "Scripture"
    case habits = "Habits"
    case recovery = "Recovery"
    case community = "Community"
    case growth = "Growth"

    var id: String { rawValue }
}

enum AchievementTone: String, Codable, Equatable {
    case green
    case gold
    case blue
    case red
    case sage
    case warm
}

struct PrayerAchievementStats: Equatable {
    var sessionsCompleted: Int
    var minutesCompleted: Int

    static let empty = PrayerAchievementStats(sessionsCompleted: 0, minutesCompleted: 0)
}

struct AchievementProgress: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var detail: String
    var systemImage: String
    var category: AchievementCategory
    var tone: AchievementTone
    var currentValue: Int
    var targetValue: Int
    var unlockedAt: Date?

    var isUnlocked: Bool {
        currentValue >= targetValue
    }

    var progress: Double {
        guard targetValue > 0 else { return isUnlocked ? 1 : 0 }
        return min(max(Double(currentValue) / Double(targetValue), 0), 1)
    }

    var progressLabel: String {
        isUnlocked ? "Unlocked" : "\(min(currentValue, targetValue))/\(targetValue)"
    }

    func preservingUnlock(_ unlock: AchievementUnlock) -> AchievementProgress {
        var updated = self
        updated.currentValue = max(currentValue, targetValue)
        updated.unlockedAt = unlock.unlockedAt
        return updated
    }
}

struct AchievementUnlock: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var systemImage: String
    var category: AchievementCategory
    var tone: AchievementTone
    var unlockedAt: Date

    init(
        id: String,
        title: String,
        systemImage: String,
        category: AchievementCategory,
        tone: AchievementTone,
        unlockedAt: Date
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.category = category
        self.tone = tone
        self.unlockedAt = unlockedAt
    }

    init?(achievement: AchievementProgress, fallbackDate: Date = Date()) {
        guard achievement.isUnlocked else { return nil }
        self.init(
            id: achievement.id,
            title: achievement.title,
            systemImage: achievement.systemImage,
            category: achievement.category,
            tone: achievement.tone,
            unlockedAt: achievement.unlockedAt ?? fallbackDate
        )
    }
}

enum AchievementEngine {
    static func build(
        profile: UserProfile?,
        missions: [Mission],
        journalEntries: [ReflectionEntry],
        habits: [GrowthHabit],
        groups: [ClimbGroup],
        posts: [EncouragementPost],
        partners: [AccountabilityPartner],
        verseMemory: [MemorizedVerse],
        prayerStats: PrayerAchievementStats
    ) -> [AchievementProgress] {
        guard let profile else { return [] }

        let completedMissions = missions.filter { $0.status == .completed || $0.status == .recovered }
        let recoveredMissions = missions.filter { $0.status == .recovered }
        let highestCompletedDifficulty = completedMissions.map(\.difficulty).max() ?? 0
        let journalCount = journalEntries.count
        let habitCompletionCount = habits.reduce(0) { $0 + $1.completedDates.count }
        let joinedGroupCount = groups.filter(\.isJoined).count
        let userPostCount = posts.filter { $0.authorID == profile.id }.count
        let activeVerseCount = verseMemory.filter { !$0.isArchived }.count
        let masteredVerseCount = verseMemory.filter { !$0.isArchived && $0.mastery >= 0.80 }.count
        let ovrMilestone = profile.ovrScore
        let partnerCount = partners.count

        return [
            achievement(
                id: "first-focus",
                title: "First Yes",
                subtitle: "Complete your first protected focus block.",
                detail: "A real start beats a perfect plan.",
                systemImage: "checkmark.seal.fill",
                category: .focus,
                tone: .green,
                current: completedMissions.count,
                target: 1,
                unlockedAt: completedMissions.sorted { $0.date < $1.date }.first?.date
            ),
            achievement(
                id: "shield-bearer",
                title: "Shield Bearer",
                subtitle: "Turn on app blocking for focus sessions.",
                detail: "Your attention needs a wall before it needs more willpower.",
                systemImage: "lock.shield.fill",
                category: .focus,
                tone: .sage,
                current: profile.appBlockingEnabled ? 1 : 0,
                target: 1,
                unlockedAt: profile.appBlockingEnabled ? profile.joinedAt : nil
            ),
            achievement(
                id: "three-day-return",
                title: "Three-Day Return",
                subtitle: "Hold a 3-day mission streak.",
                detail: "Consistency starts looking real on day three.",
                systemImage: "flame.fill",
                category: .streak,
                tone: .gold,
                current: profile.longestStreak,
                target: 3,
                unlockedAt: profile.longestStreak >= 3 ? profile.joinedAt : nil
            ),
            achievement(
                id: "week-of-obedience",
                title: "Week of Obedience",
                subtitle: "Hold a 7-day mission streak.",
                detail: "Seven days is not luck. It is return repeated.",
                systemImage: "calendar.badge.checkmark",
                category: .streak,
                tone: .gold,
                current: profile.longestStreak,
                target: 7,
                unlockedAt: profile.longestStreak >= 7 ? profile.joinedAt : nil
            ),
            achievement(
                id: "thirty-day-path",
                title: "Thirty-Day Path",
                subtitle: "Hold a 30-day mission streak.",
                detail: "The path becomes visible when obedience gets ordinary.",
                systemImage: "mountain.2.fill",
                category: .streak,
                tone: .warm,
                current: profile.longestStreak,
                target: 30,
                unlockedAt: profile.longestStreak >= 30 ? profile.joinedAt : nil
            ),
            achievement(
                id: "examined-heart",
                title: "Examined Heart",
                subtitle: "Submit 5 honest reflections.",
                detail: "Reflection turns behavior into formation.",
                systemImage: "book.pages.fill",
                category: .growth,
                tone: .blue,
                current: journalCount,
                target: 5,
                unlockedAt: journalEntries.sorted { $0.date < $1.date }.dropFirst(4).first?.date
            ),
            achievement(
                id: "return-after-miss",
                title: "Return After Miss",
                subtitle: "Complete a recovery mission.",
                detail: "A miss is not the end when return becomes your reflex.",
                systemImage: "arrow.counterclockwise.circle.fill",
                category: .recovery,
                tone: .red,
                current: recoveredMissions.count,
                target: 1,
                unlockedAt: recoveredMissions.sorted { $0.date < $1.date }.first?.date
            ),
            achievement(
                id: "quiet-minutes",
                title: "Quiet Minutes",
                subtitle: "Complete 30 minutes of prayer.",
                detail: "Small quiet minutes become a practiced refuge.",
                systemImage: "hands.sparkles.fill",
                category: .prayer,
                tone: .warm,
                current: prayerStats.minutesCompleted,
                target: 30,
                unlockedAt: prayerStats.minutesCompleted >= 30 ? profile.joinedAt : nil
            ),
            achievement(
                id: "prayer-rhythm",
                title: "Prayer Rhythm",
                subtitle: "Complete 3 prayer sessions.",
                detail: "Prayer becomes stronger when return has a rhythm.",
                systemImage: "timer.circle.fill",
                category: .prayer,
                tone: .sage,
                current: prayerStats.sessionsCompleted,
                target: 3,
                unlockedAt: prayerStats.sessionsCompleted >= 3 ? profile.joinedAt : nil
            ),
            achievement(
                id: "word-kept",
                title: "Word Kept",
                subtitle: "Save a verse to memory.",
                detail: "A verse kept close is a weapon against drift.",
                systemImage: "text.book.closed.fill",
                category: .scripture,
                tone: .blue,
                current: activeVerseCount,
                target: 1,
                unlockedAt: verseMemory.filter { !$0.isArchived }.sorted { $0.addedAt < $1.addedAt }.first?.addedAt
            ),
            achievement(
                id: "scripture-rooted",
                title: "Scripture Rooted",
                subtitle: "Master 3 memory verses.",
                detail: "Memory turns the Word into a ready answer.",
                systemImage: "leaf.fill",
                category: .scripture,
                tone: .green,
                current: masteredVerseCount,
                target: 3,
                unlockedAt: masteredVerseCount >= 3 ? profile.joinedAt : nil
            ),
            achievement(
                id: "habit-keeper",
                title: "Habit Keeper",
                subtitle: "Complete 10 habit check-ins.",
                detail: "The unseen reps are where the person changes.",
                systemImage: "checklist.checked",
                category: .habits,
                tone: .green,
                current: habitCompletionCount,
                target: 10,
                unlockedAt: habitCompletionCount >= 10 ? profile.joinedAt : nil
            ),
            achievement(
                id: "pressure-level",
                title: "Pressure Level",
                subtitle: "Complete a difficulty 3+ focus block.",
                detail: "Growth requires resistance once the easy wins are done.",
                systemImage: "bolt.shield.fill",
                category: .focus,
                tone: .gold,
                current: highestCompletedDifficulty,
                target: 3,
                unlockedAt: completedMissions.filter { $0.difficulty >= 3 }.sorted { $0.date < $1.date }.first?.date
            ),
            achievement(
                id: "conviction-level",
                title: "Conviction Level",
                subtitle: "Reach 70 OVR through real behavior.",
                detail: "OVR is not identity. It is evidence of follow-through.",
                systemImage: "chart.line.uptrend.xyaxis.circle.fill",
                category: .growth,
                tone: .sage,
                current: ovrMilestone,
                target: 70,
                unlockedAt: ovrMilestone >= 70 ? profile.joinedAt : nil
            ),
            achievement(
                id: "circle-builder",
                title: "Circle Builder",
                subtitle: "Join a group or add an accountability partner.",
                detail: "Discipline grows stronger when someone can ask if you returned.",
                systemImage: "person.2.badge.gearshape.fill",
                category: .community,
                tone: .blue,
                current: max(joinedGroupCount, partnerCount),
                target: 1,
                unlockedAt: max(joinedGroupCount, partnerCount) > 0 ? profile.joinedAt : nil
            ),
            achievement(
                id: "encourager",
                title: "Encourager",
                subtitle: "Post one encouragement to the community.",
                detail: "Pressure gets lighter when someone else is strengthened.",
                systemImage: "message.badge.filled.fill",
                category: .community,
                tone: .warm,
                current: userPostCount,
                target: 1,
                unlockedAt: posts.filter { $0.authorID == profile.id }.sorted { $0.createdAt < $1.createdAt }.first?.createdAt
            )
        ]
    }

    private static func achievement(
        id: String,
        title: String,
        subtitle: String,
        detail: String,
        systemImage: String,
        category: AchievementCategory,
        tone: AchievementTone,
        current: Int,
        target: Int,
        unlockedAt: Date?
    ) -> AchievementProgress {
        AchievementProgress(
            id: id,
            title: title,
            subtitle: subtitle,
            detail: detail,
            systemImage: systemImage,
            category: category,
            tone: tone,
            currentValue: max(0, current),
            targetValue: max(1, target),
            unlockedAt: current >= target ? unlockedAt : nil
        )
    }

    static func merged(
        _ achievements: [AchievementProgress],
        with storedUnlocks: [AchievementUnlock]
    ) -> [AchievementProgress] {
        let unlocksByID = Dictionary(uniqueKeysWithValues: storedUnlocks.map { ($0.id, $0) })
        return achievements.map { achievement in
            guard let unlock = unlocksByID[achievement.id] else { return achievement }
            return achievement.preservingUnlock(unlock)
        }
    }

    static func unlocks(from achievements: [AchievementProgress]) -> [AchievementUnlock] {
        achievements
            .compactMap { AchievementUnlock(achievement: $0) }
            .sorted {
                if $0.unlockedAt == $1.unlockedAt {
                    return $0.title < $1.title
                }
                return $0.unlockedAt > $1.unlockedAt
            }
    }
}

struct AppStateSnapshot: Codable, Equatable {
    var profile: UserProfile?
    var missions: [Mission]
    var devotionals: [Devotional]
    var journalEntries: [ReflectionEntry]
    var progress: [ProgressSnapshot]
    var habits: [GrowthHabit]
    var challenges: [GrowthChallenge]
    var groups: [ClimbGroup]
    var posts: [EncouragementPost]
    var partners: [AccountabilityPartner]
    var leaderboard: [LeaderboardEntry]
    var blockedUserIDs: [String]
    var moderationReports: [ModerationReport]
    var contentFeedback: [DailyContentFeedback]
    var notificationFatigue: NotificationFatigueState
    var monthlyLetters: [MonthlyReflectionLetter]
    var verseMemory: [MemorizedVerse]
    var achievementUnlocks: [AchievementUnlock]

    init(
        profile: UserProfile?,
        missions: [Mission],
        devotionals: [Devotional],
        journalEntries: [ReflectionEntry],
        progress: [ProgressSnapshot],
        habits: [GrowthHabit],
        challenges: [GrowthChallenge],
        groups: [ClimbGroup],
        posts: [EncouragementPost],
        partners: [AccountabilityPartner],
        leaderboard: [LeaderboardEntry],
        blockedUserIDs: [String] = [],
        moderationReports: [ModerationReport] = [],
        contentFeedback: [DailyContentFeedback] = [],
        notificationFatigue: NotificationFatigueState = NotificationFatigueState(),
        monthlyLetters: [MonthlyReflectionLetter] = [],
        verseMemory: [MemorizedVerse] = [],
        achievementUnlocks: [AchievementUnlock] = []
    ) {
        self.profile = profile
        self.missions = missions
        self.devotionals = devotionals
        self.journalEntries = journalEntries
        self.progress = progress
        self.habits = habits
        self.challenges = challenges
        self.groups = groups
        self.posts = posts
        self.partners = partners
        self.leaderboard = leaderboard
        self.blockedUserIDs = blockedUserIDs
        self.moderationReports = moderationReports
        self.contentFeedback = contentFeedback
        self.notificationFatigue = notificationFatigue
        self.monthlyLetters = monthlyLetters
        self.verseMemory = verseMemory
        self.achievementUnlocks = achievementUnlocks
    }

    private enum CodingKeys: String, CodingKey {
        case profile
        case missions
        case devotionals
        case journalEntries
        case progress
        case habits
        case challenges
        case groups
        case posts
        case partners
        case leaderboard
        case blockedUserIDs
        case moderationReports
        case contentFeedback
        case notificationFatigue
        case monthlyLetters
        case verseMemory
        case achievementUnlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(UserProfile.self, forKey: .profile)
        missions = try container.decode([Mission].self, forKey: .missions)
        devotionals = try container.decode([Devotional].self, forKey: .devotionals)
        journalEntries = try container.decode([ReflectionEntry].self, forKey: .journalEntries)
        progress = try container.decode([ProgressSnapshot].self, forKey: .progress)
        habits = try container.decode([GrowthHabit].self, forKey: .habits)
        challenges = try container.decode([GrowthChallenge].self, forKey: .challenges)
        groups = try container.decode([ClimbGroup].self, forKey: .groups)
        posts = try container.decode([EncouragementPost].self, forKey: .posts)
        partners = try container.decode([AccountabilityPartner].self, forKey: .partners)
        leaderboard = try container.decode([LeaderboardEntry].self, forKey: .leaderboard)
        blockedUserIDs = try container.decodeIfPresent([String].self, forKey: .blockedUserIDs) ?? []
        moderationReports = try container.decodeIfPresent([ModerationReport].self, forKey: .moderationReports) ?? []
        contentFeedback = try container.decodeIfPresent([DailyContentFeedback].self, forKey: .contentFeedback) ?? []
        notificationFatigue = try container.decodeIfPresent(NotificationFatigueState.self, forKey: .notificationFatigue) ?? NotificationFatigueState()
        monthlyLetters = try container.decodeIfPresent([MonthlyReflectionLetter].self, forKey: .monthlyLetters) ?? []
        verseMemory = try container.decodeIfPresent([MemorizedVerse].self, forKey: .verseMemory) ?? []
        achievementUnlocks = try container.decodeIfPresent([AchievementUnlock].self, forKey: .achievementUnlocks) ?? []
    }

    static let empty = AppStateSnapshot(
        profile: nil,
        missions: [],
        devotionals: [],
        journalEntries: [],
        progress: [],
        habits: [],
        challenges: [],
        groups: [],
        posts: [],
        partners: [],
        leaderboard: [],
        blockedUserIDs: [],
        moderationReports: [],
        contentFeedback: [],
        notificationFatigue: NotificationFatigueState(),
        monthlyLetters: [],
        verseMemory: [],
        achievementUnlocks: []
    )
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}
