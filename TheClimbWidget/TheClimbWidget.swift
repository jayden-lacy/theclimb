#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit
import ActivityKit

private enum WidgetStorage {
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let storageKey = "the-climb.snapshot.v1"
}

@available(iOSApplicationExtension 17.0, *)
struct CompleteTodayHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Today’s Habit"
    static let description = IntentDescription("Mark the first incomplete habit complete in The Climb.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = WidgetActionStore.completeFirstIncompleteHabit()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

@available(iOSApplicationExtension 17.0, *)
struct StartPrayerTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Prayer Timer"
    static let description = IntentDescription("Start a short prayer timer from The Climb widget.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = WidgetActionStore.startPrayerTimer(minutes: 2)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

@available(iOSApplicationExtension 17.0, *)
struct FinishPrayerTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish Prayer Timer"
    static let description = IntentDescription("Complete the active prayer timer in The Climb.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = WidgetActionStore.finishPrayerTimer()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

@available(iOSApplicationExtension 17.0, *)
struct OpenTheClimbIntent: AppIntent {
    static let title: LocalizedStringResource = "Open The Climb"
    static let description = IntentDescription("Open The Climb to continue today’s protected focus block.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

private enum WidgetActionStore {
    private enum PrayerKeys {
        static let isRunning = "climb.prayer.isRunning"
        static let startedAt = "climb.prayer.startedAt"
        static let endsAt = "climb.prayer.endsAt"
        static let remainingSeconds = "climb.prayer.remainingSeconds"
        static let selectedMinutes = "climb.prayer.selectedMinutes"
        static let sessionsCompleted = "climb.prayer.sessionsCompleted"
        static let minutesCompleted = "climb.prayer.minutesCompleted"
        static let lastCompletedAt = "climb.prayer.lastCompletedAt"
    }

    struct ActionResult {
        let didChange: Bool
        let message: String
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetStorage.appGroupID)
    }

    static func completeFirstIncompleteHabit() -> ActionResult {
        guard let defaults,
              let data = defaults.data(forKey: WidgetStorage.storageKey),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var habits = root["habits"] as? [[String: Any]] else {
            return ActionResult(didChange: false, message: "Open The Climb to set up habits.")
        }

        let formatter = ISO8601DateFormatter()
        let calendar = Calendar.current
        guard let index = habits.firstIndex(where: { habit in
            let isEnabled = habit["isEnabled"] as? Bool ?? true
            guard isEnabled else { return false }
            let completedDates = habit["completedDates"] as? [String] ?? []
            return !completedDates.contains { dateString in
                guard let date = formatter.date(from: dateString) else { return false }
                return calendar.isDateInToday(date)
            }
        }) else {
            return ActionResult(didChange: false, message: "All habits are complete today.")
        }

        var completedDates = habits[index]["completedDates"] as? [String] ?? []
        completedDates.append(formatter.string(from: Date()))
        habits[index]["completedDates"] = completedDates
        root["habits"] = habits

        guard let updatedData = try? JSONSerialization.data(withJSONObject: root) else {
            return ActionResult(didChange: false, message: "Could not update your habit.")
        }

        defaults.set(updatedData, forKey: WidgetStorage.storageKey)
        return ActionResult(didChange: true, message: "Habit marked complete.")
    }

    static func startPrayerTimer(minutes: Int) -> ActionResult {
        guard let defaults else {
            return ActionResult(didChange: false, message: "Open The Climb to start prayer.")
        }

        let safeMinutes = max(1, min(minutes, 30))
        let startedAt = Date()
        let duration = safeMinutes * 60
        let endsAt = startedAt.addingTimeInterval(TimeInterval(duration))

        defaults.set(true, forKey: PrayerKeys.isRunning)
        defaults.set(startedAt.timeIntervalSince1970, forKey: PrayerKeys.startedAt)
        defaults.set(endsAt.timeIntervalSince1970, forKey: PrayerKeys.endsAt)
        defaults.set(duration, forKey: PrayerKeys.remainingSeconds)
        defaults.set(safeMinutes, forKey: PrayerKeys.selectedMinutes)
        return ActionResult(didChange: true, message: "Prayer timer started.")
    }

    static func finishPrayerTimer() -> ActionResult {
        guard let defaults else {
            return ActionResult(didChange: false, message: "Open The Climb to finish prayer.")
        }

        let now = Date()
        let startedAtInterval = defaults.double(forKey: PrayerKeys.startedAt)
        let endsAtInterval = defaults.double(forKey: PrayerKeys.endsAt)
        let selectedMinutes = max(defaults.integer(forKey: PrayerKeys.selectedMinutes), 1)
        let startedAt = startedAtInterval > 0 ? Date(timeIntervalSince1970: startedAtInterval) : now.addingTimeInterval(TimeInterval(-selectedMinutes * 60))
        let plannedEndsAt = endsAtInterval > 0 ? Date(timeIntervalSince1970: endsAtInterval) : now
        let completedSeconds = max(60, min(Int(now.timeIntervalSince(startedAt)), selectedMinutes * 60, Int(plannedEndsAt.timeIntervalSince(startedAt))))
        let completedMinutes = max(1, Int((Double(completedSeconds) / 60).rounded()))

        defaults.set(defaults.integer(forKey: PrayerKeys.sessionsCompleted) + 1, forKey: PrayerKeys.sessionsCompleted)
        defaults.set(defaults.integer(forKey: PrayerKeys.minutesCompleted) + completedMinutes, forKey: PrayerKeys.minutesCompleted)
        defaults.set(now.timeIntervalSince1970, forKey: PrayerKeys.lastCompletedAt)
        clearPrayerTimer(defaults: defaults)
        return ActionResult(didChange: true, message: "Prayer completed.")
    }

    static func clearPrayerTimer(defaults: UserDefaults) {
        defaults.set(false, forKey: PrayerKeys.isRunning)
        defaults.removeObject(forKey: PrayerKeys.startedAt)
        defaults.removeObject(forKey: PrayerKeys.endsAt)
        defaults.removeObject(forKey: PrayerKeys.remainingSeconds)
    }
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
    let hasIncompleteHabit: Bool
    let prayerSessionsCompleted: Int
    let prayerMinutesCompleted: Int
    let isPrayerTimerActive: Bool
    let prayerTimerEndsAt: Date?
    let prayerDurationMinutes: Int
    let challengeTitle: String
    let challengeDetail: String
    let challengeProgress: Double
    let challengeDaysRemaining: Int
    let partnerName: String
    let partnerStatus: String
    let partnerSharedStreak: Int
    let partnerWeekCompletions: Int
    let isConfigured: Bool

    var relevance: TimelineEntryRelevance? {
        guard isConfigured else {
            return TimelineEntryRelevance(score: 25, duration: 60 * 20)
        }

        let status = missionStatus.lowercased()
        let score: Float
        switch status {
        case "active":
            score = 92
        case "failed":
            score = 86
        case "pending", "ready":
            score = hasIncompleteHabit ? 82 : 74
        case "completed", "recovered":
            score = hasIncompleteHabit ? 58 : 34
        default:
            score = 50
        }

        let duration = status == "active" ? TimeInterval(max(durationMinutes, 1) * 60) : 60 * 30
        return TimelineEntryRelevance(score: score, duration: duration)
    }

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
        hasIncompleteHabit: true,
        prayerSessionsCompleted: 2,
        prayerMinutesCompleted: 10,
        isPrayerTimerActive: false,
        prayerTimerEndsAt: nil,
        prayerDurationMinutes: 2,
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
        hasIncompleteHabit: false,
        prayerSessionsCompleted: 0,
        prayerMinutesCompleted: 0,
        isPrayerTimerActive: false,
        prayerTimerEndsAt: nil,
        prayerDurationMinutes: 2,
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
        let defaultRefresh = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(60 * 20)
        let prayerRefresh = entry.prayerTimerEndsAt.map { $0.addingTimeInterval(1) }
        let nextRefresh = [defaultRefresh, prayerRefresh].compactMap(\.self).min() ?? defaultRefresh
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
        let hasIncompleteHabit = snapshot.habits.contains { $0.isEnabled && !$0.isCompletedToday }
        let latestProgress = snapshot.progress.sorted { $0.date > $1.date }.first
        let prayerState = WidgetPrayerState(defaults: defaults)

        return ClimbWidgetEntry(
            date: Date(),
            missionTitle: mission?.title ?? "Today’s focus block is ready",
            missionSummary: mission?.summary ?? "Open The Climb to start your protected faith focus rhythm.",
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
            hasIncompleteHabit: hasIncompleteHabit,
            prayerSessionsCompleted: prayerState.sessionsCompleted,
            prayerMinutesCompleted: prayerState.minutesCompleted,
            isPrayerTimerActive: prayerState.isActive,
            prayerTimerEndsAt: prayerState.activeEndsAt,
            prayerDurationMinutes: prayerState.selectedMinutes,
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
            case .systemExtraLarge:
                extraLargeWidget
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
        .widgetURL(entry.defaultWidgetURL)
    }

    private var smallWidget: some View {
        ZStack(alignment: .bottomTrailing) {
            WidgetCornerBeam(tint: entry.statusTint)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    WidgetLogoDot(tint: entry.statusTint, size: 26)
                    Spacer(minLength: 8)
                    WidgetStatusCapsule(text: entry.conciseStatus, tint: entry.statusTint)
                }

                Spacer(minLength: 10)

                Text(entry.primaryActionLabel.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(entry.statusTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Text(entry.missionTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .padding(.top, 5)

                Spacer(minLength: 10)

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(entry.streak)")
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                        .foregroundStyle(WidgetTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.60)
                    Text("day streak")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WidgetTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Spacer(minLength: 0)
                }

                ProgressBar(value: streakProgress, tint: entry.statusTint)
                    .frame(height: 4)
                    .padding(.top, 7)
            }
            .padding(15)
        }
        .widgetBackground(emphasis: entry.statusTint)
    }

    private var mediumWidget: some View {
        HStack(alignment: .top, spacing: 13) {
            Link(destination: entry.missionWidgetURL) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        WidgetLogoDot(tint: entry.statusTint, size: 28)
                        Text(entry.primaryActionLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(entry.statusTint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.66)
                            .allowsTightening(true)
                        Spacer(minLength: 4)
                    }

                    Text(entry.missionTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(WidgetTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.60)
                        .allowsTightening(true)
                        .truncationMode(.tail)

                    Text(entry.missionSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WidgetTheme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)

                    Spacer(minLength: 0)

                    WidgetCommandStrip(entry: entry)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 9) {
                if let progressURL = entry.progressWidgetURL {
                    Link(destination: progressURL) {
                        WidgetMomentumStack(entry: entry, streakProgress: streakProgress)
                    }
                    .buttonStyle(.plain)
                } else {
                    WidgetMomentumStack(entry: entry, streakProgress: streakProgress)
                }

                WidgetWordChip(entry: entry)
            }
            .frame(width: 122, alignment: .leading)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .widgetBackground(emphasis: entry.statusTint)
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        WidgetLogoDot(tint: entry.statusTint, size: 30)
                        Text("THE CLIMB")
                            .font(.system(size: 11, weight: .black))
                            .tracking(1.2)
                            .foregroundStyle(WidgetTheme.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                    }

                    Text(entry.primaryActionLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(entry.statusTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)

                    Text(entry.missionTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(WidgetTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.58)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ScoreRing(value: Double(entry.ovr) / 100, label: "\(entry.ovr)", caption: "OVR")
                    .frame(width: 72, height: 72)
            }

            WidgetCommandStrip(entry: entry)

            HStack(alignment: .top, spacing: 10) {
                WidgetDailyWordPanel(entry: entry)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 9) {
                    WidgetHeroMetric(
                        title: "Streak",
                        value: "\(entry.streak)",
                        footnote: "Goal \(max(entry.streakGoal, 1))",
                        progress: streakProgress,
                        tint: WidgetTheme.sage
                    )
                    WidgetHeroMetric(
                        title: "Week",
                        value: "\(Int(entry.completionRate * 100))%",
                        footnote: "mission consistency",
                        progress: entry.completionRate,
                        tint: WidgetTheme.blue
                    )
                }
                .frame(width: 118)
            }

            HStack(spacing: 9) {
                habitMiniPanel
                prayerMiniPanel
                WidgetPartnerPanel(entry: entry)
            }
        }
        .padding(17)
        .widgetBackground(emphasis: entry.statusTint)
    }

    private var extraLargeWidget: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    WidgetLogoDot(tint: entry.statusTint, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("THE CLIMB")
                            .font(.system(size: 11, weight: .black))
                            .tracking(1.4)
                            .foregroundStyle(WidgetTheme.secondaryText)
                        Text(entry.primaryActionLabel)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(entry.statusTint)
                    }
                    Spacer(minLength: 8)
                    WidgetStatusCapsule(text: entry.conciseStatus, tint: entry.statusTint)
                }

                Text(entry.missionTitle)
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.54)
                    .allowsTightening(true)

                Text(entry.missionSummary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)

                Spacer(minLength: 0)

                WidgetCommandStrip(entry: entry)
                WidgetDailyWordPanel(entry: entry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 11) {
                    ScoreRing(value: Double(entry.ovr) / 100, label: "\(entry.ovr)", caption: "OVR")
                        .frame(width: 88, height: 88)
                    VStack(alignment: .leading, spacing: 9) {
                        WidgetProgressRow(title: "Streak protection", value: "\(entry.streak)/\(max(entry.streakGoal, 1))", progress: streakProgress, tint: WidgetTheme.sage)
                        WidgetProgressRow(title: "Focus consistency", value: "\(Int(entry.completionRate * 100))%", progress: entry.completionRate, tint: WidgetTheme.blue)
                    }
                }
                .padding(12)
                .background(WidgetTheme.glassSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(WidgetTheme.dividerStrong, lineWidth: 1)
                }

                habitMiniPanel
                prayerMiniPanel
                WidgetPartnerPanel(entry: entry)
            }
            .frame(width: 230, alignment: .leading)
        }
        .padding(20)
        .widgetBackground(emphasis: entry.statusTint)
    }

    @ViewBuilder
    private var habitMiniPanel: some View {
        if #available(iOSApplicationExtension 17.0, *), entry.hasIncompleteHabit {
            Button(intent: CompleteTodayHabitIntent()) {
                WidgetMiniPanel(
                    title: "Habit",
                    value: entry.habitTitle,
                    footnote: "Tap to complete",
                    symbol: "checkmark.seal.fill",
                    tint: WidgetTheme.amber
                )
            }
            .buttonStyle(.plain)
        } else {
            WidgetMiniPanel(
                title: "Habit",
                value: entry.habitTitle,
                footnote: entry.hasIncompleteHabit ? "Open to complete" : "Daily rhythm",
                symbol: entry.hasIncompleteHabit ? "checkmark.seal.fill" : "checkmark.seal",
                tint: WidgetTheme.amber
            )
        }
    }

    @ViewBuilder
    private var prayerMiniPanel: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            if entry.isPrayerTimerActive {
                Button(intent: FinishPrayerTimerIntent()) {
                    WidgetPrayerMiniPanel(entry: entry)
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: StartPrayerTimerIntent()) {
                    WidgetMiniPanel(
                        title: "Prayer",
                        value: entry.prayerMinutesCompleted > 0 ? "\(entry.prayerMinutesCompleted)m" : "2 min",
                        footnote: entry.prayerSessionsCompleted > 0 ? "\(entry.prayerSessionsCompleted) sessions" : "Start timer",
                        symbol: "timer",
                        tint: WidgetTheme.blue
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            WidgetMiniPanel(
                title: "Prayer",
                value: entry.prayerMinutesCompleted > 0 ? "\(entry.prayerMinutesCompleted)m" : "2 min",
                footnote: "Open to pray",
                symbol: "timer",
                tint: WidgetTheme.blue
            )
        }
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
        .description("Focus block, Daily Word, streak, OVR, habits, and accountability.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct ClimbMissionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
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
                    IslandProtectionBadge(context: context, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    IslandTimerBlock(endsAt: context.state.endsAt)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(context.attributes.missionTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .truncationMode(.tail)

                        LiveActivityProgressLine(
                            startedAt: context.state.startedAt,
                            endsAt: context.state.endsAt,
                            tint: context.attributes.isBlockingActive ? WidgetTheme.green : WidgetTheme.sage
                        )
                        .frame(height: 4)

                        HStack(spacing: 6) {
                            Image(systemName: context.attributes.isBlockingActive ? "lock.shield.fill" : "timer")
                                .font(.caption2.weight(.bold))
                            Text(context.attributes.isBlockingActive ? "Protected focus" : "Focus session")
                                .font(.caption2.weight(.semibold))
                            Spacer(minLength: 6)
                            Text("Reflection next")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        .foregroundStyle(context.attributes.isBlockingActive ? WidgetTheme.green : WidgetTheme.sage)
                    }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                ActivityMark(isProtected: context.attributes.isBlockingActive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The Climb")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetTheme.secondaryText)
                    Text(context.state.focusLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(context.attributes.isBlockingActive ? WidgetTheme.green : WidgetTheme.sage)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .allowsTightening(true)
                }
                Spacer(minLength: 8)
                Text(context.attributes.appBlockingEnabled ? "Blocking" : "Focus")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.attributes.isBlockingActive ? WidgetTheme.green : WidgetTheme.sage)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((context.attributes.isBlockingActive ? WidgetTheme.green : WidgetTheme.sage).opacity(0.13), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(context.attributes.missionTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)

                LiveActivityProgressLine(
                    startedAt: context.state.startedAt,
                    endsAt: context.state.endsAt,
                    tint: context.attributes.isBlockingActive ? WidgetTheme.green : WidgetTheme.sage
                )
                .frame(height: 5)
            }

            HStack(alignment: .lastTextBaseline, spacing: 9) {
                Text(context.state.endsAt, style: .timer)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text("remaining")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                Spacer(minLength: 8)
                Text("\(max(context.attributes.durationMinutes, 1))m")
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(WidgetTheme.surfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(WidgetTheme.divider, lineWidth: 1)
                    }
            }

            Text("Stay with the focus block. Reflection is next.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .padding(18)
        .widgetURL(URL(string: "theclimb://open?tab=home"))
    }
}

private struct ActivityMark: View {
    let isProtected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill((isProtected ? WidgetTheme.green : WidgetTheme.sage).opacity(0.14))
            Image(systemName: isProtected ? "lock.shield.fill" : "mountain.2.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isProtected ? WidgetTheme.green : WidgetTheme.sage)
        }
        .frame(width: 34, height: 34)
    }
}

private struct IslandProtectionBadge: View {
    let context: ActivityViewContext<ClimbMissionAttributes>
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text("The Climb")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            Label(context.state.focusLabel, systemImage: context.attributes.isBlockingActive ? "lock.shield.fill" : "timer")
                .font(.caption.weight(.bold))
                .foregroundStyle(context.attributes.isBlockingActive ? WidgetTheme.green : WidgetTheme.sage)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .allowsTightening(true)
        }
    }
}

private struct IslandTimerBlock: View {
    let endsAt: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(endsAt, style: .timer)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text("remaining")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.56))
        }
    }
}

private struct LiveActivityProgressLine: View {
    let startedAt: Date
    let endsAt: Date
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 15)) { timeline in
            ProgressBar(value: progress(at: timeline.date), tint: tint)
        }
    }

    private func progress(at date: Date) -> Double {
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(startedAt) / total, 0), 1)
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

private struct WidgetPrayerState {
    private enum Keys {
        static let isRunning = "climb.prayer.isRunning"
        static let endsAt = "climb.prayer.endsAt"
        static let selectedMinutes = "climb.prayer.selectedMinutes"
        static let sessionsCompleted = "climb.prayer.sessionsCompleted"
        static let minutesCompleted = "climb.prayer.minutesCompleted"
    }

    let sessionsCompleted: Int
    let minutesCompleted: Int
    let selectedMinutes: Int
    let activeEndsAt: Date?

    init(defaults: UserDefaults) {
        sessionsCompleted = max(defaults.integer(forKey: Keys.sessionsCompleted), 0)
        minutesCompleted = max(defaults.integer(forKey: Keys.minutesCompleted), 0)
        selectedMinutes = max(defaults.integer(forKey: Keys.selectedMinutes), 2)

        let isRunning = defaults.bool(forKey: Keys.isRunning)
        let endsAtInterval = defaults.double(forKey: Keys.endsAt)
        let endsAt = endsAtInterval > 0 ? Date(timeIntervalSince1970: endsAtInterval) : nil
        if isRunning, let endsAt, endsAt > Date() {
            activeEndsAt = endsAt
        } else {
            activeEndsAt = nil
        }
    }

    var isActive: Bool {
        activeEndsAt != nil
    }
}

private enum WidgetTheme {
    static let black = Color(red: 7 / 255, green: 11 / 255, blue: 22 / 255)
    static let ink = Color(red: 9 / 255, green: 14 / 255, blue: 27 / 255)
    static let surface = Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255)
    static let surfaceRaised = Color(red: 23 / 255, green: 33 / 255, blue: 54 / 255)
    static let glassSurface = Color.white.opacity(0.070)
    static let divider = Color.white.opacity(0.085)
    static let dividerStrong = Color.white.opacity(0.135)
    static let primaryText = Color(red: 247 / 255, green: 247 / 255, blue: 245 / 255)
    static let secondaryText = Color(red: 156 / 255, green: 166 / 255, blue: 181 / 255)
    static let tertiaryText = Color(red: 102 / 255, green: 113 / 255, blue: 133 / 255)
    static let warmText = Color(red: 233 / 255, green: 221 / 255, blue: 199 / 255)
    static let green = Color(red: 169 / 255, green: 203 / 255, blue: 255 / 255)
    static let sage = Color(red: 140 / 255, green: 255 / 255, blue: 221 / 255)
    static let amber = Color(red: 179 / 255, green: 154 / 255, blue: 255 / 255)
    static let blue = Color(red: 169 / 255, green: 203 / 255, blue: 255 / 255)
    static let red = Color(red: 255 / 255, green: 123 / 255, blue: 134 / 255)
}

private extension ClimbWidgetEntry {
    var durationLabel: String {
        durationMinutes > 0 ? "\(durationMinutes)m" : "Today"
    }

    var conciseStatus: String {
        switch missionStatus.lowercased() {
        case "completed", "recovered":
            "Safe"
        case "active":
            "Live"
        case "failed":
            "Recover"
        default:
            durationLabel
        }
    }

    var primaryActionLabel: String {
        switch missionStatus.lowercased() {
        case "completed":
            "Reflection is next"
        case "recovered":
            "Recovery logged"
        case "active":
            appBlockingEnabled ? "Protected focus" : "Stay in the block"
        case "failed":
            "Take the recovery step"
        default:
            "Start today’s focus"
        }
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

    var defaultWidgetURL: URL? {
        URL(string: "theclimb://open?tab=home")
    }

    var missionWidgetURL: URL {
        URL(string: "theclimb://open?tab=home")!
    }

    var progressWidgetURL: URL? {
        URL(string: "theclimb://open?tab=progress")
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
                .font(.system(size: 10, weight: .semibold))
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

private struct WidgetCornerBeam: View {
    let tint: Color

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.28))
            .frame(width: 3, height: 46)
            .offset(x: -8, y: -8)
        .allowsHitTesting(false)
    }
}

private struct WidgetLogoDot: View {
    let tint: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(WidgetTheme.glassSurface)
                .overlay {
                    Circle()
                        .stroke(tint.opacity(0.38), lineWidth: 1)
                }
            Image(systemName: "arrow.up")
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

private struct WidgetStatusCapsule: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .black))
            .tracking(0.9)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.13), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            }
    }
}

private struct WidgetCommandStrip: View {
    let entry: ClimbWidgetEntry

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                WidgetCommandPill(text: entry.durationLabel, symbol: "timer", tint: WidgetTheme.warmText)
                WidgetCommandPill(text: "Level \(entry.missionDifficulty)", symbol: "bolt.fill", tint: WidgetTheme.amber)
                WidgetCommandPill(
                    text: entry.appBlockingEnabled ? "Blocking" : entry.missionCategory,
                    symbol: entry.appBlockingEnabled ? "lock.shield.fill" : "target",
                    tint: entry.appBlockingEnabled ? WidgetTheme.green : WidgetTheme.sage
                )
            }

            HStack(spacing: 6) {
                WidgetCommandPill(text: entry.durationLabel, symbol: "timer", tint: WidgetTheme.warmText)
                WidgetCommandPill(
                    text: entry.appBlockingEnabled ? "Blocking" : "L\(entry.missionDifficulty)",
                    symbol: entry.appBlockingEnabled ? "lock.shield.fill" : "bolt.fill",
                    tint: entry.appBlockingEnabled ? WidgetTheme.green : WidgetTheme.amber
                )
            }
        }
    }
}

private struct WidgetCommandPill: View {
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
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(WidgetTheme.glassSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(WidgetTheme.divider, lineWidth: 1)
            }
    }
}

private struct WidgetMomentumStack: View {
    let entry: ClimbWidgetEntry
    let streakProgress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(entry.streak)")
                    .font(.system(size: 26, weight: .bold).monospacedDigit())
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                Text("day")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(1)
            }

            ProgressBar(value: streakProgress, tint: WidgetTheme.sage)
                .frame(height: 4)

            HStack(spacing: 5) {
                Text("\(entry.ovr)")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                Text("OVR")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(WidgetTheme.glassSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WidgetTheme.dividerStrong, lineWidth: 1)
        }
    }
}

private struct WidgetWordChip: View {
    let entry: ClimbWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WORD")
                .font(.system(size: 8, weight: .black))
                .tracking(1.0)
                .foregroundStyle(WidgetTheme.amber)
                .lineLimit(1)

            Text(entry.verseReference)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)

            Text(entry.devotionalTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
        }
        .padding(10)
        .background(WidgetTheme.surfaceRaised.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WidgetTheme.divider, lineWidth: 1)
        }
    }
}

private struct WidgetHeroMetric: View {
    let title: String
    let value: String
    let footnote: String
    let progress: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                Text(title)
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }

            Text(footnote)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WidgetTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)

            ProgressBar(value: progress, tint: tint)
                .frame(height: 4)
        }
        .padding(10)
        .background(WidgetTheme.glassSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WidgetTheme.divider, lineWidth: 1)
        }
    }
}

private struct WidgetPartnerPanel: View {
    let entry: ClimbWidgetEntry

    var body: some View {
        WidgetMiniPanel(
            title: "Partner",
            value: entry.partnerName,
            footnote: entry.partnerSharedStreak > 0 ? "\(entry.partnerSharedStreak)d together · \(entry.partnerWeekCompletions)/7" : entry.partnerStatus,
            symbol: "person.2.fill",
            tint: WidgetTheme.sage
        )
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(WidgetTheme.surfaceRaised.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WidgetTheme.divider, lineWidth: 1)
        }
    }
}

private struct WidgetStreakCount: View {
    let entry: ClimbWidgetEntry

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(entry.streak)")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WidgetTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text("day streak")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WidgetTheme.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
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
        .background(WidgetTheme.surfaceRaised.opacity(0.74), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(WidgetTheme.divider, lineWidth: 1)
        }
    }
}

private struct WidgetPrayerMiniPanel: View {
    let entry: ClimbWidgetEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(WidgetTheme.blue.opacity(0.13))
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetTheme.blue)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Prayer")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let endsAt = entry.prayerTimerEndsAt {
                    Text(endsAt, style: .timer)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(WidgetTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .allowsTightening(true)
                } else {
                    Text("Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .allowsTightening(true)
                }
                Text("Tap when done")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(WidgetTheme.surfaceRaised.opacity(0.66), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WidgetTheme.divider, lineWidth: 1)
        }
    }
}

private struct WidgetDailyWordPanel: View {
    let entry: ClimbWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(entry.verseReference)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WidgetTheme.amber)
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("Daily Word")
                    .font(.system(size: 9, weight: .semibold))
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
        .background(WidgetTheme.surfaceRaised.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WidgetTheme.divider, lineWidth: 1)
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WidgetTheme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
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
        .background(WidgetTheme.surfaceRaised.opacity(0.66), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WidgetTheme.divider, lineWidth: 1)
        }
    }
}

private struct CompactMetric: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
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
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .allowsTightening(true)
            .truncationMode(.tail)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(WidgetTheme.surfaceRaised.opacity(0.62), in: Capsule())
    }
}

private struct ProgressBar: View {
    let value: Double
    var tint: Color = WidgetTheme.green

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetTheme.divider)
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
                .stroke(WidgetTheme.divider, lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(WidgetTheme.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(WidgetTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .allowsTightening(true)
                Text(caption)
                    .font(.system(size: 8, weight: .semibold))
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
                    .font(.system(size: 11, weight: .semibold))
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
                    .fill(WidgetTheme.green.opacity(0.12))
                Image(systemName: "person.2.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WidgetTheme.green)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
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
        .background(WidgetTheme.surfaceRaised.opacity(0.66), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WidgetTheme.divider, lineWidth: 1)
        }
    }
}

private extension View {
    func widgetBackground(emphasis: Color = WidgetTheme.green) -> some View {
        containerBackground(for: .widget) {
            WidgetTheme.black
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(emphasis.opacity(0.16))
                        .frame(height: 1)
                }
        }
    }
}
#endif
