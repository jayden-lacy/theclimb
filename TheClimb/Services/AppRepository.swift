import Foundation

protocol AppRepository {
    func loadSnapshot() async throws -> AppStateSnapshot
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
