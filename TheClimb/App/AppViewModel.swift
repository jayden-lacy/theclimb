import Combine
import Foundation
import WidgetKit

enum CommunityPostResult: Equatable {
    case posted
    case rejected(String)
}

enum OVRScoring {
    static let baseline = 50
    static let completedMission = 3
    static let reflectionSubmitted = 1
    static let highEffortBonus = 2
    static let consistencyBonus = 1
    static let recoveryMission = 3
    static let failedMissionPenalty = 5

    static func completionDelta(previousStreak: Int, effortRating: Int, missionDifficulty: Int, currentOVR: Int) -> Int {
        let rawScore = completedMission +
            reflectionSubmitted +
            min(highEffortBonus, max(0, effortRating - 3)) +
            (previousStreak >= 3 ? consistencyBonus : 0) +
            difficultyBonus(for: missionDifficulty)
        return scaledGain(rawScore, currentOVR: currentOVR, missionDifficulty: missionDifficulty)
    }

    static func recoveryDelta(currentOVR: Int) -> Int {
        scaledGain(recoveryMission, currentOVR: currentOVR, missionDifficulty: max(1, ovrDifficultyStep(for: currentOVR) - 1))
    }

    static func failurePenalty(currentOVR: Int, missionDifficulty: Int) -> Int {
        failedMissionPenalty +
            difficultyBonus(for: missionDifficulty) +
            (currentOVR >= 70 ? 1 : 0) +
            (currentOVR >= 85 ? 2 : 0) +
            (currentOVR >= 95 ? 2 : 0)
    }

    static func challengeDifficulty(for profile: UserProfile, completionRate: Double) -> Int {
        targetMissionDifficulty(for: profile, completionRate: completionRate, recentFailureCount: 0)
    }

    static func targetMissionDifficulty(
        for profile: UserProfile,
        completionRate: Double? = nil,
        recentFailureCount: Int = 0
    ) -> Int {
        let ovrLevel = ovrDifficultyStep(for: profile.ovrScore)
        let streakPressure = profile.currentStreak >= 14 ? 2 : (profile.currentStreak >= 5 ? 1 : 0)
        let consistencyPressure = (completionRate ?? 0) >= 0.85 ? 1 : 0
        let streakGoalPressure = profile.streakGoal >= 60 ? 1 : 0
        let starterAdjustment = profile.streakGoal <= 14 && profile.ovrScore < 60 ? -1 : 0
        let recoveryAdjustment = recentFailureCount > 0 && profile.currentStreak == 0 ? -1 : 0
        return min(5, max(1, ovrLevel + streakPressure + consistencyPressure + streakGoalPressure + starterAdjustment + recoveryAdjustment))
    }

    static func ovrDifficultyStep(for ovrScore: Int) -> Int {
        switch ovrScore {
        case ..<55:
            1
        case 55..<68:
            2
        case 68..<80:
            3
        case 80..<90:
            4
        default:
            5
        }
    }

    static func requiredChallengeCompletions(for difficulty: Int) -> Int {
        switch difficulty {
        case 1: 3
        case 2: 5
        case 3: 7
        case 4: 10
        default: 14
        }
    }

    static func challengeWindowDays(for difficulty: Int) -> Int {
        switch difficulty {
        case 1: 5
        case 2: 7
        case 3: 10
        case 4: 14
        default: 21
        }
    }

    static func minimumMissionMinutes(for difficulty: Int, ageGroup: AgeGroup) -> Int {
        let base = switch ageGroup {
        case .teen:
            15
        case .college:
            20
        case .youngAdult:
            25
        }
        return min(90, base + max(0, difficulty - 1) * 10)
    }

    static func growthMultiplier(for currentOVR: Int) -> Double {
        switch currentOVR {
        case ..<60:
            0.65
        case 60..<70:
            0.50
        case 70..<80:
            0.36
        case 80..<90:
            0.24
        case 90..<95:
            0.16
        default:
            0.10
        }
    }

    static func progressionLabel(for difficulty: Int) -> String {
        switch difficulty {
        case 1: "Foundation"
        case 2: "Pressure"
        case 3: "Endurance"
        case 4: "Conviction"
        default: "Mastery"
        }
    }

    static func missionPressureLine(for difficulty: Int) -> String {
        switch difficulty {
        case 1:
            "Level 1: finish the simple version without skipping reflection."
        case 2:
            "Level 2: add resistance by protecting the full timer and removing the first distraction."
        case 3:
            "Level 3: finish the mission and add one accountability check-in afterward."
        case 4:
            "Level 4: complete the full mission with app blocking, reflection, and a concrete next step."
        default:
            "Level 5: protect the full window, remove every known trigger, and report the result to your partner."
        }
    }

    private static func difficultyBonus(for missionDifficulty: Int) -> Int {
        max(0, min(missionDifficulty, 5) - 2)
    }

    private static func scaledGain(_ rawScore: Int, currentOVR: Int, missionDifficulty: Int) -> Int {
        let expectedDifficulty = ovrDifficultyStep(for: currentOVR)
        let underLevelPenalty = max(0, expectedDifficulty - missionDifficulty) * 2
        let adjustedRawScore = rawScore - underLevelPenalty

        guard adjustedRawScore > 0 else { return 0 }
        if currentOVR >= 80 && missionDifficulty < expectedDifficulty {
            return 0
        }

        let scaled = Int((Double(adjustedRawScore) * growthMultiplier(for: currentOVR)).rounded())
        return max(1, scaled)
    }

    static var visibleRules: [(String, String, String)] {
        [
            ("Complete mission", "+1-3", "Easy wins help early, but gains slow as OVR rises."),
            ("Submit reflection", "+1", "Reflection is required before OVR moves."),
            ("Strong effort", "+1-2", "Higher effort can add a small bonus."),
            ("Consistency", "+1", "Earned after protecting a streak."),
            ("Harder mission", "+1-3", "Higher-level missions are required to grow past high OVR."),
            ("Recovery mission", "+0-2", "Recovery helps, but it cannot replace completing the main mission."),
            ("Failed mission", "-5+", "Missing a harder mission costs more.")
        ]
    }
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
    @Published private(set) var notificationState: NotificationPermissionState = .notDetermined
    @Published private(set) var isRefreshingLeaderboard = false
    @Published private(set) var isRefreshingGroups = false
    @Published private(set) var isRefreshingPosts = false
    @Published private(set) var isRefreshingPartners = false
    @Published private(set) var latestPartnerInviteCode: String?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published private(set) var isPreparingTodayPlan = false

    private let repository: AppRepository
    private let generationService: MissionGenerationService
    private let focusService: FocusBlockingService
    private let notificationScheduler: NotificationScheduling
    private var missionMutationsInFlight: Set<String> = []

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

    var activeHabits: [GrowthHabit] {
        habits.filter(\.isEnabled)
    }

    var todayHabitCompletionCount: Int {
        activeHabits.filter { $0.isCompleted() }.count
    }

    var todayHabitCompletionRate: Double {
        let active = activeHabits
        guard !active.isEmpty else { return 0 }
        return Double(active.filter { $0.isCompleted() }.count) / Double(active.count)
    }

    var failedMissionCount: Int {
        failedMissionIDs.count
    }

    private var recentFailureCount: Int {
        let recentMissionFailures = missions
            .sorted { $0.date > $1.date }
            .prefix(5)
            .filter { $0.status == .failed }
            .count
        let recentJournalFailures = journalEntries
            .prefix(5)
            .filter {
                guard let reason = $0.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
                return !reason.isEmpty
            }
            .count
        return max(recentMissionFailures, recentJournalFailures)
    }

    private var failedMissionIDs: Set<String> {
        var ids = Set(missions.filter { $0.status == .failed }.map(\.id))
        for entry in journalEntries {
            guard let reason = entry.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !reason.isEmpty else { continue }
            ids.insert(entry.missionID)
        }
        return ids
    }

    var visiblePosts: [EncouragementPost] {
        let blocked = Set(blockedUserIDs)
        let reportedPostIDs = Set(moderationReports.map(\.postID))
        return posts.filter { post in
            !blocked.contains(post.authorID) && !reportedPostIDs.contains(post.id)
        }
    }

    var requiresPasswordForAccountDeletion: Bool {
        FirebaseIntegration.requiresPasswordForAccountDeletion
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

        do {
            let snapshot = try await repository.loadSnapshot()
            let needsSave = apply(snapshot)
            try await refreshCurrentSession(forceSave: needsSave)
            isLoading = false
            await refreshGlobalLeaderboard()
            await refreshCommunityFeed()
            await refreshCommunityGroups()
            await refreshAccountabilityPartners()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func refreshActiveSession() async {
        do {
            try await refreshCurrentSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshGlobalLeaderboard() async {
        guard !isRefreshingLeaderboard else { return }
        isRefreshingLeaderboard = true
        defer { isRefreshingLeaderboard = false }

        do {
            let entries = try await repository.loadGlobalLeaderboard(limit: 100)
            applyGlobalLeaderboard(entries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshCommunityGroups() async {
        guard !isRefreshingGroups else { return }
        isRefreshingGroups = true
        defer { isRefreshingGroups = false }

        do {
            groups = try await repository.loadCommunityGroups(limit: 50)
            try await save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshCommunityFeed() async {
        guard !isRefreshingPosts else { return }
        isRefreshingPosts = true
        defer { isRefreshingPosts = false }

        do {
            posts = try await repository.loadRecentEncouragementPosts(limit: 100)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAccountabilityPartners() async {
        guard !isRefreshingPartners, let profile else { return }
        isRefreshingPartners = true
        defer { isRefreshingPartners = false }

        do {
            partners = try await repository.loadAccountabilityPartners(for: profile)
            try await save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
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
    ) async -> Bool {
        let previousSnapshot = snapshot
        let userID: String
        let resolvedDisplayName: String

        do {
            if let authenticatedUser {
                if !authenticatedUser.isNewUser, try await loadSignedInSnapshotIfAvailable() {
                    return true
                }
                userID = authenticatedUser.id
                resolvedDisplayName = displayName.isEmpty ? authenticatedUser.displayName : displayName
            } else if let signedInUser = FirebaseIntegration.currentSignedInUser(matchingEmail: email) {
                userID = signedInUser.id
                resolvedDisplayName = displayName.isEmpty ? signedInUser.displayName : displayName
            } else {
                do {
                    let createdUser = try await FirebaseIntegration.createUser(
                        email: email,
                        password: password,
                        displayName: displayName
                    )
                    userID = createdUser.id
                    resolvedDisplayName = displayName.isEmpty ? createdUser.displayName : displayName
                } catch FirebaseIntegrationError.accountAlreadyExists {
                    let signedInUser = try await FirebaseIntegration.signInExistingUser(email: email, password: password)
                    if try await loadSignedInSnapshotIfAvailable() {
                        return true
                    }
                    userID = signedInUser.id
                    resolvedDisplayName = displayName.isEmpty ? signedInUser.displayName : displayName
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
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
            ovrScore: OVRScoring.baseline,
            currentStreak: 0,
            longestStreak: 0,
            recoveryStreak: 0,
            appBlockingEnabled: true,
            joinedAt: Date()
        )

        self.profile = profile
        groups = []
        posts = []
        partners = []
        leaderboard = Self.seedLeaderboard(profile: profile)
        notificationState = await notificationScheduler.authorizationState()

        do {
            let plan = try await generationService.dailyPlan(for: profile, history: journalEntries)
            devotionals = [plan.devotional]
            missions = [plan.mission]
            habits = plan.habits
            challenges = plan.challenges
            recordProgressSnapshot()
            try await save()
            await notificationScheduler.scheduleDailyReminder(hour: notificationHour, minute: notificationMinute)
            return true
        } catch {
            restoreSnapshot(previousSnapshot)
            errorMessage = error.localizedDescription
            return false
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

    func signInWithEmailForOnboarding(email: String, password: String) async {
        do {
            try await FirebaseIntegration.signInExistingUser(email: email, password: password)
            try await loadSignedInSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSignedInAccountForOnboarding() async {
        do {
            try await loadSignedInSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func shouldContinueNewProfileAfterSocialSignIn() async -> Bool {
        do {
            let didLoadExistingProfile = try await loadSignedInSnapshotIfAvailable()
            return !didLoadExistingProfile
        } catch {
            errorMessage = error.localizedDescription
            return false
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

    private func loadSignedInSnapshot() async throws {
        guard try await loadSignedInSnapshotIfAvailable() else {
            try? FirebaseIntegration.signOut()
            throw FirebaseIntegrationError.savedProfileMissing
        }
    }

    private func loadSignedInSnapshotIfAvailable() async throws -> Bool {
        let snapshot = try await repository.loadSnapshot()
        if snapshot.profile != nil {
            _ = apply(snapshot)
            try await refreshCurrentSession()
            WidgetCenter.shared.reloadAllTimelines()
            return true
        }

        guard try await FirebaseIntegration.currentUserHasSavedProfile() else {
            return false
        }

        throw FirebaseIntegrationError.decodingFailed
    }

    func startMission(_ mission: Mission, endsAt: Date? = nil) async {
        updateMission(mission.id) { $0.status = .active }
        let focusEndsAt = endsAt ?? Date().addingTimeInterval(TimeInterval(max(mission.durationMinutes, 1) * 60))
        ActiveFocusMissionTimerStore.save(mission: mission, endsAt: focusEndsAt)
        focusState = await focusService.startFocus(for: mission, endsAt: focusEndsAt)
        await MissionLiveActivityService.start(for: mission, endsAt: focusEndsAt, focusState: focusState)
        await notificationScheduler.scheduleMissionTimerEnded(for: mission, at: focusEndsAt)
        await refreshNotificationSchedule()
        await persistQuietly()
    }

    func stopMissionFocus() async {
        await focusService.stopFocus()
        await MissionLiveActivityService.end()
        focusState = await focusService.refreshAuthorizationStatus()
        await notificationScheduler.cancelMissionTimerEnded()
        await notificationScheduler.cancelIncompleteMissionReminder()
    }

    func requestScreenTimeAuthorization() async {
        focusState = await focusService.requestAuthorization()
    }

    func requestNotificationAuthorization() async {
        notificationState = await notificationScheduler.requestAuthorization()
        await refreshNotificationSchedule()
    }

    func refreshScreenTimeAuthorization() async {
        focusState = await focusService.refreshAuthorizationStatus()
    }

    func refreshNotificationAuthorization() async {
        notificationState = await notificationScheduler.authorizationState()
    }

    @discardableResult
    func completeMission(
        missionID: String,
        hardestPart: String,
        lessonLearned: String,
        effortRating: Int,
        improvementPlan: String,
        mood: MoodRating
    ) async -> Bool {
        guard beginMissionMutation(missionID) else { return false }
        defer { endMissionMutation(missionID) }
        guard var profile else { return false }
        guard let missionIndex = missions.firstIndex(where: { $0.id == missionID }) else { return false }

        let mission = missions[missionIndex]
        switch mission.status {
        case .completed, .recovered:
            return true
        case .failed:
            errorMessage = "This mission is already marked missed. Complete the recovery step instead."
            return false
        case .pending, .active:
            break
        }

        let previousSnapshot = snapshot
        let previousStreak = profile.currentStreak
        missions[missionIndex].status = .completed
        advanceChallenges(for: mission)

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

        profile.ovrScore = min(
            100,
            profile.ovrScore + OVRScoring.completionDelta(
                previousStreak: previousStreak,
                effortRating: effortRating,
                missionDifficulty: mission.difficulty,
                currentOVR: profile.ovrScore
            )
        )
        self.profile = profile
        reconcileAdaptiveChallenges()
        reconcileStreaksWithMissionHistory()
        if let profile = self.profile {
            syncLeaderboardProfile(profile)
        }
        recordProgressSnapshot()

        do {
            try await save()
        } catch {
            restoreSnapshot(previousSnapshot)
            errorMessage = error.localizedDescription
            return false
        }

        await focusService.stopFocus()
        await MissionLiveActivityService.end(missionID: missionID)
        focusState = .unavailable
        await notificationScheduler.cancelMissionTimerEnded()
        await notificationScheduler.cancelIncompleteMissionReminder()
        return true
    }

    @discardableResult
    func failMission(missionID: String, reason: String) async -> Bool {
        guard beginMissionMutation(missionID) else { return false }
        defer { endMissionMutation(missionID) }
        guard var profile else { return false }
        guard let missionIndex = missions.firstIndex(where: { $0.id == missionID }) else { return false }
        guard missions[missionIndex].status != .completed, missions[missionIndex].status != .recovered else { return false }

        let previousSnapshot = snapshot
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldApplyPenalty = missions[missionIndex].status != .failed
        missions[missionIndex].status = .failed

        if shouldApplyPenalty {
            profile.ovrScore = max(
                0,
                profile.ovrScore - OVRScoring.failurePenalty(
                    currentOVR: profile.ovrScore,
                    missionDifficulty: missions[missionIndex].difficulty
                )
            )
            profile.currentStreak = 0
        }
        self.profile = profile
        syncLeaderboardProfile(profile)

        if let existingIndex = journalEntries.firstIndex(where: { $0.missionID == missionID && $0.failureReason != nil }) {
            journalEntries[existingIndex].date = Date()
            journalEntries[existingIndex].hardestPart = trimmedReason
            journalEntries[existingIndex].failureReason = trimmedReason
        } else {
            let entry = ReflectionEntry(
                id: UUID().uuidString,
                date: Date(),
                missionID: missionID,
                hardestPart: trimmedReason,
                lessonLearned: "I need a recovery step instead of quitting the day.",
                effortRating: 1,
                improvementPlan: "Take the fallback mission and remove the first obstacle.",
                mood: .low,
                failureReason: trimmedReason
            )
            journalEntries.insert(entry, at: 0)
        }

        if shouldApplyPenalty {
            recordProgressSnapshot()
        }

        do {
            try await save()
        } catch {
            restoreSnapshot(previousSnapshot)
            errorMessage = error.localizedDescription
            return false
        }

        await focusService.stopFocus()
        await MissionLiveActivityService.end(missionID: missionID)
        focusState = .unavailable
        await notificationScheduler.cancelMissionTimerEnded()
        await notificationScheduler.cancelIncompleteMissionReminder()
        await notificationScheduler.scheduleRecoveryPrompt()
        return true
    }

    @discardableResult
    func completeFallback(missionID: String) async -> Bool {
        guard beginMissionMutation(missionID) else { return false }
        defer { endMissionMutation(missionID) }
        guard var profile else { return false }
        guard let missionIndex = missions.firstIndex(where: { $0.id == missionID }) else { return false }

        switch missions[missionIndex].status {
        case .recovered, .completed:
            return true
        case .failed:
            break
        case .pending, .active:
            errorMessage = "Log the miss before completing recovery."
            return false
        }

        let previousSnapshot = snapshot
        missions[missionIndex].status = .recovered
        profile.ovrScore = min(100, profile.ovrScore + OVRScoring.recoveryDelta(currentOVR: profile.ovrScore))
        profile.recoveryStreak += 1
        self.profile = profile
        reconcileAdaptiveChallenges()
        reconcileStreaksWithMissionHistory()
        if let profile = self.profile {
            syncLeaderboardProfile(profile)
        }
        recordProgressSnapshot()

        do {
            try await save()
        } catch {
            restoreSnapshot(previousSnapshot)
            errorMessage = error.localizedDescription
            return false
        }

        await notificationScheduler.cancelIncompleteMissionReminder()
        return true
    }

    @discardableResult
    func addEncouragementPost(_ body: String) async -> CommunityPostResult {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile, !trimmedBody.isEmpty else { return .rejected("Write something before posting.") }
        guard CommunitySafetyFilter.isAllowed(trimmedBody) else {
            return .rejected("Edit the language and try again.")
        }

        let post = EncouragementPost(
            id: UUID().uuidString,
            authorID: profile.id,
            author: profile.displayName,
            body: trimmedBody,
            createdAt: Date(),
            amenCount: 0
        )

        posts.insert(post, at: 0)
        do {
            let createdPost = try await repository.createEncouragementPost(post)
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = createdPost
            }
            await refreshCommunityFeed()
            return .posted
        } catch {
            posts.removeAll { $0.id == post.id }
            errorMessage = error.localizedDescription
            return .rejected("Unable to post right now.")
        }
    }

    func addAmen(to postID: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !blockedUserIDs.contains(posts[index].authorID) else { return }
        posts[index].amenCount += 1

        do {
            try await repository.addAmen(to: postID)
            await refreshCommunityFeed()
        } catch {
            if let restoreIndex = posts.firstIndex(where: { $0.id == postID }) {
                posts[restoreIndex].amenCount = max(0, posts[restoreIndex].amenCount - 1)
            }
            errorMessage = error.localizedDescription
        }
    }

    func deletePost(_ postID: String) async -> Bool {
        guard let profile,
              let index = posts.firstIndex(where: { $0.id == postID }),
              posts[index].authorID == profile.id else {
            return false
        }

        do {
            try await repository.deleteEncouragementPost(postID: postID, authorID: profile.id)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        posts.remove(at: index)
        moderationReports.removeAll { $0.postID == postID }
        await refreshCommunityFeed()
        return true
    }

    func reportPost(_ postID: String, reason: String) async -> Bool {
        guard let profile,
              let post = posts.first(where: { $0.id == postID }),
              post.authorID != profile.id,
              !moderationReports.contains(where: { $0.postID == postID && $0.reportedByUserID == profile.id }) else {
            return false
        }

        let report = ModerationReport(
            id: UUID().uuidString,
            postID: post.id,
            reportedUserID: post.authorID,
            reportedByUserID: profile.id,
            reason: reason,
            postBody: post.body,
            createdAt: Date()
        )

        do {
            try await repository.reportEncouragementPost(report)
            moderationReports.insert(report, at: 0)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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

    @discardableResult
    func joinGroup(_ groupID: String) async -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return false }
        guard !groups[index].isJoined else { return true }
        let previousGroup = groups[index]
        groups[index].members += 1
        groups[index].isJoined = true
        if let profile {
            groups[index].memberIDs.append(profile.id)
            groups[index].memberIDs = Array(Set(groups[index].memberIDs))
            groups[index].memberNames[profile.id] = profile.displayName
        }

        do {
            try await repository.joinCommunityGroup(groupID, displayName: profile?.displayName ?? "Climber")
            try await save()
            await refreshCommunityGroups()
            return true
        } catch {
            if let restoreIndex = groups.firstIndex(where: { $0.id == groupID }) {
                groups[restoreIndex] = previousGroup
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func leaveGroup(_ groupID: String) async -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return false }
        guard groups[index].isJoined else { return true }
        guard !groups[index].isOwner(profile?.id) else {
            errorMessage = "Group owners must delete the group instead of leaving it."
            return false
        }
        let previousGroup = groups[index]
        groups[index].members = max(0, groups[index].members - 1)
        groups[index].isJoined = false
        if let userID = profile?.id {
            groups[index].memberIDs.removeAll { $0 == userID }
            groups[index].adminIDs.removeAll { $0 == userID }
            groups[index].memberNames.removeValue(forKey: userID)
        }

        do {
            try await repository.leaveCommunityGroup(groupID)
            try await save()
            await refreshCommunityGroups()
            return true
        } catch {
            if let restoreIndex = groups.firstIndex(where: { $0.id == groupID }) {
                groups[restoreIndex] = previousGroup
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func checkInWithGroup(_ groupID: String) async -> Bool {
        guard let group = groups.first(where: { $0.id == groupID && $0.isJoined }) else {
            return false
        }

        let result = await addEncouragementPost("Checked in with \(group.name) for \(group.activeChallenge).")
        return result == .posted
    }

    func logChallengeStep(_ challengeID: String) async -> Bool {
        guard let index = challenges.firstIndex(where: { $0.id == challengeID }),
              !challenges[index].isComplete else {
            return false
        }

        let previousChallenges = challenges
        let previousProfile = profile
        let previousProgress = progress
        let target = max(challenges[index].targetCompletions, 1)
        challenges[index].completedCount = min(challenges[index].completedCount + 1, target)
        challenges[index].daysRemaining = max(challenges[index].daysRemaining - 1, 1)

        if challenges[index].isComplete, var profile {
            let reward = challenges[index].difficulty >= 4 ? 2 : 1
            profile.ovrScore = min(100, profile.ovrScore + reward)
            self.profile = profile
            syncLeaderboardProfile(profile)
            recordProgressSnapshot()
        }

        do {
            try await save()
            return true
        } catch {
            challenges = previousChallenges
            profile = previousProfile
            progress = previousProgress
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createGroup(name: String, subtitle: String, challenge: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChallenge = challenge.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty,
              !trimmedSubtitle.isEmpty,
              !trimmedChallenge.isEmpty,
              CommunitySafetyFilter.isAllowed(trimmedName),
              CommunitySafetyFilter.isAllowed(trimmedSubtitle),
              CommunitySafetyFilter.isAllowed(trimmedChallenge) else {
            return false
        }

        guard let profile else { return false }
        let group = ClimbGroup(
            id: UUID().uuidString,
            name: String(trimmedName.prefix(42)),
            subtitle: String(trimmedSubtitle.prefix(96)),
            members: 1,
            activeChallenge: String(trimmedChallenge.prefix(40)),
            isJoined: true,
            ownerID: profile.id,
            adminIDs: [profile.id],
            memberIDs: [profile.id],
            memberNames: [profile.id: profile.displayName]
        )

        do {
            let createdGroup = try await repository.createCommunityGroup(group)
            groups.removeAll { $0.id == createdGroup.id }
            groups.insert(createdGroup, at: 0)
            try await save()
            await refreshCommunityGroups()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateGroupDetails(groupID: String, name: String, subtitle: String, challenge: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChallenge = challenge.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let profile,
              let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].isAdmin(profile.id),
              !trimmedName.isEmpty,
              !trimmedSubtitle.isEmpty,
              !trimmedChallenge.isEmpty,
              CommunitySafetyFilter.isAllowed(trimmedName),
              CommunitySafetyFilter.isAllowed(trimmedSubtitle),
              CommunitySafetyFilter.isAllowed(trimmedChallenge) else {
            return false
        }

        let previousGroup = groups[index]
        groups[index].name = String(trimmedName.prefix(42))
        groups[index].subtitle = String(trimmedSubtitle.prefix(96))
        groups[index].activeChallenge = String(trimmedChallenge.prefix(40))

        do {
            try await repository.updateCommunityGroupDetails(
                groupID: groupID,
                name: groups[index].name,
                subtitle: groups[index].subtitle,
                challenge: groups[index].activeChallenge
            )
            try await save()
            await refreshCommunityGroups()
            return true
        } catch {
            if let restoreIndex = groups.firstIndex(where: { $0.id == groupID }) {
                groups[restoreIndex] = previousGroup
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setGroupAdmin(groupID: String, memberID: String, isAdmin: Bool) async -> Bool {
        guard let profile,
              let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].isAdmin(profile.id),
              groups[index].memberIDs.contains(memberID),
              !groups[index].isOwner(memberID) else {
            return false
        }

        let previousGroup = groups[index]
        if isAdmin {
            if !groups[index].adminIDs.contains(memberID) {
                groups[index].adminIDs.append(memberID)
            }
        } else {
            groups[index].adminIDs.removeAll { $0 == memberID }
        }

        do {
            try await repository.setCommunityGroupAdmin(groupID: groupID, memberID: memberID, isAdmin: isAdmin)
            try await save()
            await refreshCommunityGroups()
            return true
        } catch {
            if let restoreIndex = groups.firstIndex(where: { $0.id == groupID }) {
                groups[restoreIndex] = previousGroup
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeGroupMember(groupID: String, memberID: String) async -> Bool {
        guard let profile,
              let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].isAdmin(profile.id),
              memberID != profile.id,
              !groups[index].isOwner(memberID) else {
            return false
        }

        let previousGroup = groups[index]
        groups[index].memberIDs.removeAll { $0 == memberID }
        groups[index].adminIDs.removeAll { $0 == memberID }
        groups[index].memberNames.removeValue(forKey: memberID)
        groups[index].members = groups[index].memberIDs.count

        do {
            try await repository.removeCommunityGroupMember(groupID: groupID, memberID: memberID)
            try await save()
            await refreshCommunityGroups()
            return true
        } catch {
            if let restoreIndex = groups.firstIndex(where: { $0.id == groupID }) {
                groups[restoreIndex] = previousGroup
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteGroup(_ groupID: String) async -> Bool {
        guard let profile,
              let group = groups.first(where: { $0.id == groupID }),
              group.isAdmin(profile.id) else {
            return false
        }

        let previousGroups = groups
        groups.removeAll { $0.id == groupID }

        do {
            try await repository.deleteCommunityGroup(groupID)
            try await save()
            await refreshCommunityGroups()
            return true
        } catch {
            groups = previousGroups
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createPartnerInvite() async -> String? {
        guard let profile else { return nil }
        do {
            let code = try await repository.createAccountabilityPartnerInvite(for: profile)
            latestPartnerInviteCode = code
            await refreshAccountabilityPartners()
            return code
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func acceptPartnerInvite(code: String) async -> Bool {
        guard let profile else { return false }
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode.count >= 4 else { return false }

        do {
            try await repository.acceptAccountabilityPartnerInvite(code: normalizedCode, profile: profile)
            await refreshAccountabilityPartners()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func checkIn(with partnerID: String) async {
        guard let index = partners.firstIndex(where: { $0.id == partnerID }),
              !partners[index].isPending else { return }
        partners[index].lastCheckIn = "Just now"
        partners[index].checkInCount += 1
        partners[index].lastInteraction = "Checked in just now"
        partners[index].lastCheckInDate = Date()
        partners[index].weeklyCompletions = min(partners[index].weeklyCompletions + 1, 7)
        let partner = partners[index]
        do {
            try await repository.updateAccountabilityPartnerActivity(partner, action: .checkIn, message: nil)
            try await save()
            await refreshAccountabilityPartners()
        } catch {
            errorMessage = error.localizedDescription
            await persistQuietly()
        }
    }

    func nudgePartner(_ partnerID: String) async {
        guard let index = partners.firstIndex(where: { $0.id == partnerID }),
              !partners[index].isPending else { return }
        partners[index].nudgeCount += 1
        partners[index].lastInteraction = "Nudge sent just now"
        let partner = partners[index]
        do {
            try await repository.updateAccountabilityPartnerActivity(partner, action: .nudge, message: nil)
            try await save()
            await refreshAccountabilityPartners()
        } catch {
            errorMessage = error.localizedDescription
            await persistQuietly()
        }
    }

    func encouragePartner(_ partnerID: String, message: String) async {
        guard let index = partners.firstIndex(where: { $0.id == partnerID }),
              !partners[index].isPending else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        partners[index].encouragementCount += 1
        partners[index].lastInteraction = "Encouragement sent"
        let partner = partners[index]
        do {
            try await repository.updateAccountabilityPartnerActivity(partner, action: .encouragement, message: trimmedMessage)
            try await save()
            await refreshAccountabilityPartners()
        } catch {
            errorMessage = error.localizedDescription
            await persistQuietly()
        }
    }

    func toggleHabit(_ habit: GrowthHabit) async {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].isEnabled.toggle()
        await persistQuietly()
    }

    func setHabitEnabled(_ habitID: String, isEnabled: Bool) async {
        guard let index = habits.firstIndex(where: { $0.id == habitID }) else { return }
        guard habits[index].isEnabled != isEnabled else { return }
        habits[index].isEnabled = isEnabled
        await persistQuietly()
    }

    func toggleHabitCompletion(_ habitID: String) async {
        guard let index = habits.firstIndex(where: { $0.id == habitID }) else { return }
        guard habits[index].isEnabled else { return }
        habits[index].toggleCompletion()
        await persistQuietly()
    }

    @discardableResult
    func updateProfile(
        displayName: String? = nil,
        struggle: Struggle? = nil,
        streakGoal: Int? = nil,
        appBlockingEnabled: Bool? = nil,
        notificationHour: Int? = nil,
        notificationMinute: Int? = nil
    ) async -> Bool {
        guard var profile else { return false }
        let previousSnapshot = snapshot

        if let displayName {
            profile.displayName = displayName
        }
        if let struggle {
            profile.mainStruggle = struggle
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
        }
        self.profile = profile
        syncLeaderboardProfile(profile)

        do {
            try await save()
            await refreshNotificationSchedule()
            return true
        } catch {
            restoreSnapshot(previousSnapshot)
            await refreshNotificationSchedule()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }

        do {
            await focusService.stopFocus()
            await MissionLiveActivityService.end()
            await notificationScheduler.cancelMissionTimerEnded()
            try FirebaseIntegration.signOut()
            try await repository.clearLocalSnapshot()
            apply(.empty)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount(password: String? = nil) async {
        isLoading = true
        defer { isLoading = false }

        do {
            await focusService.stopFocus()
            await MissionLiveActivityService.end()
            await notificationScheduler.cancelMissionTimerEnded()
            guard let userID = FirebaseIntegration.currentUserID else {
                try await repository.clearLocalSnapshot()
                apply(.empty)
                WidgetCenter.shared.reloadAllTimelines()
                return
            }

            try await FirebaseIntegration.reauthenticateForAccountDeletion(password: password)
            try await repository.deleteAccountData(userID: userID)
            try await FirebaseIntegration.deleteCurrentAuthenticatedAccount()
            try await repository.clearLocalSnapshot()
            apply(.empty)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureTodayPlan() async throws {
        guard let profile else { return }
        guard shouldGenerateTodayPlan else { return }

        isPreparingTodayPlan = true
        defer { isPreparingTodayPlan = false }

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
        reconcilePendingMissionDifficulty()
        try await save()
    }

    private var shouldGenerateTodayPlan: Bool {
        guard let mission = todayMission, let devotional = todayDevotional else {
            return true
        }

        let canRefreshExistingPlan = FirebaseIntegration.currentUserID != nil && mission.status == .pending
        return canRefreshExistingPlan && Self.needsNLTRefresh(devotional)
    }

    private func refreshCurrentSession(forceSave: Bool = false) async throws {
        focusState = await focusService.refreshAuthorizationStatus()
        notificationState = await notificationScheduler.authorizationState()
        let didAutoFailExpiredMissions = applyExpiredMissionFailures()
        if didAutoFailExpiredMissions {
            await focusService.stopFocus()
            await MissionLiveActivityService.end()
            focusState = await focusService.refreshAuthorizationStatus()
            await notificationScheduler.cancelIncompleteMissionReminder()
            await notificationScheduler.scheduleRecoveryPrompt()
        }
        try await ensureTodayPlan()
        await restoreActiveMissionTimerIfNeeded()
        if didAutoFailExpiredMissions {
            recordProgressSnapshot()
        }
        if reconcileStreaksWithMissionHistory() ||
            reconcilePendingMissionDifficulty() ||
            reconcileAdaptiveChallenges() ||
            didAutoFailExpiredMissions ||
            forceSave {
            try await save()
        }
        await refreshNotificationSchedule()
    }

    private func restoreActiveMissionTimerIfNeeded() async {
        let monitorEndHandoff = ActiveFocusMissionTimerStore.consumeMonitorEndHandoff()

        guard let mission = missions.first(where: { $0.status == .active }) else {
            await focusService.stopFocus()
            await MissionLiveActivityService.end()
            focusState = await focusService.refreshAuthorizationStatus()
            await notificationScheduler.cancelMissionTimerEnded()
            return
        }

        if monitorEndHandoff?.missionID == mission.id {
            await focusService.stopFocus(preservingTimer: true)
            await MissionLiveActivityService.end(missionID: mission.id)
            focusState = await focusService.refreshAuthorizationStatus()
            await notificationScheduler.cancelMissionTimerEnded()
            return
        }

        guard let endsAt = ActiveFocusMissionTimerStore.endDate(for: mission.id) else {
            await focusService.stopFocus()
            await MissionLiveActivityService.end(missionID: mission.id)
            focusState = await focusService.refreshAuthorizationStatus()
            await notificationScheduler.cancelMissionTimerEnded()
            return
        }

        if endsAt > Date() {
            focusState = await focusService.startFocus(for: mission, endsAt: endsAt)
            await MissionLiveActivityService.start(for: mission, endsAt: endsAt, focusState: focusState)
            await notificationScheduler.scheduleMissionTimerEnded(for: mission, at: endsAt)
        } else {
            await focusService.stopFocus(preservingTimer: true)
            await MissionLiveActivityService.end(missionID: mission.id)
            focusState = await focusService.refreshAuthorizationStatus()
            await notificationScheduler.cancelMissionTimerEnded()
        }
    }

    private func refreshNotificationSchedule() async {
        guard let profile else { return }
        await notificationScheduler.scheduleDailyReminder(
            hour: profile.notificationHour,
            minute: profile.notificationMinute
        )

        guard let mission = todayMission,
              mission.status == .pending || mission.status == .active,
              let reminderDate = incompleteReminderDate(for: profile) else {
            await notificationScheduler.cancelIncompleteMissionReminder()
            return
        }

        await notificationScheduler.scheduleIncompleteMissionReminder(at: reminderDate)
    }

    private func incompleteReminderDate(for profile: UserProfile) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        guard let dailyReminderDate = calendar.date(
            bySettingHour: profile.notificationHour,
            minute: profile.notificationMinute,
            second: 0,
            of: now
        ) else {
            return nil
        }

        let eveningReminder = calendar.date(bySettingHour: 20, minute: 30, second: 0, of: now) ?? now
        let latestReminder = calendar.date(bySettingHour: 21, minute: 30, second: 0, of: now) ?? eveningReminder
        let target = min(max(dailyReminderDate.addingTimeInterval(6 * 60 * 60), eveningReminder), latestReminder)
        return target > now ? target : nil
    }

    private func beginMissionMutation(_ missionID: String) -> Bool {
        guard !missionMutationsInFlight.contains(missionID) else { return false }
        missionMutationsInFlight.insert(missionID)
        return true
    }

    private func endMissionMutation(_ missionID: String) {
        missionMutationsInFlight.remove(missionID)
    }

    private func updateMission(_ id: String, mutation: (inout Mission) -> Void) {
        guard let index = missions.firstIndex(where: { $0.id == id }) else { return }
        mutation(&missions[index])
    }

    private func advanceChallenges(for mission: Mission) {
        guard !challenges.isEmpty else { return }
        for index in challenges.indices where challenges[index].category == mission.category {
            let target = max(challenges[index].targetCompletions, 1)
            challenges[index].completedCount = min(challenges[index].completedCount + 1, target)
            challenges[index].daysRemaining = max(challenges[index].daysRemaining - 1, 1)
        }
    }

    @discardableResult
    private func reconcilePendingMissionDifficulty() -> Bool {
        guard let profile else { return false }
        let targetDifficulty = OVRScoring.targetMissionDifficulty(
            for: profile,
            completionRate: completionRate,
            recentFailureCount: recentFailureCount
        )
        let minimumDuration = OVRScoring.minimumMissionMinutes(for: targetDifficulty, ageGroup: profile.ageGroup)
        let pressureLine = OVRScoring.missionPressureLine(for: targetDifficulty)
        var didMutate = false

        for index in missions.indices where missions[index].status == .pending {
            if missions[index].difficulty != targetDifficulty {
                missions[index].difficulty = targetDifficulty
                didMutate = true
            }

            if missions[index].durationMinutes < minimumDuration {
                missions[index].durationMinutes = minimumDuration
                didMutate = true
            }

            let originalCount = missions[index].extraChallenges.count
            missions[index].extraChallenges.removeAll { challenge in
                challenge.hasPrefix("Level ") && challenge.contains(":")
            }
            if missions[index].extraChallenges.count != originalCount {
                didMutate = true
            }

            if !missions[index].extraChallenges.contains(where: { $0 == pressureLine }) {
                missions[index].extraChallenges.insert(pressureLine, at: 0)
                didMutate = true
            }
        }

        return didMutate
    }

    @discardableResult
    private func reconcileAdaptiveChallenges() -> Bool {
        guard let profile else { return false }
        let targetDifficulty = OVRScoring.targetMissionDifficulty(
            for: profile,
            completionRate: completionRate,
            recentFailureCount: recentFailureCount
        )
        var didMutate = false

        if challenges.isEmpty {
            challenges = Self.defaultAdaptiveChallenges(for: profile, difficulty: targetDifficulty)
            return true
        }

        for index in challenges.indices {
            if challenges[index].isComplete {
                challenges[index] = Self.nextAdaptiveChallenge(
                    for: profile,
                    category: challenges[index].category,
                    difficulty: min(5, max(targetDifficulty, challenges[index].difficulty + 1)),
                    salt: index
                )
                didMutate = true
                continue
            }

            let requiredCompletions = OVRScoring.requiredChallengeCompletions(for: targetDifficulty)
            let requiredDays = OVRScoring.challengeWindowDays(for: targetDifficulty)

            if challenges[index].difficulty != targetDifficulty ||
                challenges[index].targetCompletions != requiredCompletions ||
                challenges[index].daysRemaining < requiredDays {
                challenges[index].difficulty = targetDifficulty
                challenges[index].targetCompletions = requiredCompletions
                challenges[index].completedCount = min(challenges[index].completedCount, requiredCompletions)
                challenges[index].daysRemaining = max(challenges[index].daysRemaining, requiredDays)
                let path = GrowthPathPersonalization.resolve(for: profile)
                if challenges[index].category == path.category {
                    challenges[index].detail = "\(path.planSummary) Complete \(challenges[index].targetCompletions) level \(targetDifficulty) missions without skipping reflection."
                } else {
                    challenges[index].detail = Self.challengeDetail(
                        title: challenges[index].title,
                        category: challenges[index].category,
                        difficulty: targetDifficulty,
                        targetCompletions: challenges[index].targetCompletions
                    )
                }
                didMutate = true
            }
        }

        let pathCategory = GrowthPathPersonalization.resolve(for: profile).category
        if !challenges.contains(where: { $0.category == pathCategory }) {
            challenges.append(
                Self.nextAdaptiveChallenge(
                    for: profile,
                    category: pathCategory,
                    difficulty: targetDifficulty,
                    salt: challenges.count
                )
            )
            didMutate = true
        }

        return didMutate
    }

    @discardableResult
    private func applyExpiredMissionFailures() -> Bool {
        guard var profile else { return false }

        let today = Date().startOfDay
        var expiredMissionIDs: [String] = []

        for index in missions.indices {
            guard missions[index].status == .pending || missions[index].status == .active else { continue }
            guard missions[index].date.startOfDay < today else { continue }
            missions[index].status = .failed
            expiredMissionIDs.append(missions[index].id)
        }

        guard !expiredMissionIDs.isEmpty else { return false }

        let totalPenalty = expiredMissionIDs.reduce(0) { total, missionID in
            let difficulty = missions.first(where: { $0.id == missionID })?.difficulty ?? 1
            return total + OVRScoring.failurePenalty(currentOVR: profile.ovrScore, missionDifficulty: difficulty)
        }
        profile.ovrScore = max(0, profile.ovrScore - totalPenalty)
        profile.currentStreak = 0
        self.profile = profile
        syncLeaderboardProfile(profile)

        for missionID in expiredMissionIDs where !journalEntries.contains(where: { $0.missionID == missionID && $0.failureReason != nil }) {
            journalEntries.insert(
                ReflectionEntry(
                    id: UUID().uuidString,
                    date: Date(),
                    missionID: missionID,
                    hardestPart: "The mission expired before it was completed.",
                    lessonLearned: "I need to respond before the day closes.",
                    effortRating: 1,
                    improvementPlan: "Take the next recovery step and keep the next mission smaller.",
                    mood: .low,
                    failureReason: "The mission expired before it was completed."
                ),
                at: 0
            )
        }

        return true
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
                failedMissions: failedMissionCount
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

    private func restoreSnapshot(_ snapshot: AppStateSnapshot) {
        profile = snapshot.profile
        missions = snapshot.missions
        devotionals = snapshot.devotionals
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
    }

    @discardableResult
    private func apply(_ snapshot: AppStateSnapshot) -> Bool {
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
        var didMutate = false
        if let profile {
            didMutate = removeLaunchDemoData(currentUserID: profile.id) || didMutate
            didMutate = reconcileStreaksWithMissionHistory() || didMutate
            didMutate = reconcilePendingMissionDifficulty() || didMutate
            didMutate = reconcileAdaptiveChallenges() || didMutate
            if let profile = self.profile {
                syncLeaderboardProfile(profile)
            }
        }
        return didMutate
    }

    private func applyGlobalLeaderboard(_ entries: [LeaderboardEntry]) {
        var rankedEntries = entries.sortedForGlobalRank
        if let profile {
            let currentEntry = LeaderboardEntry(
                id: profile.id,
                name: profile.displayName,
                ovrScore: profile.ovrScore,
                streak: profile.currentStreak
            )
            if let index = rankedEntries.firstIndex(where: { $0.id == profile.id }) {
                rankedEntries[index] = currentEntry
            } else {
                rankedEntries.append(currentEntry)
            }
        }

        leaderboard = Array(rankedEntries.sortedForGlobalRank.prefix(100))
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
                if $0.streak == $1.streak {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.streak > $1.streak
            }
            return $0.ovrScore > $1.ovrScore
        }
    }

    private func removeLaunchDemoData(currentUserID: String) -> Bool {
        let startingPostCount = posts.count
        let startingPartnerCount = partners.count
        let startingGroupCount = groups.count
        let startingLeaderboardCount = leaderboard.count
        posts.removeAll { $0.authorID.hasPrefix("seed-") }
        groups.removeAll { group in
            Self.isLegacySeedGroup(group, currentUserID: currentUserID)
        }
        partners.removeAll { partner in
            (partner.name == "Jordan" && partner.lastInteraction == "Checked in today") ||
                (partner.name == "Sam" && partner.lastInteraction == "Shared encouragement yesterday")
        }
        leaderboard.removeAll { entry in
            entry.id != currentUserID && Self.demoLeaderboardNames.contains(entry.name)
        }
        return posts.count != startingPostCount ||
            partners.count != startingPartnerCount ||
            groups.count != startingGroupCount ||
            leaderboard.count != startingLeaderboardCount
    }

    private static func enrichDevotionalIfNeeded(_ devotional: Devotional) -> Devotional {
        var updated = devotional
        if (updated.verseText?.isEmpty ?? true) && !updated.bibleVerse.localizedCaseInsensitiveContains("(NLT)") {
            updated.verseText = verseText(reference: updated.bibleVerse, struggle: updated.struggle)
        }
        if updated.explanation.count < 320 {
            updated.explanation = longerExplanation(for: updated.struggle)
        }
        return updated
    }

    private static func needsNLTRefresh(_ devotional: Devotional) -> Bool {
        !devotional.bibleVerse.localizedCaseInsensitiveContains("(NLT)")
    }

    private static func verseText(reference: String, struggle: Struggle) -> String {
        switch normalizedVerseReference(reference) {
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

    private static func normalizedVerseReference(_ reference: String) -> String {
        reference
            .replacingOccurrences(of: #" \((NLT|KJV)\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func defaultAdaptiveChallenges(for profile: UserProfile, difficulty: Int) -> [GrowthChallenge] {
        let pathCategory = GrowthPathPersonalization.resolve(for: profile).category
        let struggleCategory = category(for: profile.mainStruggle)
        var categories = [pathCategory]
        if struggleCategory != pathCategory {
            categories.append(struggleCategory)
        }
        if !categories.contains(.discipline) {
            categories.append(.discipline)
        }

        return categories.prefix(2).enumerated().map { offset, category in
            nextAdaptiveChallenge(
                for: profile,
                category: category,
                difficulty: max(1, difficulty - offset),
                salt: offset
            )
        }
    }

    private static func nextAdaptiveChallenge(
        for profile: UserProfile,
        category: MissionCategory,
        difficulty: Int,
        salt: Int
    ) -> GrowthChallenge {
        let clampedDifficulty = min(max(difficulty, 1), 5)
        let targetCompletions = OVRScoring.requiredChallengeCompletions(for: clampedDifficulty)
        let path = GrowthPathPersonalization.resolve(for: profile)
        let title = category == path.category
            ? challengeTitle(action: path.challengeTitle, difficulty: clampedDifficulty)
            : challengeTitle(category: category, difficulty: clampedDifficulty, salt: salt)
        let detail = category == path.category
            ? "\(path.planSummary) Complete \(targetCompletions) level \(clampedDifficulty) missions without skipping reflection."
            : challengeDetail(
                title: title,
                category: category,
                difficulty: clampedDifficulty,
                targetCompletions: targetCompletions
            )
        return GrowthChallenge(
            id: "adaptive-\(category.id.lowercased().replacingOccurrences(of: " ", with: "-"))-\(clampedDifficulty)-\(UUID().uuidString.prefix(6))",
            title: title,
            detail: detail,
            category: category,
            daysRemaining: OVRScoring.challengeWindowDays(for: clampedDifficulty),
            difficulty: clampedDifficulty,
            targetCompletions: targetCompletions,
            completedCount: 0
        )
    }

    private static func challengeTitle(category: MissionCategory, difficulty: Int, salt: Int) -> String {
        let tier = switch difficulty {
        case 1: "Foundation"
        case 2: "Pressure"
        case 3: "Endurance"
        case 4: "Conviction"
        default: "Mastery"
        }

        let action = switch category {
        case .focus: ["Focus Block", "Deep Work", "Distraction Fast"][salt % 3]
        case .faith: ["Prayer Rhythm", "Scripture Before Scroll", "Obedience Practice"][salt % 3]
        case .discipline: ["Hard Thing First", "No-Zero Chain", "Finish Line"][salt % 3]
        case .selfControl: ["Guardrail", "Trigger Reset", "Clean Start"][salt % 3]
        case .social: ["Courage Check", "Encouragement Chain", "Truth Under Pressure"][salt % 3]
        }

        return "\(tier) \(action)"
    }

    private static func challengeTitle(action: String, difficulty: Int) -> String {
        let tier = switch difficulty {
        case 1: "Foundation"
        case 2: "Pressure"
        case 3: "Endurance"
        case 4: "Conviction"
        default: "Mastery"
        }
        return "\(tier) \(action)"
    }

    private static func challengeDetail(
        title: String,
        category: MissionCategory,
        difficulty: Int,
        targetCompletions: Int
    ) -> String {
        let pressure = switch difficulty {
        case 1: "Keep it simple and prove you can show up."
        case 2: "Add a little resistance and protect the window."
        case 3: "Raise the standard without overcorrecting."
        case 4: "Stay consistent when it costs attention and comfort."
        default: "Protect excellence with humility and accountability."
        }
        return "Complete \(targetCompletions) \(category.rawValue.lowercased()) missions at level \(difficulty). \(pressure)"
    }

    private static func category(for struggle: Struggle) -> MissionCategory {
        switch struggle {
        case .focus:
            .focus
        case .discipline, .consistency:
            .discipline
        case .purity:
            .selfControl
        case .prayer, .scripture:
            .faith
        case .socialPressure:
            .social
        }
    }

    private static func seedLeaderboard(profile: UserProfile) -> [LeaderboardEntry] {
        [LeaderboardEntry(id: profile.id, name: profile.displayName, ovrScore: profile.ovrScore, streak: profile.currentStreak)]
    }

    private static let demoLeaderboardNames = Set(["Naomi", "Elijah", "Maya", "Micah", "Ari", "Jordan", "Sam"])

    private static func isLegacySeedGroup(_ group: ClimbGroup, currentUserID: String) -> Bool {
        guard group.id.hasPrefix("group-\(currentUserID)-") else { return false }
        if ["Daily Discipline", "Focus Block", "Prayer Rhythm"].contains(group.name) {
            return true
        }
        return group.name.hasSuffix(" Path") && group.activeChallenge == "One Honest Win"
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
