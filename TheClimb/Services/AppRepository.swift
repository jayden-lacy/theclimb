import Foundation

struct TrustedMissionResult: Codable, Equatable {
    var profile: UserProfile
    var mission: Mission
    var journalEntry: ReflectionEntry?
    var progressSnapshot: ProgressSnapshot?
    var leaderboardEntry: LeaderboardEntry
    var appliedDelta: Int
}

protocol AppRepository {
    func loadSnapshot() async throws -> AppStateSnapshot
    func loadGlobalLeaderboard(limit: Int) async throws -> [LeaderboardEntry]
    func completeMission(
        missionID: String,
        hardestPart: String,
        lessonLearned: String,
        effortRating: Int,
        improvementPlan: String,
        mood: MoodRating
    ) async throws -> TrustedMissionResult
    func failMission(missionID: String, reason: String) async throws -> TrustedMissionResult
    func completeRecoveryMission(missionID: String) async throws -> TrustedMissionResult
    func loadRecentEncouragementPosts(limit: Int) async throws -> [EncouragementPost]
    func createEncouragementPost(_ post: EncouragementPost) async throws -> EncouragementPost
    func addAmen(to postID: String) async throws
    func reportEncouragementPost(_ report: ModerationReport) async throws
    func deleteEncouragementPost(postID: String, authorID: String) async throws
    func loadCommunityGroups(limit: Int) async throws -> [ClimbGroup]
    func loadCommunityGroup(id: String) async throws -> ClimbGroup?
    func createCommunityGroup(_ group: ClimbGroup) async throws -> ClimbGroup
    func joinCommunityGroup(_ groupID: String, displayName: String) async throws
    func leaveCommunityGroup(_ groupID: String) async throws
    func updateCommunityGroupDetails(groupID: String, name: String, subtitle: String, challenge: String) async throws
    func setCommunityGroupAdmin(groupID: String, memberID: String, isAdmin: Bool) async throws
    func removeCommunityGroupMember(groupID: String, memberID: String) async throws
    func deleteCommunityGroup(_ groupID: String) async throws
    func loadAccountabilityPartners(for profile: UserProfile) async throws -> [AccountabilityPartner]
    func createAccountabilityPartnerInvite(for profile: UserProfile) async throws -> String
    func acceptAccountabilityPartnerInvite(code: String, profile: UserProfile) async throws
    func updateAccountabilityPartnerActivity(_ partner: AccountabilityPartner, action: AccountabilityPartnerAction, message: String?) async throws
    func saveSnapshot(_ snapshot: AppStateSnapshot) async throws
    func clearLocalSnapshot() async throws
    func deleteAccountData(userID: String) async throws
    func deleteUserDocument(collection: String, documentID: String, userID: String) async throws
}

enum RepositoryError: LocalizedError {
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Unable to save app data."
        case .decodingFailed:
            "Unable to read saved app data."
        }
    }
}
