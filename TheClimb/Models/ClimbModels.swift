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
}

struct GrowthChallenge: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var detail: String
    var category: MissionCategory
    var daysRemaining: Int
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

    init(
        id: String,
        name: String,
        focus: Struggle,
        lastCheckIn: String,
        checkInCount: Int = 0,
        nudgeCount: Int = 0,
        encouragementCount: Int = 0,
        lastInteraction: String = "No action yet"
    ) {
        self.id = id
        self.name = name
        self.focus = focus
        self.lastCheckIn = lastCheckIn
        self.checkInCount = checkInCount
        self.nudgeCount = nudgeCount
        self.encouragementCount = encouragementCount
        self.lastInteraction = lastInteraction
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
    }
}

struct ClimbGroup: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var subtitle: String
    var members: Int
    var activeChallenge: String
    var isJoined: Bool

    init(
        id: String,
        name: String,
        subtitle: String,
        members: Int,
        activeChallenge: String,
        isJoined: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.members = members
        self.activeChallenge = activeChallenge
        self.isJoined = isJoined
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case subtitle
        case members
        case activeChallenge
        case isJoined
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        members = try container.decode(Int.self, forKey: .members)
        activeChallenge = try container.decode(String.self, forKey: .activeChallenge)
        isJoined = try container.decodeIfPresent(Bool.self, forKey: .isJoined) ?? false
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
