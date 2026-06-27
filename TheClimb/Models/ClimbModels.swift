import Foundation

enum AgeGroup: String, CaseIterable, Codable, Identifiable {
    case teen = "Teen"
    case college = "College"
    case youngAdult = "Young Adult"

    var id: String { rawValue }
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
        case .teen:
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

struct ProgressSnapshot: Identifiable, Codable, Equatable {
    var id: String
    var date: Date
    var ovrScore: Int
    var currentStreak: Int
    var completionRate: Double
    var completedMissions: Int
    var failedMissions: Int
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

struct ModerationReport: Identifiable, Codable, Equatable {
    var id: String
    var postID: String
    var reportedUserID: String
    var reportedByUserID: String
    var reason: String
    var postBody: String
    var createdAt: Date
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
        moderationReports: [ModerationReport] = []
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
        moderationReports: []
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
