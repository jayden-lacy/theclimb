import Combine
import Foundation
import WidgetKit

enum CommunityPostResult: Equatable {
    case posted
    case rejected(String)
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var missions: [Mission] = []
    @Published private(set) var devotionals: [Devotional] = []
    @Published private(set) var journalEntries: [ReflectionEntry] = []
    @Published private(set) var progress: [ProgressSnapshot] = []
    @Published private(set) var habits: [GrowthHabit] = []
    @Published private(set) var challenges: [GrowthChallenge] = []
    @Published private(set) var groups: [ClimbGroup] = []
    @Published private(set) var posts: [EncouragementPost] = []
    @Published private(set) var partners: [AccountabilityPartner] = []
    @Published private(set) var leaderboard: [LeaderboardEntry] = []
    @Published private(set) var blockedUserIDs: [String] = []
    @Published private(set) var moderationReports: [ModerationReport] = []
    @Published private(set) var focusState: FocusModeState = .unavailable
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let repository: AppRepository
    private let generationService: MissionGenerationService
    private let focusService: FocusBlockingService
    private let notificationScheduler: NotificationScheduling

    init(
        repository: AppRepository = FirebaseIntegration.repository(),
        generationService: MissionGenerationService = RemoteAIContentService(),
        focusService: FocusBlockingService = ScreenTimeFocusBlockingService(),
        notificationScheduler: NotificationScheduling = LocalNotificationScheduler()
    ) {
        self.repository = repository
        self.generationService = generationService
        self.focusService = focusService
        self.notificationScheduler = notificationScheduler
    }

    var todayMission: Mission? {
        missions.first { Calendar.current.isDateInToday($0.date) }
    }

    var todayDevotional: Devotional? {
        devotionals.first { Calendar.current.isDateInToday($0.date) }
    }

    var completionRate: Double {
        guard !missions.isEmpty else { return 0 }
        let completed = missions.filter { $0.status == .completed || $0.status == .recovered }.count
        return Double(completed) / Double(missions.count)
    }

    var visiblePosts: [EncouragementPost] {
        let blocked = Set(blockedUserIDs)
        let reportedPostIDs = Set(moderationReports.map(\.postID))
        return posts.filter { post in
            !blocked.contains(post.authorID) && !reportedPostIDs.contains(post.id)
        }
    }

    var weeklyReport: String {
        guard let profile else { return "Create your climb plan to begin tracking progress." }
        if profile.currentStreak == 0 {
            return "Recovery week. One honest mission today matters more than catching up."
        }
        return "Current streak: \(profile.currentStreak). Protect the next small promise."
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await repository.loadSnapshot()
            apply(snapshot)
            focusState = await focusService.refreshAuthorizationStatus()
            try await ensureTodayPlan()
            if reconcileStreaksWithMissionHistory() {
                try await save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshActiveSession() async {
        do {
            focusState = await focusService.refreshAuthorizationStatus()
            try await ensureTodayPlan()
            if reconcileStreaksWithMissionHistory() {
                try await save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeOnboarding(
        displayName: String,
        email: String,
        password: String,
        authenticatedUser: FirebaseSignedInUser? = nil,
        ageGroup: AgeGroup,
        goals: [String],
        struggle: Struggle,
        streakGoal: Int,
        notificationHour: Int,
        notificationMinute: Int
    ) async {
        let userID: String
        let resolvedDisplayName: String
        do {
            if let authenticatedUser {
                userID = authenticatedUser.id
                resolvedDisplayName = displayName.isEmpty ? authenticatedUser.displayName : displayName
            } else {
                userID = try await FirebaseIntegration.createOrSignInUser(
                    email: email,
                    password: password,
                    displayName: displayName
                )
                resolvedDisplayName = displayName.isEmpty ? "Climber" : displayName
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let profile = UserProfile(
            id: userID,
            displayName: resolvedDisplayName,
            ageGroup: ageGroup,
            goals: goals,
            mainStruggle: struggle,
            streakGoal: streakGoal,
            notificationHour: notificationHour,
            notificationMinute: notificationMinute,
            ovrScore: 50,
            currentStreak: 0,
            longestStreak: 0,
            recoveryStreak: 0,
            appBlockingEnabled: true,
            joinedAt: Date()
        )

        self.profile = profile
        groups = Self.seedGroups()
        posts = Self.seedPosts()
        partners = Self.seedPartners(for: struggle)
        leaderboard = Self.seedLeaderboard(profile: profile)
        await notificationScheduler.scheduleDailyReminder(hour: notificationHour, minute: notificationMinute)

        do {
            let plan = try await generationService.dailyPlan(for: profile, history: journalEntries)
            devotionals = [plan.devotional]
            missions = [plan.mission]
            habits = plan.habits
            challenges = plan.challenges
            recordProgressSnapshot()
            try await save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGoogleForOnboarding() async -> FirebaseSignedInUser? {
        do {
            return try await FirebaseIntegration.signInWithGoogle()
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func signInWithAppleForOnboarding() async -> FirebaseSignedInUser? {
        do {
            return try await FirebaseIntegration.signInWithApple()
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func startMission(_ mission: Mission) async {
        updateMission(mission.id) { $0.status = .active }
        focusState = await focusService.startFocus(for: mission)
        await persistQuietly()
    }

    func requestScreenTimeAuthorization() async {
        focusState = await focusService.requestAuthorization()
    }

    func refreshScreenTimeAuthorization() async {
        focusState = await focusService.refreshAuthorizationStatus()
    }

    func completeMission(
        missionID: String,
        hardestPart: String,
        lessonLearned: String,
        effortRating: Int,
        improvementPlan: String,
        mood: MoodRating
    ) async {
        guard var profile else { return }
        let previousStreak = profile.currentStreak
        updateMission(missionID) { $0.status = .completed }

        let entry = ReflectionEntry(
            id: UUID().uuidString,
            date: Date(),
            missionID: missionID,
            hardestPart: hardestPart,
            lessonLearned: lessonLearned,
            effortRating: effortRating,
            improvementPlan: improvementPlan,
            mood: mood,
            failureReason: nil
        )
        journalEntries.insert(entry, at: 0)

        let consistencyBonus = previousStreak >= 2 ? 2 : 0
        profile.ovrScore = min(100, profile.ovrScore + 4 + min(3, effortRating / 2) + consistencyBonus)
        self.profile = profile
        reconcileStreaksWithMissionHistory()
        if let profile = self.profile {
            syncLeaderboardProfile(profile)
        }

        await focusService.stopFocus()
        focusState = .unavailable
        recordProgressSnapshot()
        await persistQuietly()
    }

    func failMission(missionID: String, reason: String) async {
        guard var profile else { return }
        updateMission(missionID) { $0.status = .failed }
        profile.ovrScore = max(0, profile.ovrScore - 3)
        profile.currentStreak = 0
        self.profile = profile
        syncLeaderboardProfile(profile)

        let entry = ReflectionEntry(
            id: UUID().uuidString,
            date: Date(),
            missionID: missionID,
            hardestPart: reason,
            lessonLearned: "I need a recovery step instead of quitting the day.",
            effortRating: 1,
            improvementPlan: "Take the fallback mission and remove the first obstacle.",
            mood: .low,
            failureReason: reason
        )
        journalEntries.insert(entry, at: 0)

        await focusService.stopFocus()
        focusState = .unavailable
        await notificationScheduler.scheduleRecoveryPrompt()
        recordProgressSnapshot()
        await persistQuietly()
    }

    func completeFallback(missionID: String) async {
        guard var profile else { return }
        updateMission(missionID) { $0.status = .recovered }
        profile.ovrScore = min(100, profile.ovrScore + 2)
        profile.recoveryStreak += 1
        self.profile = profile
        reconcileStreaksWithMissionHistory()
        if let profile = self.profile {
            syncLeaderboardProfile(profile)
        }
        recordProgressSnapshot()
        await persistQuietly()
    }

    @discardableResult
    func addEncouragementPost(_ body: String) async -> CommunityPostResult {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile, !trimmedBody.isEmpty else { return .rejected("Write something before posting.") }
        guard CommunitySafetyFilter.isAllowed(trimmedBody) else {
            return .rejected("Edit the language and try again.")
        }

        posts.insert(
            EncouragementPost(
                id: UUID().uuidString,
                authorID: profile.id,
                author: profile.displayName,
                body: trimmedBody,
                createdAt: Date(),
                amenCount: 0
            ),
            at: 0
        )
        await persistQuietly()
        return .posted
    }

    func addAmen(to postID: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !blockedUserIDs.contains(posts[index].authorID) else { return }
        posts[index].amenCount += 1
        await persistQuietly()
    }

    func deletePost(_ postID: String) async -> Bool {
        guard let profile,
              let index = posts.firstIndex(where: { $0.id == postID }),
              posts[index].authorID == profile.id else {
            return false
        }

        do {
            try await repository.deleteUserDocument(collection: "posts", documentID: postID, userID: profile.id)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        posts.remove(at: index)
        moderationReports.removeAll { $0.postID == postID }
        await persistQuietly()
        return true
    }

    func reportPost(_ postID: String, reason: String) async -> Bool {
        guard let profile,
              let post = posts.first(where: { $0.id == postID }),
              post.authorID != profile.id,
              !moderationReports.contains(where: { $0.postID == postID && $0.reportedByUserID == profile.id }) else {
            return false
        }

        moderationReports.insert(
            ModerationReport(
                id: UUID().uuidString,
                postID: post.id,
                reportedUserID: post.authorID,
                reportedByUserID: profile.id,
                reason: reason,
                postBody: post.body,
                createdAt: Date()
            ),
            at: 0
        )
        await persistQuietly()
        return true
    }

    func blockUser(_ userID: String) async -> Bool {
        guard let profile, userID != profile.id, !blockedUserIDs.contains(userID) else {
            return false
        }

        blockedUserIDs.append(userID)
        await persistQuietly()
        return true
    }

    func isOwnPost(_ post: EncouragementPost) -> Bool {
        post.authorID == profile?.id
    }

    func joinGroup(_ groupID: String) async {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard !groups[index].isJoined else { return }
        groups[index].members += 1
        groups[index].isJoined = true
        await persistQuietly()
    }

    func checkIn(with partnerID: String) async {
        guard let index = partners.firstIndex(where: { $0.id == partnerID }) else { return }
        partners[index].lastCheckIn = "Just now"
        partners[index].checkInCount += 1
        partners[index].lastInteraction = "Checked in just now"
        await persistQuietly()
    }

    func nudgePartner(_ partnerID: String) async {
        guard let index = partners.firstIndex(where: { $0.id == partnerID }) else { return }
        partners[index].nudgeCount += 1
        partners[index].lastInteraction = "Nudge sent just now"
        await persistQuietly()
    }

    func encouragePartner(_ partnerID: String, message: String) async {
        guard let index = partners.firstIndex(where: { $0.id == partnerID }) else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        partners[index].encouragementCount += 1
        partners[index].lastInteraction = "Encouragement sent"
        await persistQuietly()
    }

    func toggleHabit(_ habit: GrowthHabit) async {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].isEnabled.toggle()
        await persistQuietly()
    }

    func updateProfile(
        displayName: String? = nil,
        struggle: Struggle? = nil,
        streakGoal: Int? = nil,
        appBlockingEnabled: Bool? = nil,
        notificationHour: Int? = nil,
        notificationMinute: Int? = nil
    ) async {
        guard var profile else { return }
        if let displayName {
            profile.displayName = displayName
        }
        if let struggle {
            profile.mainStruggle = struggle
            partners = Self.seedPartners(for: struggle)
        }
        if let streakGoal {
            profile.streakGoal = streakGoal
        }
        if let appBlockingEnabled {
            profile.appBlockingEnabled = appBlockingEnabled
            missions = missions.map { mission in
                var updated = mission
                if Calendar.current.isDateInToday(updated.date) {
                    updated.appBlockingEnabled = appBlockingEnabled
                }
                return updated
            }
        }
        if let notificationHour, let notificationMinute {
            profile.notificationHour = notificationHour
            profile.notificationMinute = notificationMinute
            await notificationScheduler.scheduleDailyReminder(hour: notificationHour, minute: notificationMinute)
        }
        self.profile = profile
        syncLeaderboardProfile(profile)
        await persistQuietly()
    }

    func resetLocalData() async {
        do {
            try await repository.clearLocalSnapshot()
            apply(.empty)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }

        do {
            await focusService.stopFocus()
            try FirebaseIntegration.signOut()
            try await repository.clearLocalSnapshot()
            apply(.empty)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount() async {
        isLoading = true
        defer { isLoading = false }

        do {
            await focusService.stopFocus()
            guard let userID = FirebaseIntegration.currentUserID else {
                try await repository.clearLocalSnapshot()
                apply(.empty)
                WidgetCenter.shared.reloadAllTimelines()
                return
            }

            try await repository.deleteAccountData(userID: userID)
            try await FirebaseIntegration.deleteCurrentAccount()
            try await repository.clearLocalSnapshot()
            apply(.empty)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureTodayPlan() async throws {
        guard let profile else { return }
        if todayMission != nil, todayDevotional != nil { return }

        let plan = try await generationService.dailyPlan(for: profile, history: journalEntries)
        devotionals.removeAll { Calendar.current.isDateInToday($0.date) }
        missions.removeAll { Calendar.current.isDateInToday($0.date) }
        devotionals.insert(plan.devotional, at: 0)
        missions.insert(plan.mission, at: 0)
        if habits.isEmpty {
            habits = plan.habits
        }
        if challenges.isEmpty {
            challenges = plan.challenges
        }
        try await save()
    }

    private func updateMission(_ id: String, mutation: (inout Mission) -> Void) {
        guard let index = missions.firstIndex(where: { $0.id == id }) else { return }
        mutation(&missions[index])
    }

    private func recordProgressSnapshot() {
        guard let profile else { return }
        progress.insert(
            ProgressSnapshot(
                id: UUID().uuidString,
                date: Date(),
                ovrScore: profile.ovrScore,
                currentStreak: profile.currentStreak,
                completionRate: completionRate,
                completedMissions: missions.filter { $0.status == .completed || $0.status == .recovered }.count,
                failedMissions: missions.filter { $0.status == .failed }.count
            ),
            at: 0
        )
        progress = Array(progress.prefix(30))
    }

    private func persistQuietly() async {
        do {
            try await save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async throws {
        try await repository.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var snapshot: AppStateSnapshot {
        AppStateSnapshot(
            profile: profile,
            missions: missions,
            devotionals: devotionals,
            journalEntries: journalEntries,
            progress: progress,
            habits: habits,
            challenges: challenges,
            groups: groups,
            posts: posts,
            partners: partners,
            leaderboard: leaderboard,
            blockedUserIDs: blockedUserIDs,
            moderationReports: moderationReports
        )
    }

    private func apply(_ snapshot: AppStateSnapshot) {
        profile = snapshot.profile
        missions = snapshot.missions
        devotionals = snapshot.devotionals.map(Self.enrichDevotionalIfNeeded)
        journalEntries = snapshot.journalEntries
        progress = snapshot.progress
        habits = snapshot.habits
        challenges = snapshot.challenges
        groups = snapshot.groups
        posts = snapshot.posts
        partners = snapshot.partners
        leaderboard = snapshot.leaderboard
        blockedUserIDs = snapshot.blockedUserIDs
        moderationReports = snapshot.moderationReports
        if let profile {
            ensureGlobalLeaderboardEntries(profile: profile)
            reconcileStreaksWithMissionHistory()
            if let profile = self.profile {
                syncLeaderboardProfile(profile)
            }
        }
    }

    @discardableResult
    private func reconcileStreaksWithMissionHistory() -> Bool {
        guard var profile else { return false }

        let calculatedStreak = calculatedCurrentStreak()
        let calculatedLongest = max(profile.longestStreak, calculatedStreak)
        guard profile.currentStreak != calculatedStreak || profile.longestStreak != calculatedLongest else {
            return false
        }

        profile.currentStreak = calculatedStreak
        profile.longestStreak = calculatedLongest
        self.profile = profile
        syncLeaderboardProfile(profile)
        return true
    }

    private func calculatedCurrentStreak() -> Int {
        let calendar = Calendar.current
        let today = Date().startOfDay

        if missions.contains(where: { calendar.isDate($0.date, inSameDayAs: today) && $0.status == .failed }) {
            return 0
        }

        let completedDays = Set(
            missions
                .filter { $0.status == .completed || $0.status == .recovered }
                .map { $0.date.startOfDay }
        )

        let yesterday = today.addingDays(-1)
        let startingDay: Date
        if completedDays.contains(today) {
            startingDay = today
        } else if completedDays.contains(yesterday) {
            startingDay = yesterday
        } else {
            return 0
        }

        var streak = 0
        var cursor = startingDay
        while completedDays.contains(cursor) {
            streak += 1
            cursor = cursor.addingDays(-1)
        }

        return streak
    }

    private func ensureGlobalLeaderboardEntries(profile: UserProfile) {
        if leaderboard.isEmpty {
            leaderboard = Self.seedLeaderboard(profile: profile)
            return
        }

        let existingNames = Set(leaderboard.map(\.name))
        for entry in Self.seedGlobalCompetitors() where !existingNames.contains(entry.name) {
            leaderboard.append(entry)
        }
    }

    private func syncLeaderboardProfile(_ profile: UserProfile) {
        let entry = LeaderboardEntry(
            id: profile.id,
            name: profile.displayName,
            ovrScore: profile.ovrScore,
            streak: profile.currentStreak
        )

        if let index = leaderboard.firstIndex(where: { $0.id == profile.id }) {
            leaderboard[index] = entry
        } else if let index = leaderboard.firstIndex(where: { $0.name == profile.displayName }) {
            leaderboard[index] = entry
        } else {
            leaderboard.insert(entry, at: 0)
        }

        leaderboard.sort {
            if $0.ovrScore == $1.ovrScore {
                return $0.streak > $1.streak
            }
            return $0.ovrScore > $1.ovrScore
        }
    }

    private static func enrichDevotionalIfNeeded(_ devotional: Devotional) -> Devotional {
        var updated = devotional
        if updated.verseText?.isEmpty ?? true {
            updated.verseText = verseText(reference: updated.bibleVerse, struggle: updated.struggle)
        }
        if updated.explanation.count < 320 {
            updated.explanation = longerExplanation(for: updated.struggle)
        }
        return updated
    }

    private static func verseText(reference: String, struggle: Struggle) -> String {
        switch reference {
        case "Colossians 3:23":
            return "\"And whatsoever ye do, do it heartily, as to the Lord, and not unto men.\""
        case "Luke 16:10":
            return "\"He that is faithful in that which is least is faithful also in much: and he that is unjust in the least is unjust also in much.\""
        case "Galatians 6:9":
            return "\"And let us not be weary in well doing: for in due season we shall reap, if we faint not.\""
        case "Psalm 51:10":
            return "\"Create in me a clean heart, O God; and renew a right spirit within me.\""
        case "1 Thessalonians 5:17":
            return "\"Pray without ceasing.\""
        case "Psalm 119:105":
            return "\"Thy word is a lamp unto my feet, and a light unto my path.\""
        case "Romans 12:2":
            return "\"And be not conformed to this world: but be ye transformed by the renewing of your mind.\""
        default:
            return verseText(reference: defaultVerseReference(for: struggle), struggle: struggle)
        }
    }

    private static func defaultVerseReference(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "Colossians 3:23"
        case .discipline:
            "Luke 16:10"
        case .consistency:
            "Galatians 6:9"
        case .purity:
            "Psalm 51:10"
        case .prayer:
            "1 Thessalonians 5:17"
        case .scripture:
            "Psalm 119:105"
        case .socialPressure:
            "Romans 12:2"
        }
    }

    private static func longerExplanation(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "This verse turns focus into worship. Your attention is not just a productivity tool; it is one of the ways you decide what gets authority over your day. When you work heartily before God, you stop letting notifications, pressure, and mood make every decision for you. Today is not about proving yourself to people. It is about giving God one honest, undivided block of obedience and finishing what is in front of you with a whole heart."
        case .discipline:
            "Jesus connects small faithfulness with larger responsibility. The task you keep avoiding may look ordinary, but it is training your ability to be trusted. Discipline grows when you choose the next right thing before it feels rewarding. Today, do not wait for a perfect mood or a dramatic reset. Choose faithfulness in the small thing, finish one concrete step, and let that obedience become evidence that you are becoming more dependable."
        case .consistency:
            "Paul does not pretend that doing good always feels exciting. He names the real danger: growing weary before the harvest is visible. Consistency is built in the gap between effort and results, when quitting would be easier than showing up again. Today is not about making up for every missed day. It is about refusing a zero day, taking one obedient step, and trusting that repeated faithfulness is never wasted in God’s hands."
        case .purity:
            "David asks God for more than behavior management; he asks for a clean heart and a renewed spirit. Self-control begins deeper than avoiding one trigger. It starts when you bring desire, shame, and weakness into God’s presence instead of hiding them. Today, protect your future self with one clear boundary, remove the first trigger before it becomes a fight, and ask God to renew what discipline alone cannot fix."
        case .prayer:
            "Prayer is not only a scheduled religious moment; it is the habit of returning to God throughout the day. A short honest prayer is better than a perfect prayer you never begin. This verse lowers the barrier. You can pray before the spiral grows, before the distraction wins, and before the pressure sets the tone. Today, speak plainly with God, return quickly when your mind wanders, and let prayer interrupt the drift."
        case .scripture:
            "The Word is called a lamp, not a floodlight. God often gives enough light for the next step before He shows the whole road. Scripture becomes practical when one verse is allowed to confront one real decision. Today, read slowly instead of rushing for volume. Write down the line that stands out, name the choice it is calling you toward, and obey the light you have before asking for more."
        case .socialPressure:
            "Pressure tries to shape you from the outside in, but transformation begins with a renewed mind. You do not have to become a copy of every room you enter. Courage grows when truth forms your choices before people test them. Today, decide your response before the pressure hits. Make one visible choice that matches your faith, even if it is quiet, and let obedience matter more than fitting in."
        }
    }

    private static func seedGroups() -> [ClimbGroup] {
        [
            ClimbGroup(id: UUID().uuidString, name: "Morning Climbers", subtitle: "Daily check-ins before school or work", members: 42, activeChallenge: "7-Day Climb"),
            ClimbGroup(id: UUID().uuidString, name: "Church Crew", subtitle: "Faith, focus, and honest recovery", members: 18, activeChallenge: "Quiet Hour")
        ]
    }

    private static func seedPosts() -> [EncouragementPost] {
        [
            EncouragementPost(
                id: UUID().uuidString,
                authorID: "seed-micah",
                author: "Micah",
                body: "No-zero day. Even a small obedient step counts.",
                createdAt: Date().addingTimeInterval(-1800),
                amenCount: 12
            ),
            EncouragementPost(
                id: UUID().uuidString,
                authorID: "seed-ari",
                author: "Ari",
                body: "Prayed before touching my phone this morning. Different start.",
                createdAt: Date().addingTimeInterval(-7200),
                amenCount: 8
            )
        ]
    }

    private static func seedPartners(for struggle: Struggle) -> [AccountabilityPartner] {
        [
            AccountabilityPartner(
                id: UUID().uuidString,
                name: "Jordan",
                focus: struggle,
                lastCheckIn: "Today",
                checkInCount: 3,
                nudgeCount: 1,
                encouragementCount: 2,
                lastInteraction: "Checked in today"
            ),
            AccountabilityPartner(
                id: UUID().uuidString,
                name: "Sam",
                focus: .consistency,
                lastCheckIn: "Yesterday",
                checkInCount: 2,
                nudgeCount: 0,
                encouragementCount: 1,
                lastInteraction: "Shared encouragement yesterday"
            )
        ]
    }

    private static func seedLeaderboard(profile: UserProfile) -> [LeaderboardEntry] {
        [LeaderboardEntry(id: profile.id, name: profile.displayName, ovrScore: profile.ovrScore, streak: profile.currentStreak)] + seedGlobalCompetitors()
    }

    private static func seedGlobalCompetitors() -> [LeaderboardEntry] {
        [
            LeaderboardEntry(id: UUID().uuidString, name: "Naomi", ovrScore: 91, streak: 24),
            LeaderboardEntry(id: UUID().uuidString, name: "Elijah", ovrScore: 86, streak: 18),
            LeaderboardEntry(id: UUID().uuidString, name: "Maya", ovrScore: 81, streak: 13),
            LeaderboardEntry(id: UUID().uuidString, name: "Micah", ovrScore: 74, streak: 6),
            LeaderboardEntry(id: UUID().uuidString, name: "Ari", ovrScore: 68, streak: 4),
            LeaderboardEntry(id: UUID().uuidString, name: "Jordan", ovrScore: 63, streak: 3),
            LeaderboardEntry(id: UUID().uuidString, name: "Sam", ovrScore: 58, streak: 2)
        ]
    }
}

private enum CommunitySafetyFilter {
    private static let blockedTerms = [
        "fuck",
        "shit",
        "bitch",
        "asshole",
        "kys",
        "kill yourself",
        "go die",
        "nigger",
        "faggot",
        "retard"
    ]

    static func isAllowed(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "!", with: "i")
            .replacingOccurrences(of: "3", with: "e")
            .replacingOccurrences(of: "4", with: "a")
            .replacingOccurrences(of: "@", with: "a")
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "$", with: "s")

        return !blockedTerms.contains { normalized.contains($0) }
    }
}
