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
}
