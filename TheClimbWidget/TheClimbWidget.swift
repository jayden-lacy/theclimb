#if os(iOS)
import SwiftUI
import WidgetKit
import ActivityKit

private enum WidgetStorage {
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let storageKey = "the-climb.snapshot.v1"
}

struct ClimbWidgetEntry: TimelineEntry {
    let date: Date
    let missionTitle: String
    let missionSummary: String
    let missionStatus: String
    let missionCategory: String
    let durationMinutes: Int
    let missionDifficulty: Int
    let appBlockingEnabled: Bool
    let streak: Int
    let streakGoal: Int
    let ovr: Int
    let completionRate: Double
    let devotionalTitle: String
    let verseReference: String
    let verseText: String
    let reflectionQuestion: String
    let habitTitle: String
    let challengeTitle: String
    let challengeDetail: String
    let challengeProgress: Double
    let challengeDaysRemaining: Int
    let partnerName: String
    let partnerStatus: String
    let partnerSharedStreak: Int
    let partnerWeekCompletions: Int
    let isConfigured: Bool

    static let placeholder = ClimbWidgetEntry(
        date: Date(),
        missionTitle: "No phone for 1 hour after waking",
        missionSummary: "Start clean. Win the first hour.",
        missionStatus: "Pending",
        missionCategory: "Focus",
        durationMinutes: 60,
        missionDifficulty: 3,
        appBlockingEnabled: true,
        streak: 14,
        streakGoal: 30,
        ovr: 78,
        completionRate: 0.71,
        devotionalTitle: "Undivided Attention",
        verseReference: "Psalm 119:37",
        verseText: "Turn my eyes from worthless things, and give me life through your word.",
        reflectionQuestion: "What is trying to own your attention today?",
        habitTitle: "Phone away before mission",
        challengeTitle: "Daily rhythm",
        challengeDetail: "Protect the next faithful step today.",
        challengeProgress: 0.57,
        challengeDaysRemaining: 3,
        partnerName: "Jordan",
        partnerStatus: "Your move",
        partnerSharedStreak: 4,
        partnerWeekCompletions: 5,
        isConfigured: true
    )

    static let empty = ClimbWidgetEntry(
        date: Date(),
        missionTitle: "Build your climb",
        missionSummary: "Open The Climb to create today’s mission.",
        missionStatus: "Ready",
        missionCategory: "Discipline",
        durationMinutes: 0,
        missionDifficulty: 1,
        appBlockingEnabled: false,
        streak: 0,
        streakGoal: 7,
        ovr: 50,
        completionRate: 0,
        devotionalTitle: "Start the path",
        verseReference: "Today",
        verseText: "Open The Climb to prepare your mission and Daily Word.",
        reflectionQuestion: "What needs your first obedient step?",
        habitTitle: "Choose your rhythm",
        challengeTitle: "Daily rhythm",
        challengeDetail: "Open The Climb to build your daily rhythm.",
        challengeProgress: 0,
        challengeDaysRemaining: 0,
        partnerName: "No partner",
        partnerStatus: "Invite someone",
        partnerSharedStreak: 0,
        partnerWeekCompletions: 0,
        isConfigured: false
    )
}

struct ClimbWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClimbWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ClimbWidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClimbWidgetEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(60 * 20)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> ClimbWidgetEntry {
        guard let defaults = UserDefaults(suiteName: WidgetStorage.appGroupID),
              let data = defaults.data(forKey: WidgetStorage.storageKey) else {
            return .empty
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let snapshot = try? decoder.decode(WidgetAppStateSnapshot.self, from: data),
              let profile = snapshot.profile else {
            return .empty
        }

        let calendar = Calendar.current
        let mission = snapshot.missions.first { calendar.isDateInToday($0.date) }
            ?? snapshot.missions.sorted { $0.date > $1.date }.first
        let devotional = snapshot.devotionals.first { calendar.isDateInToday($0.date) }
            ?? snapshot.devotionals.sorted { $0.date > $1.date }.first
        let challenge = snapshot.challenges
            .sorted {
                if $0.isComplete == $1.isComplete {
                    return $0.difficulty > $1.difficulty
                }
                return !$0.isComplete
            }
            .first
        let partner = snapshot.partners.first { !$0.isPending } ?? snapshot.partners.first
        let habit = snapshot.habits.first { $0.isEnabled && !$0.isCompletedToday }
            ?? snapshot.habits.first { $0.isEnabled }
            ?? snapshot.habits.first
        let latestProgress = snapshot.progress.sorted { $0.date > $1.date }.first

        return ClimbWidgetEntry(
            date: Date(),
            missionTitle: mission?.title ?? "Today’s mission is ready",
            missionSummary: mission?.summary ?? "Open The Climb to start your discipline rhythm.",
            missionStatus: mission?.status.capitalized ?? "Ready",
            missionCategory: mission?.category ?? "Discipline",
            durationMinutes: mission?.durationMinutes ?? 0,
            missionDifficulty: mission?.difficulty ?? 1,
            appBlockingEnabled: mission?.appBlockingEnabled ?? false,
            streak: profile.currentStreak,
            streakGoal: profile.streakGoal,
            ovr: profile.ovrScore,
            completionRate: latestProgress?.completionRate ?? snapshot.completionRateFallback,
            devotionalTitle: devotional?.title ?? "Daily Word",
            verseReference: devotional?.bibleVerse ?? "Today",
            verseText: devotional?.verseText ?? devotional?.explanation ?? "Open The Climb to read today’s devotional.",
            reflectionQuestion: devotional?.reflectionQuestion ?? "What is the next faithful step today?",
            habitTitle: habit.map { $0.isCompletedToday ? "\($0.title) done" : $0.title } ?? "Daily rhythm",
            challengeTitle: challenge?.title ?? "Daily rhythm",
            challengeDetail: challenge?.detail ?? "Keep the next faithful step small.",
            challengeProgress: challenge?.progress ?? 0,
            challengeDaysRemaining: challenge?.daysRemaining ?? 0,
            partnerName: partner?.name ?? "No partner",
            partnerStatus: partner.map { $0.isPending ? "Invite pending" : $0.lastCheckIn } ?? "Invite someone",
            partnerSharedStreak: partner?.sharedStreak ?? 0,
            partnerWeekCompletions: partner?.weeklyCompletions ?? 0,
            isConfigured: true
        )
    }
}

struct TheClimbWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ClimbWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemLarge:
                largeWidget
            case .systemMedium:
                mediumWidget
            case .accessoryCircular:
                circularWidget
            case .accessoryRectangular:
                rectangularWidget
            case .accessoryInline:
                inlineWidget
            default:
                smallWidget
            }
        }
        .dynamicTypeSize(.xSmall ... .large)
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetTopline(title: "Today", trailing: entry.missionStatus, tint: entry.statusTint)

            ViewThatFits(in: .vertical) {
                WidgetMissionTextBlock(entry: entry, titleSize: 16, titleLines: 3, summaryLines: 0)
                WidgetMissionTextBlock(entry: entry, titleSize: 15, titleLines: 2, summaryLines: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                WidgetMetricTile(value: "\(entry.ovr)", label: "OVR", tint: WidgetTheme.sage)
                WidgetMetricTile(value: "\(entry.streak)", label: "streak", tint: WidgetTheme.amber)
            }

            ProgressBar(value: streakProgress, tint: WidgetTheme.sage)
                .frame(height: 4)
        }
        .padding(15)
        .widgetBackground()
    }

    private var mediumWidget: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetTopline(title: "The Climb", trailing: entry.durationLabel, tint: WidgetTheme.sage)

                ViewThatFits(in: .vertical) {
                    WidgetMissionTextBlock(entry: entry, titleSize: 18, titleLines: 2, summaryLines: 2)
                    WidgetMissionTextBlock(entry: entry, titleSize: 16, titleLines: 2, summaryLines: 1)
                }

                Spacer(minLength: 0)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        WidgetBadge(text: entry.missionStatus, symbol: "flag.fill", tint: entry.statusTint)
                        WidgetBadge(text: "L\(entry.missionDifficulty)", symbol: "bolt.fill", tint: WidgetTheme.amber)
                        WidgetBadge(text: entry.appBlockingEnabled ? "Block" : entry.missionCategory, symbol: entry.appBlockingEnabled ? "lock.fill" : "target", tint: WidgetTheme.blue)
                    }
                    HStack(spacing: 5) {
                        WidgetBadge(text: entry.missionStatus, symbol: "flag.fill", tint: entry.statusTint)
                        WidgetBadge(text: "L\(entry.missionDifficulty)", symbol: "bolt.fill", tint: WidgetTheme.amber)
                    }
                    WidgetBadge(text: entry.missionStatus, symbol: "flag.fill", tint: entry.statusTint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 7) {
                    ScoreRing(value: Double(entry.ovr) / 100, label: "\(entry.ovr)", caption: "OVR")
                        .frame(width: 58, height: 58)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(entry.streak)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(WidgetTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Text("day streak")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WidgetTheme.tertiaryText)
                            .lineLimit(1)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.verseReference)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WidgetTheme.warmText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                    Text(entry.devotionalTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(WidgetTheme.surfaceRaised.opacity(0.78), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(WidgetTheme.divider.opacity(0.76), lineWidth: 1)
                }
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .widgetBackground()
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetTopline(title: "The Climb", trailing: entry.missionStatus, tint: entry.statusTint)

            WidgetMissionPanel(entry: entry)

            HStack(spacing: 9) {
                ScoreRing(value: Double(entry.ovr) / 100, label: "\(entry.ovr)", caption: "OVR")
                    .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 10) {
                    WidgetProgressRow(
                        title: "Streak",
                        value: "\(entry.streak)/\(max(entry.streakGoal, 1))",
                        progress: streakProgress,
                        tint: WidgetTheme.sage
                    )
                    WidgetProgressRow(
                        title: "Completion",
                        value: "\(Int(entry.completionRate * 100))%",
                        progress: entry.completionRate,
                        tint: WidgetTheme.blue
                    )
                }
            }

            WidgetDailyWordPanel(entry: entry)

            HStack(spacing: 9) {
                WidgetMiniPanel(
                    title: "Habit",
                    value: entry.habitTitle,
                    footnote: entry.appBlockingEnabled ? "Blocking ready" : "Daily rhythm",
                    symbol: "checkmark.seal.fill",
                    tint: WidgetTheme.amber
                )
                WidgetMiniPanel(
                    title: "Partner",
                    value: entry.partnerName,
                    footnote: entry.partnerSharedStreak > 0 ? "\(entry.partnerSharedStreak)d together · \(entry.partnerWeekCompletions)/7" : entry.partnerStatus,
                    symbol: "person.2.fill",
                    tint: WidgetTheme.sage
                )
            }
        }
        .padding(16)
        .widgetBackground()
    }

    private var circularWidget: some View {
        Gauge(value: Double(entry.ovr), in: 0...100) {
            Image(systemName: "mountain.2.fill")
        } currentValueLabel: {
            Text("\(entry.ovr)")
        }
        .gaugeStyle(.accessoryCircular)
        .tint(WidgetTheme.green)
        .containerBackground(WidgetTheme.black, for: .widget)
    }

    private var rectangularWidget: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.appBlockingEnabled ? "lock.shield.fill" : "mountain.2.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(entry.appBlockingEnabled ? WidgetTheme.blue : WidgetTheme.sage)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.missionTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                Text("\(entry.durationLabel) · \(entry.streak)d streak · \(entry.ovr) OVR")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }
        }
        .containerBackground(WidgetTheme.black, for: .widget)
    }

    private var inlineWidget: some View {
        Text("The Climb: \(entry.missionStatus) · \(entry.streak)d · \(entry.ovr) OVR")
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
    }

    private var streakProgress: Double {
        guard entry.streakGoal > 0 else { return 0 }
        return min(Double(entry.streak) / Double(entry.streakGoal), 1)
    }
}

struct TheClimbWidget: Widget {
    let kind = "TheClimbWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClimbWidgetProvider()) { entry in
            TheClimbWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("The Climb")
        .description("Mission, Daily Word, streak, OVR, habits, and accountability.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct ClimbMissionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        var focusLabel: String
    }

    var missionID: String
    var missionTitle: String
    var durationMinutes: Int
    var appBlockingEnabled: Bool
    var isBlockingActive: Bool
}

struct TheClimbMissionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClimbMissionAttributes.self) { context in
            MissionLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(WidgetTheme.black)
                .activitySystemActionForegroundColor(WidgetTheme.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("The Climb")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                        Text(context.state.focusLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WidgetTheme.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(context.state.endsAt, style: .timer)
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("left")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.56))
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.missionTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                }
            } compactLeading: {
                Image(systemName: context.attributes.isBlockingActive ? "lock.shield.fill" : "timer")
                    .foregroundStyle(WidgetTheme.green)
            } compactTrailing: {
                Text(context.state.endsAt, style: .timer)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            } minimal: {
                Image(systemName: "mountain.2.fill")
                    .foregroundStyle(WidgetTheme.green)
            }
            .keylineTint(WidgetTheme.green)
        }
    }
}

private struct MissionLiveActivityLockScreenView: View {
    let context: ActivityViewContext<ClimbMissionAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "mountain.2.fill")
                    .foregroundStyle(WidgetTheme.green)
                Text("The Climb")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.secondaryText)
                Spacer()
                Text(context.state.focusLabel.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WidgetTheme.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .allowsTightening(true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(WidgetTheme.green.opacity(0.14), in: Capsule())
            }

            Text(context.attributes.missionTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(context.state.endsAt, style: .timer)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                Spacer()
                Image(systemName: context.attributes.isBlockingActive ? "lock.fill" : "timer")
                    .foregroundStyle(WidgetTheme.green)
            }
        }
        .padding(18)
    }
}

private struct WidgetAppStateSnapshot: Decodable {
    let profile: WidgetProfile?
    let missions: [WidgetMission]
    let devotionals: [WidgetDevotional]
    let progress: [WidgetProgressSnapshot]
    let habits: [WidgetHabit]
    let challenges: [WidgetChallenge]
    let partners: [WidgetPartner]

    private enum CodingKeys: String, CodingKey {
        case profile
        case missions
        case devotionals
        case progress
        case habits
        case challenges
        case partners
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(WidgetProfile.self, forKey: .profile)
        missions = try container.decodeIfPresent([WidgetMission].self, forKey: .missions) ?? []
        devotionals = try container.decodeIfPresent([WidgetDevotional].self, forKey: .devotionals) ?? []
        progress = try container.decodeIfPresent([WidgetProgressSnapshot].self, forKey: .progress) ?? []
        habits = try container.decodeIfPresent([WidgetHabit].self, forKey: .habits) ?? []
        challenges = try container.decodeIfPresent([WidgetChallenge].self, forKey: .challenges) ?? []
        partners = try container.decodeIfPresent([WidgetPartner].self, forKey: .partners) ?? []
    }

    var completionRateFallback: Double {
        guard !missions.isEmpty else { return 0 }
        let completed = missions.filter { ["completed", "recovered"].contains($0.status.lowercased()) }.count
        return min(Double(completed) / Double(missions.count), 1)
    }
}

private struct WidgetProfile: Decodable {
    let streakGoal: Int
    let ovrScore: Int
    let currentStreak: Int
}

private struct WidgetMission: Decodable {
    let date: Date
    let title: String
    let summary: String
    let category: String
    let durationMinutes: Int
    let difficulty: Int
    let status: String
    let appBlockingEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case date
        case title
        case summary
        case category
        case durationMinutes
        case difficulty
        case status
        case appBlockingEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Discipline"
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1
        status = try container.decode(String.self, forKey: .status)
        appBlockingEnabled = try container.decodeIfPresent(Bool.self, forKey: .appBlockingEnabled) ?? false
    }
}

private struct WidgetDevotional: Decodable {
    let date: Date
    let title: String
    let bibleVerse: String
    let verseText: String?
    let explanation: String
    let reflectionQuestion: String
}

private struct WidgetProgressSnapshot: Decodable {
    let date: Date
    let completionRate: Double
    let completedMissions: Int
    let failedMissions: Int
}

private struct WidgetHabit: Decodable {
    let title: String
    let isEnabled: Bool
    let completedDates: [Date]

    private enum CodingKeys: String, CodingKey {
        case title
        case isEnabled
        case completedDates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        completedDates = try container.decodeIfPresent([Date].self, forKey: .completedDates) ?? []
    }

    var isCompletedToday: Bool {
        completedDates.contains { Calendar.current.isDateInToday($0) }
    }
}

private struct WidgetChallenge: Decodable {
    let title: String
    let detail: String
    let difficulty: Int
    let daysRemaining: Int
    let targetCompletions: Int
    let completedCount: Int

    private enum CodingKeys: String, CodingKey {
        case title
        case detail
        case difficulty
        case daysRemaining
        case targetCompletions
        case completedCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? "Keep building your current challenge."
        difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 1
        daysRemaining = max(try container.decodeIfPresent(Int.self, forKey: .daysRemaining) ?? 0, 0)
        targetCompletions = max(try container.decodeIfPresent(Int.self, forKey: .targetCompletions) ?? 3, 1)
        completedCount = min(max(try container.decodeIfPresent(Int.self, forKey: .completedCount) ?? 0, 0), targetCompletions)
    }

    var progress: Double {
        guard targetCompletions > 0 else { return 0 }
        return min(Double(completedCount) / Double(targetCompletions), 1)
    }

    var isComplete: Bool {
        completedCount >= targetCompletions
    }
}

private struct WidgetPartner: Decodable {
    let name: String
    let lastCheckIn: String
    let isPending: Bool
    let sharedStreak: Int
    let weeklyCompletions: Int

    private enum CodingKeys: String, CodingKey {
        case name
        case lastCheckIn
        case isPending
        case sharedStreak
        case weeklyCompletions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        lastCheckIn = try container.decodeIfPresent(String.self, forKey: .lastCheckIn) ?? "Waiting"
        isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
        sharedStreak = max(try container.decodeIfPresent(Int.self, forKey: .sharedStreak) ?? 0, 0)
        weeklyCompletions = min(max(try container.decodeIfPresent(Int.self, forKey: .weeklyCompletions) ?? 0, 0), 7)
    }
}

private enum WidgetTheme {
    static let black = Color(red: 0.012, green: 0.016, blue: 0.012)
    static let surface = Color(red: 0.033, green: 0.047, blue: 0.035)
    static let surfaceRaised = Color(red: 0.067, green: 0.094, blue: 0.071)
    static let divider = Color(red: 0.145, green: 0.188, blue: 0.153)
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.690, green: 0.659, blue: 0.612)
    static let tertiaryText = Color(red: 0.455, green: 0.431, blue: 0.392)
    static let warmText = Color(red: 0.937, green: 0.890, blue: 0.816)
    static let green = Color(red: 0.169, green: 0.902, blue: 0.420)
    static let sage = Color(red: 0.525, green: 0.902, blue: 0.635)
    static let amber = Color(red: 0.941, green: 0.698, blue: 0.290)
    static let blue = Color(red: 0.431, green: 0.616, blue: 0.949)
    static let red = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let ink = Color(red: 0.027, green: 0.035, blue: 0.029)
}

private extension ClimbWidgetEntry {
    var durationLabel: String {
        durationMinutes > 0 ? "\(durationMinutes)m" : "Today"
    }

    var statusTint: Color {
        switch missionStatus.lowercased() {
        case "completed", "recovered":
            WidgetTheme.sage
        case "active":
            WidgetTheme.blue
        case "failed":
            WidgetTheme.red
        default:
            WidgetTheme.amber
        }
    }

    var primaryCue: String {
        if appBlockingEnabled {
            return "Blocking on · \(durationLabel)"
        }
        return "\(missionCategory) · L\(missionDifficulty) · \(durationLabel)"
    }
}

private struct WidgetTopline: View {
    let title: String
    let trailing: String
    var tint: Color = WidgetTheme.sage

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "mountain.2.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .allowsTightening(true)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(trailing)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .truncationMode(.tail)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(tint.opacity(0.13), in: Capsule())
        }
    }
}

private struct WidgetMissionTextBlock: View {
    let entry: ClimbWidgetEntry
    let titleSize: CGFloat
    let titleLines: Int
    let summaryLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.missionTitle)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(titleLines)
                .minimumScaleFactor(0.60)
                .allowsTightening(true)
                .truncationMode(.tail)
                .layoutPriority(2)

            if summaryLines > 0 {
                Text(entry.missionSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(summaryLines)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            } else {
                Text(entry.primaryCue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }
        }
    }
}

private struct WidgetMetricTile: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(WidgetTheme.surfaceRaised.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WidgetTheme.divider.opacity(0.88), lineWidth: 1)
        }
    }
}

private struct WidgetMissionPanel: View {
    let entry: ClimbWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    WidgetBadge(text: entry.missionCategory, symbol: "target", tint: WidgetTheme.sage)
                    WidgetBadge(text: "Level \(entry.missionDifficulty)", symbol: "bolt.fill", tint: WidgetTheme.amber)
                    WidgetBadge(
                        text: entry.appBlockingEnabled ? "Blocking" : entry.durationLabel,
                        symbol: entry.appBlockingEnabled ? "lock.fill" : "timer",
                        tint: entry.appBlockingEnabled ? WidgetTheme.blue : WidgetTheme.warmText
                    )
                }
                HStack(spacing: 6) {
                    WidgetBadge(text: "L\(entry.missionDifficulty)", symbol: "bolt.fill", tint: WidgetTheme.amber)
                    WidgetBadge(
                        text: entry.appBlockingEnabled ? "Blocking" : entry.durationLabel,
                        symbol: entry.appBlockingEnabled ? "lock.fill" : "timer",
                        tint: entry.appBlockingEnabled ? WidgetTheme.blue : WidgetTheme.warmText
                    )
                }
                WidgetBadge(
                    text: entry.appBlockingEnabled ? "Blocking" : entry.durationLabel,
                    symbol: entry.appBlockingEnabled ? "lock.fill" : "timer",
                    tint: entry.appBlockingEnabled ? WidgetTheme.blue : WidgetTheme.warmText
                )
            }

            ViewThatFits(in: .vertical) {
                WidgetMissionTextBlock(entry: entry, titleSize: 21, titleLines: 2, summaryLines: 2)
                WidgetMissionTextBlock(entry: entry, titleSize: 19, titleLines: 2, summaryLines: 1)
            }
        }
        .padding(12)
        .background(WidgetTheme.surfaceRaised.opacity(0.88), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(WidgetTheme.divider.opacity(0.92), lineWidth: 1)
        }
    }
}

private struct WidgetDailyWordPanel: View {
    let entry: ClimbWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(entry.verseReference)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("Daily Word")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Text(entry.verseText)
                .font(.system(size: 13, weight: .medium, design: .serif))
                .foregroundStyle(WidgetTheme.primaryText.opacity(0.92))
                .lineLimit(2)
                .minimumScaleFactor(0.64)
                .allowsTightening(true)
                .truncationMode(.tail)
                .layoutPriority(1)

            Text(entry.reflectionQuestion)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
                .allowsTightening(true)
                .truncationMode(.tail)
        }
        .padding(11)
        .background(
            LinearGradient(
                colors: [WidgetTheme.surfaceRaised.opacity(0.88), WidgetTheme.amber.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WidgetTheme.divider.opacity(0.82), lineWidth: 1)
        }
    }
}

private struct WidgetMiniPanel: View {
    let title: String
    let value: String
    let footnote: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.13))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                Text(footnote)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(WidgetTheme.surfaceRaised.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WidgetTheme.divider.opacity(0.80), lineWidth: 1)
        }
    }
}

private struct CompactMetric: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WidgetTheme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
    }
}

private struct WidgetBadge: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .truncationMode(.tail)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(WidgetTheme.surfaceRaised.opacity(0.70), in: Capsule())
    }
}

private struct ProgressBar: View {
    let value: Double
    var tint: Color = WidgetTheme.green

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetTheme.divider.opacity(0.72))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
    }
}

private struct ScoreRing: View {
    let value: Double
    let label: String
    let caption: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(WidgetTheme.divider.opacity(0.72), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(WidgetTheme.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                Text(caption)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
        }
    }
}

private struct WidgetProgressRow: View {
    let title: String
    let value: String
    let progress: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                Spacer(minLength: 6)
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
            }
            ProgressBar(value: progress, tint: tint)
                .frame(height: 4)
        }
    }
}

private struct PartnerStrip: View {
    let name: String
    let status: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(WidgetTheme.green.opacity(0.16))
                Image(systemName: "person.2.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WidgetTheme.green)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(WidgetTheme.surfaceRaised.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WidgetTheme.divider.opacity(0.82), lineWidth: 1)
        }
    }
}

private extension View {
    func widgetBackground() -> some View {
        containerBackground(for: .widget) {
            ZStack {
                WidgetTheme.black
                LinearGradient(
                    colors: [
                        WidgetTheme.green.opacity(0.075),
                        WidgetTheme.surface.opacity(0.98),
                        WidgetTheme.ink,
                        WidgetTheme.black
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
        }
    }
}
#endif
