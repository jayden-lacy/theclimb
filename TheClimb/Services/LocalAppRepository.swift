import Foundation

final class LocalAppRepository: AppRepository {
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let storageKey = "the-climb.snapshot.v1"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = UserDefaults(suiteName: LocalAppRepository.appGroupID) ?? .standard) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        migrateStandardDefaultsIfNeeded()
    }

    func loadSnapshot() async throws -> AppStateSnapshot {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return .empty
        }

        do {
            return try decoder.decode(AppStateSnapshot.self, from: data)
        } catch {
            throw RepositoryError.decodingFailed
        }
    }

    func loadGlobalLeaderboard(limit: Int) async throws -> [LeaderboardEntry] {
        let snapshot = try await loadSnapshot()
        return Array(snapshot.leaderboard.sortedForGlobalRank.prefix(max(1, limit)))
    }

    func loadRecentEncouragementPosts(limit: Int) async throws -> [EncouragementPost] {
        let snapshot = try await loadSnapshot()
        return Array(snapshot.posts.sorted { $0.createdAt > $1.createdAt }.prefix(max(1, limit)))
    }

    func createEncouragementPost(_ post: EncouragementPost) async throws -> EncouragementPost {
        var snapshot = try await loadSnapshot()
        snapshot.posts.removeAll { $0.id == post.id }
        snapshot.posts.insert(post, at: 0)
        snapshot.posts.sort { $0.createdAt > $1.createdAt }
        try await saveSnapshot(snapshot)
        return post
    }

    func addAmen(to postID: String) async throws {
        var snapshot = try await loadSnapshot()
        guard let index = snapshot.posts.firstIndex(where: { $0.id == postID }) else { return }
        snapshot.posts[index].amenCount += 1
        try await saveSnapshot(snapshot)
    }

    func reportEncouragementPost(_ report: ModerationReport) async throws {
        var snapshot = try await loadSnapshot()
        snapshot.moderationReports.removeAll {
            $0.postID == report.postID && $0.reportedByUserID == report.reportedByUserID
        }
        snapshot.moderationReports.insert(report, at: 0)
        try await saveSnapshot(snapshot)
    }

    func deleteEncouragementPost(postID: String, authorID: String) async throws {
        var snapshot = try await loadSnapshot()
        snapshot.posts.removeAll { $0.id == postID && $0.authorID == authorID }
        snapshot.moderationReports.removeAll { $0.postID == postID }
        try await saveSnapshot(snapshot)
    }

    func loadCommunityGroups(limit: Int) async throws -> [ClimbGroup] {
        let snapshot = try await loadSnapshot()
        return Array(snapshot.groups.prefix(max(1, limit)))
    }

    func createCommunityGroup(_ group: ClimbGroup) async throws -> ClimbGroup {
        var snapshot = try await loadSnapshot()
        snapshot.groups.removeAll { $0.id == group.id }
        snapshot.groups.insert(group, at: 0)
        try await saveSnapshot(snapshot)
        return group
    }

    func joinCommunityGroup(_ groupID: String, displayName: String) async throws {
        var snapshot = try await loadSnapshot()
        guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard !snapshot.groups[index].isJoined else { return }
        let userID = snapshot.profile?.id ?? "local-user"
        let resolvedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Climber" : displayName
        snapshot.groups[index].isJoined = true
        if !snapshot.groups[index].memberIDs.contains(userID) {
            snapshot.groups[index].memberIDs.append(userID)
        }
        snapshot.groups[index].memberNames[userID] = String(resolvedDisplayName.prefix(40))
        snapshot.groups[index].members = snapshot.groups[index].memberIDs.count
        try await saveSnapshot(snapshot)
    }

    func leaveCommunityGroup(_ groupID: String) async throws {
        var snapshot = try await loadSnapshot()
        guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard snapshot.groups[index].isJoined else { return }
        let userID = snapshot.profile?.id ?? "local-user"
        snapshot.groups[index].isJoined = false
        snapshot.groups[index].memberIDs.removeAll { $0 == userID }
        snapshot.groups[index].adminIDs.removeAll { $0 == userID }
        snapshot.groups[index].memberNames.removeValue(forKey: userID)
        snapshot.groups[index].members = snapshot.groups[index].memberIDs.count
        try await saveSnapshot(snapshot)
    }

    func updateCommunityGroupDetails(groupID: String, name: String, subtitle: String, challenge: String) async throws {
        var snapshot = try await loadSnapshot()
        guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
        snapshot.groups[index].name = name
        snapshot.groups[index].subtitle = subtitle
        snapshot.groups[index].activeChallenge = challenge
        try await saveSnapshot(snapshot)
    }

    func setCommunityGroupAdmin(groupID: String, memberID: String, isAdmin: Bool) async throws {
        var snapshot = try await loadSnapshot()
        guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
        if isAdmin {
            if !snapshot.groups[index].adminIDs.contains(memberID) {
                snapshot.groups[index].adminIDs.append(memberID)
            }
        } else {
            snapshot.groups[index].adminIDs.removeAll { $0 == memberID }
            if snapshot.groups[index].ownerID.isEmpty == false,
               !snapshot.groups[index].adminIDs.contains(snapshot.groups[index].ownerID) {
                snapshot.groups[index].adminIDs.append(snapshot.groups[index].ownerID)
            }
        }
        try await saveSnapshot(snapshot)
    }

    func removeCommunityGroupMember(groupID: String, memberID: String) async throws {
        var snapshot = try await loadSnapshot()
        guard let index = snapshot.groups.firstIndex(where: { $0.id == groupID }) else { return }
        snapshot.groups[index].memberIDs.removeAll { $0 == memberID }
        snapshot.groups[index].adminIDs.removeAll { $0 == memberID }
        snapshot.groups[index].memberNames.removeValue(forKey: memberID)
        snapshot.groups[index].members = snapshot.groups[index].memberIDs.count
        if snapshot.groups[index].isJoined, snapshot.profile?.id == memberID {
            snapshot.groups[index].isJoined = false
        }
        try await saveSnapshot(snapshot)
    }

    func deleteCommunityGroup(_ groupID: String) async throws {
        var snapshot = try await loadSnapshot()
        snapshot.groups.removeAll { $0.id == groupID }
        try await saveSnapshot(snapshot)
    }

    func loadAccountabilityPartners(for profile: UserProfile) async throws -> [AccountabilityPartner] {
        let snapshot = try await loadSnapshot()
        return snapshot.partners
    }

    func createAccountabilityPartnerInvite(for profile: UserProfile) async throws -> String {
        let code = Self.inviteCode()
        var snapshot = try await loadSnapshot()
        let partner = AccountabilityPartner(
            id: code,
            name: "Waiting for friend",
            focus: profile.mainStruggle,
            lastCheckIn: "Pending",
            lastInteraction: "Invite code \(code)",
            inviteCode: code,
            isPending: true
        )
        snapshot.partners.removeAll { $0.id == partner.id }
        snapshot.partners.insert(partner, at: 0)
        try await saveSnapshot(snapshot)
        return code
    }

    func acceptAccountabilityPartnerInvite(code: String, profile: UserProfile) async throws {
        var snapshot = try await loadSnapshot()
        let partner = AccountabilityPartner(
            id: code.uppercased(),
            name: "Partner \(code.uppercased())",
            focus: profile.mainStruggle,
            lastCheckIn: "Ready",
            lastInteraction: "Partner connection accepted",
            inviteCode: code.uppercased(),
            isPending: false
        )
        snapshot.partners.removeAll { $0.id == partner.id }
        snapshot.partners.insert(partner, at: 0)
        try await saveSnapshot(snapshot)
    }

    func updateAccountabilityPartnerActivity(_ partner: AccountabilityPartner, action: AccountabilityPartnerAction, message: String?) async throws {
        var snapshot = try await loadSnapshot()
        guard let index = snapshot.partners.firstIndex(where: { $0.id == partner.id }) else { return }
        snapshot.partners[index] = partner
        try await saveSnapshot(snapshot)
    }

    func saveSnapshot(_ snapshot: AppStateSnapshot) async throws {
        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            throw RepositoryError.encodingFailed
        }
    }

    func clearLocalSnapshot() async throws {
        defaults.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    func deleteAccountData(userID: String) async throws {
        try await clearLocalSnapshot()
    }

    func deleteUserDocument(collection: String, documentID: String, userID: String) async throws {}

    private func migrateStandardDefaultsIfNeeded() {
        guard defaults !== UserDefaults.standard else { return }
        guard defaults.data(forKey: Self.storageKey) == nil else { return }
        guard let existingData = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        defaults.set(existingData, forKey: Self.storageKey)
    }

    private static func inviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in alphabet.randomElement() })
    }
}
