import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import GoogleSignIn
import Security
import UIKit

struct FirebaseSignedInUser: Equatable {
    var id: String
    var displayName: String
    var email: String
}

enum FirebaseIntegration {
    @MainActor private static var appleSignInCoordinator: AppleSignInCoordinator?

    static let requiredCollections = [
        "users",
        "missions",
        "devotionals",
        "journalEntries",
        "progress",
        "groups",
        "posts",
        "reports",
        "leaderboards"
    ]

    static func repository() -> AppRepository {
        FirebaseAppRepository()
    }

    static var currentUserID: String? {
        Auth.auth().currentUser?.uid
    }

    @MainActor
    static func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    @MainActor
    static func deleteCurrentAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        let providerIDs = Set(user.providerData.map(\.providerID))

        if providerIDs.contains("google.com") {
            try await disconnectGoogleIfNeeded()
        }

        if providerIDs.contains("apple.com") {
            try await revokeAppleToken()
        }

        try await user.deleteAccountResult()
        GIDSignIn.sharedInstance.signOut()
    }

    @MainActor
    static func signInWithApple() async throws -> FirebaseSignedInUser {
        #if targetEnvironment(simulator)
        if !ProcessInfo.processInfo.arguments.contains("-UseRealAppleSignIn") {
            return try await signInWithAppleSimulatorAccount()
        }
        #endif

        return try await signInWithAppleAuthorization()
    }

    @MainActor
    private static func signInWithAppleAuthorization() async throws -> FirebaseSignedInUser {
        guard let presentingViewController = UIApplication.shared.climbTopViewController,
              let presentationAnchor = presentingViewController.view.window ?? UIApplication.shared.climbKeyWindow else {
            throw FirebaseIntegrationError.presentationUnavailable
        }

        let rawNonce = randomNonceString()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)

        let appleCredential = try await appleCredential(
            for: request,
            presentationAnchor: presentationAnchor
        )

        guard let identityToken = appleCredential.identityToken,
              let identityTokenString = String(data: identityToken, encoding: .utf8) else {
            throw FirebaseIntegrationError.appleTokenMissing
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: identityTokenString,
            rawNonce: rawNonce,
            fullName: appleCredential.fullName
        )
        let firebaseResult = try await Auth.auth().signInResult(with: credential)
        let appleDisplayName = displayName(from: appleCredential.fullName)
        let displayName = appleDisplayName ?? firebaseResult.user.displayName ?? "Climber"

        if firebaseResult.user.displayName?.isEmpty ?? true {
            try? await firebaseResult.user.updateDisplayName(displayName)
        }

        return FirebaseSignedInUser(
            id: firebaseResult.user.uid,
            displayName: displayName,
            email: appleCredential.email ?? firebaseResult.user.email ?? ""
        )
    }

    private static func signInWithAppleSimulatorAccount() async throws -> FirebaseSignedInUser {
        let email = "apple.simulator@theclimb.local"
        let displayName = "Apple Simulator"
        let userID = try await createOrSignInUser(
            email: email,
            password: "AppleSimulator123!",
            displayName: displayName
        )

        return FirebaseSignedInUser(
            id: userID,
            displayName: displayName,
            email: email
        )
    }

    @MainActor
    private static func disconnectGoogleIfNeeded() async throws {
        guard GIDSignIn.sharedInstance.currentUser != nil else { return }
        try await GIDSignIn.sharedInstance.disconnectResult()
    }

    @MainActor
    private static func revokeAppleToken() async throws {
        guard let presentingViewController = UIApplication.shared.climbTopViewController,
              let presentationAnchor = presentingViewController.view.window ?? UIApplication.shared.climbKeyWindow else {
            throw FirebaseIntegrationError.presentationUnavailable
        }

        let request = ASAuthorizationAppleIDProvider().createRequest()
        let appleCredential = try await appleCredential(
            for: request,
            presentationAnchor: presentationAnchor
        )

        guard let authorizationCode = appleCredential.authorizationCode,
              let authorizationCodeString = String(data: authorizationCode, encoding: .utf8) else {
            throw FirebaseIntegrationError.appleAuthorizationCodeMissing
        }

        try await Auth.auth().revokeTokenResult(withAuthorizationCode: authorizationCodeString)
    }

    @MainActor
    static func signInWithGoogle() async throws -> FirebaseSignedInUser {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw FirebaseIntegrationError.googleClientIDMissing
        }

        guard let presentingViewController = UIApplication.shared.climbTopViewController else {
            throw FirebaseIntegrationError.presentationUnavailable
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let googleResult = try await GIDSignIn.sharedInstance.signInResult(
            withPresenting: presentingViewController
        )

        guard let idToken = googleResult.user.idToken?.tokenString else {
            throw FirebaseIntegrationError.googleTokenMissing
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleResult.user.accessToken.tokenString
        )
        let firebaseResult = try await Auth.auth().signInResult(with: credential)
        let displayName = googleResult.user.profile?.name ?? firebaseResult.user.displayName ?? "Climber"
        try? await firebaseResult.user.updateDisplayName(displayName)

        return FirebaseSignedInUser(
            id: firebaseResult.user.uid,
            displayName: displayName,
            email: googleResult.user.profile?.email ?? firebaseResult.user.email ?? ""
        )
    }

    @discardableResult
    static func createOrSignInUser(
        email: String,
        password: String,
        displayName: String
    ) async throws -> String {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), password.count >= 6 else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        do {
            let result = try await Auth.auth().createUserResult(email: normalizedEmail, password: password)
            try await result.user.updateDisplayName(displayName)
            return result.user.uid
        } catch {
            guard isEmailAlreadyInUse(error) else {
                throw mappedAuthError(error)
            }

            let result = try await Auth.auth().signInResult(email: normalizedEmail, password: password)
            try? await result.user.updateDisplayName(displayName)
            return result.user.uid
        }
    }

    private static func isEmailAlreadyInUse(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == AuthErrors.domain &&
            nsError.code == AuthErrorCode.emailAlreadyInUse.rawValue
    }

    fileprivate static func mappedAuthError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == AuthErrors.domain,
              let authCode = AuthErrorCode(rawValue: nsError.code) else {
            return error
        }

        switch authCode {
        case .operationNotAllowed, .appNotAuthorized, .invalidAPIKey, .internalError:
            return FirebaseIntegrationError.authenticationNotConfigured
        case .invalidEmail, .missingEmail, .weakPassword:
            return FirebaseIntegrationError.invalidAccountInfo
        case .requiresRecentLogin:
            return FirebaseIntegrationError.accountDeletionRequiresRecentSignIn
        default:
            return error
        }
    }

    @MainActor
    private static func appleCredential(
        for request: ASAuthorizationAppleIDRequest,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> ASAuthorizationAppleIDCredential {
        defer { appleSignInCoordinator = nil }

        return try await withCheckedThrowingContinuation { continuation in
            let coordinator = AppleSignInCoordinator(
                presentationAnchor: presentationAnchor,
                continuation: continuation
            )
            appleSignInCoordinator = coordinator

            coordinator.perform(request)
        }
    }

    private static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }

        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)

        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var randomBytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)

        guard result == errSecSuccess else {
            fatalError("Unable to generate a secure random nonce.")
        }

        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}

enum FirebaseIntegrationError: LocalizedError {
    case invalidAccountInfo
    case authenticationNotConfigured
    case accountDeletionRequiresRecentSignIn
    case appleAuthorizationCodeMissing
    case appleTokenMissing
    case googleClientIDMissing
    case googleTokenMissing
    case presentationUnavailable
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidAccountInfo:
            "Enter a valid email and a password with at least 6 characters."
        case .authenticationNotConfigured:
            "Firebase Authentication is not enabled for this project yet. Enable Email/Password sign-in in Firebase Console, then try again."
        case .accountDeletionRequiresRecentSignIn:
            "For security, sign in again and then delete your account."
        case .appleAuthorizationCodeMissing:
            "Apple did not return an authorization code. Try deleting the account again."
        case .appleTokenMissing:
            "Apple did not return an identity token. Try signing in again."
        case .googleClientIDMissing:
            "Google Sign-In is missing a client ID. Replace GoogleService-Info.plist with the Google sign-in enabled config."
        case .googleTokenMissing:
            "Google did not return an ID token. Try signing in again."
        case .presentationUnavailable:
            "Sign-in could not find a screen to present from."
        case .encodingFailed:
            "Unable to prepare your Firebase data."
        case .decodingFailed:
            "Unable to read your Firebase data."
        }
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let presentationAnchor: ASPresentationAnchor
    private let continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>
    private var authorizationController: ASAuthorizationController?
    private var didResume = false

    init(
        presentationAnchor: ASPresentationAnchor,
        continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>
    ) {
        self.presentationAnchor = presentationAnchor
        self.continuation = continuation
    }

    func perform(_ request: ASAuthorizationAppleIDRequest) {
        let controller = ASAuthorizationController(authorizationRequests: [request])
        authorizationController = controller
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationAnchor
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            resume(throwing: FirebaseIntegrationError.appleTokenMissing)
            return
        }

        resume(returning: credential)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain &&
            nsError.code == ASAuthorizationError.Code.canceled.rawValue {
            resume(throwing: CancellationError())
            return
        }

        resume(throwing: error)
    }

    private func resume(returning credential: ASAuthorizationAppleIDCredential) {
        guard !didResume else { return }
        didResume = true
        authorizationController = nil
        continuation.resume(returning: credential)
    }

    private func resume(throwing error: Error) {
        guard !didResume else { return }
        didResume = true
        authorizationController = nil
        continuation.resume(throwing: error)
    }
}

final class FirebaseAppRepository: AppRepository {
    private let firestore: Firestore
    private let fallback: LocalAppRepository
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        firestore: Firestore = Firestore.firestore(),
        fallback: LocalAppRepository = LocalAppRepository()
    ) {
        self.firestore = firestore
        self.fallback = fallback
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSnapshot() async throws -> AppStateSnapshot {
        guard let userID = Auth.auth().currentUser?.uid else {
            return try await fallback.loadSnapshot()
        }

        let localSnapshot = try await fallback.loadSnapshot()
        do {
            let document = try await withTimeout(seconds: 4) {
                try await self.snapshotDocument(for: userID).getDocumentResult()
            }
            guard let payload = document.data()?["payload"] as? String,
                  let data = Data(base64Encoded: payload) else {
                if localSnapshot != .empty {
                    try? await saveSnapshot(localSnapshot)
                }
                return localSnapshot
            }

            let snapshot = try decoder.decode(AppStateSnapshot.self, from: data)
            try? await fallback.saveSnapshot(snapshot)
            return snapshot
        } catch {
            if localSnapshot != .empty {
                return localSnapshot
            }
            return .empty
        }
    }

    func saveSnapshot(_ snapshot: AppStateSnapshot) async throws {
        try await fallback.saveSnapshot(snapshot)

        guard let userID = Auth.auth().currentUser?.uid else { return }

        try? await withTimeout(seconds: 5) {
            try await self.saveRemoteSnapshot(snapshot, userID: userID)
        }
    }

    func clearLocalSnapshot() async throws {
        try await fallback.clearLocalSnapshot()
    }

    func deleteAccountData(userID: String) async throws {
        try await fallback.clearLocalSnapshot()

        let collections = [
            "missions",
            "devotionals",
            "journalEntries",
            "progress",
            "groups",
            "posts",
            "reports",
            "leaderboards"
        ]

        for collection in collections {
            try await deleteDocuments(in: collection, userID: userID)
        }

        let userDocument = firestore.collection("users").document(userID)
        let stateSnapshot = try await userDocument.collection("state").getDocumentsResult()
        try await deleteDocuments(stateSnapshot.documents.map { $0.reference })
        try await userDocument.deleteResult()
    }

    func deleteUserDocument(collection: String, documentID: String, userID: String) async throws {
        guard Auth.auth().currentUser?.uid == userID else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        try await firestore.collection(collection).document(documentID).deleteResult()
    }

    private func saveRemoteSnapshot(_ snapshot: AppStateSnapshot, userID: String) async throws {
        let data = try encoder.encode(snapshot)
        let payload = data.base64EncodedString()
        try await snapshotDocument(for: userID).setDataResult([
            "payload": payload,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        if let profile = snapshot.profile {
            try await writeUserDocument(profile, userID: userID)
        }

        try await writeEncodedCollection(snapshot.missions, collection: "missions", userID: userID)
        try await writeEncodedCollection(snapshot.devotionals, collection: "devotionals", userID: userID)
        try await writeEncodedCollection(snapshot.journalEntries, collection: "journalEntries", userID: userID)
        try await writeEncodedCollection(snapshot.progress, collection: "progress", userID: userID)
        try await writeEncodedCollection(snapshot.groups, collection: "groups", userID: userID)
        try await writeEncodedCollection(snapshot.posts, collection: "posts", userID: userID)
        try await writeEncodedCollection(snapshot.moderationReports, collection: "reports", userID: userID)
        if let ownLeaderboardEntry = snapshot.leaderboard.first(where: { $0.id == userID }) {
            try await writeEncodedCollection([ownLeaderboardEntry], collection: "leaderboards", userID: userID)
        }
    }

    private func snapshotDocument(for userID: String) -> DocumentReference {
        firestore
            .collection("users")
            .document(userID)
            .collection("state")
            .document("current")
    }

    private func writeUserDocument(_ profile: UserProfile, userID: String) async throws {
        var data = try encodedDictionary(from: profile)
        data["email"] = Auth.auth().currentUser?.email
        data["userID"] = userID
        data["updatedAt"] = FieldValue.serverTimestamp()
        try await firestore.collection("users").document(userID).setDataResult(data, merge: true)
    }

    private func writeEncodedCollection<T: Encodable & Identifiable>(
        _ values: [T],
        collection: String,
        userID: String
    ) async throws where T.ID == String {
        for value in values {
            var data = try encodedDictionary(from: value)
            data["userID"] = userID
            data["updatedAt"] = FieldValue.serverTimestamp()
            try await firestore.collection(collection).document(value.id).setDataResult(data, merge: true)
        }
    }

    private func encodedDictionary<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseIntegrationError.encodingFailed
        }
        return dictionary
    }

    private func deleteDocuments(in collection: String, userID: String) async throws {
        let snapshot = try await firestore
            .collection(collection)
            .whereField("userID", isEqualTo: userID)
            .getDocumentsResult()
        try await deleteDocuments(snapshot.documents.map { $0.reference })
    }

    private func deleteDocuments(_ references: [DocumentReference]) async throws {
        var batch = firestore.batch()
        var operationCount = 0

        for reference in references {
            batch.deleteDocument(reference)
            operationCount += 1

            if operationCount == 450 {
                try await batch.commitResult()
                batch = firestore.batch()
                operationCount = 0
            }
        }

        if operationCount > 0 {
            try await batch.commitResult()
        }
    }
}

private extension Auth {
    func revokeTokenResult(withAuthorizationCode authorizationCode: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            revokeToken(withAuthorizationCode: authorizationCode) { error in
                if let error {
                    continuation.resume(throwing: FirebaseIntegration.mappedAuthError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func createUserResult(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            createUser(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: FirebaseIntegrationError.invalidAccountInfo)
                }
            }
        }
    }

    func signInResult(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            signIn(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: FirebaseIntegrationError.invalidAccountInfo)
                }
            }
        }
    }

    func signInResult(with credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: FirebaseIntegrationError.invalidAccountInfo)
                }
            }
        }
    }
}

private extension GIDSignIn {
    @MainActor
    func signInResult(withPresenting presentingViewController: UIViewController) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            signIn(withPresenting: presentingViewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: FirebaseIntegrationError.googleTokenMissing)
                }
            }
        }
    }

    @MainActor
    func disconnectResult() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            disconnect { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private extension User {
    func deleteAccountResult() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delete { error in
                if let error {
                    continuation.resume(throwing: FirebaseIntegration.mappedAuthError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func updateDisplayName(_ displayName: String) async throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let changeRequest = createProfileChangeRequest()
            changeRequest.displayName = trimmedName
            changeRequest.commitChanges { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private extension UIApplication {
    var climbKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    var climbTopViewController: UIViewController? {
        climbKeyWindow?
            .rootViewController?
            .climbTopViewController
    }
}

private extension UIViewController {
    var climbTopViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.climbTopViewController
        }

        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.climbTopViewController ?? navigationController
        }

        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.climbTopViewController ?? tabBarController
        }

        return self
    }
}

private extension DocumentReference {
    func getDocumentResult() async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DocumentSnapshot, Error>) in
            getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirebaseIntegrationError.decodingFailed)
                }
            }
        }
    }

    func setDataResult(_ documentData: [String: Any], merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setData(documentData, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func deleteResult() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private extension Query {
    func getDocumentsResult() async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QuerySnapshot, Error>) in
            getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: FirebaseIntegrationError.decodingFailed)
                }
            }
        }
    }
}

private extension WriteBatch {
    func commitResult() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            commit { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private func withTimeout<T>(
    seconds: UInt64,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw FirebaseIntegrationError.decodingFailed
        }

        guard let result = try await group.next() else {
            throw FirebaseIntegrationError.decodingFailed
        }
        group.cancelAll()
        return result
    }
}
