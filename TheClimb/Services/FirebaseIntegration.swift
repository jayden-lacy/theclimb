import AuthenticationServices
import CryptoKit
import FirebaseAppCheck
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
    var isNewUser = false
}

private struct AccountDeletionCleanupRequest: Encodable {
    let userID: String
}

private struct EmptyCloudFunctionRequest: Encodable {}

private struct EmptyCloudFunctionResponse: Decodable {}

private struct CloudFunctionErrorResponse: Decodable {
    let error: String?
}

private struct LeaderboardSyncResponse: Decodable {
    let entry: LeaderboardEntry
}

private struct CompleteMissionRequest: Encodable {
    let missionID: String
    let hardestPart: String
    let lessonLearned: String
    let effortRating: Int
    let improvementPlan: String
    let mood: String
}

private struct FailMissionRequest: Encodable {
    let missionID: String
    let reason: String
}

private struct RecoveryMissionRequest: Encodable {
    let missionID: String
}

private struct CommunityPostResponse: Decodable {
    let post: EncouragementPost
}

private struct CommunityGroupResponse: Decodable {
    let group: ClimbGroup
}

private struct CreateCommunityPostRequest: Encodable {
    let id: String
    let body: String
}

private struct CommunityPostIDRequest: Encodable {
    let postID: String
}

private struct ReportCommunityPostRequest: Encodable {
    let postID: String
    let reason: String
}

private struct CreateCommunityGroupRequest: Encodable {
    let id: String
    let name: String
    let subtitle: String
    let activeChallenge: String
}

private struct CommunityGroupIDRequest: Encodable {
    let groupID: String
}

private struct JoinCommunityGroupRequest: Encodable {
    let groupID: String
    let displayName: String
}

private struct UpdateCommunityGroupRequest: Encodable {
    let groupID: String
    let name: String
    let subtitle: String
    let activeChallenge: String
}

private struct SetCommunityGroupAdminRequest: Encodable {
    let groupID: String
    let memberID: String
    let isAdmin: Bool
}

private struct RemoveCommunityGroupMemberRequest: Encodable {
    let groupID: String
    let memberID: String
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
        "partnerLinks",
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

    static func currentSignedInUser(matchingEmail email: String) -> FirebaseSignedInUser? {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let user = Auth.auth().currentUser,
              user.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedEmail else {
            return nil
        }

        return FirebaseSignedInUser(
            id: user.uid,
            displayName: user.displayName ?? "Climber",
            email: user.email ?? normalizedEmail,
            isNewUser: false
        )
    }

    static func currentUserHasSavedProfile() async throws -> Bool {
        guard let userID = Auth.auth().currentUser?.uid else { return false }

        do {
            let document = try await withTimeout(seconds: 4) {
                try await Firestore.firestore()
                    .collection("users")
                    .document(userID)
                    .collection("state")
                    .document("current")
                    .getDocumentResult()
            }
            guard document.exists,
                  let payload = document.data()?["payload"] as? String else {
                return false
            }
            return !payload.isEmpty
        } catch {
            throw FirebaseIntegrationError.syncFailed
        }
    }

    @MainActor
    static var requiresPasswordForAccountDeletion: Bool {
        let providerIDs = currentProviderIDs
        return providerIDs.contains("password") &&
            !providerIDs.contains("google.com") &&
            !providerIDs.contains("apple.com")
    }

    @MainActor
    private static var currentProviderIDs: Set<String> {
        Set(Auth.auth().currentUser?.providerData.map(\.providerID) ?? [])
    }

    @MainActor
    static func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    @MainActor
    static func reauthenticateForAccountDeletion(password: String? = nil) async throws {
        guard let user = Auth.auth().currentUser else { return }
        let providerIDs = Set(user.providerData.map(\.providerID))

        if providerIDs.contains("google.com") {
            try await reauthenticateGoogleUser(user)
            return
        }

        if providerIDs.contains("apple.com") {
            try await reauthenticateAppleUserAndRevokeToken(user)
            return
        }

        if providerIDs.contains("password") {
            try await reauthenticatePasswordUser(user, password: password)
        }
    }

    @MainActor
    static func deleteCurrentAuthenticatedAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.deleteAccountResult()
        try? await disconnectGoogleIfNeeded()
        GIDSignIn.sharedInstance.signOut()
    }

    @MainActor
    static func deleteCurrentAccount(password: String? = nil) async throws {
        try await reauthenticateForAccountDeletion(password: password)
        try await deleteCurrentAuthenticatedAccount()
    }

    @MainActor
    static func signInWithApple() async throws -> FirebaseSignedInUser {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment[
            "THE_CLIMB_SIMULATOR_APPLE_EMAIL"
        ] != nil {
            return try await signInWithAppleSimulatorCredentials()
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

        let rawNonce = try randomNonceString()
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
            email: appleCredential.email ?? firebaseResult.user.email ?? "",
            isNewUser: firebaseResult.additionalUserInfo?.isNewUser ?? false
        )
    }

    private static func signInWithAppleSimulatorCredentials() async throws -> FirebaseSignedInUser {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["THE_CLIMB_SIMULATOR_APPLE_EMAIL"],
              let password = environment["THE_CLIMB_SIMULATOR_APPLE_PASSWORD"],
              email.contains("@"),
              password.count >= 6 else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }
        let displayName = environment[
            "THE_CLIMB_SIMULATOR_APPLE_DISPLAY_NAME"
        ] ?? "Apple Simulator"
        let user: FirebaseSignedInUser
        do {
            user = try await createUser(
                email: email,
                password: password,
                displayName: displayName
            )
        } catch FirebaseIntegrationError.accountAlreadyExists {
            user = try await signInExistingUser(
                email: email,
                password: password
            )
        }

        return FirebaseSignedInUser(
            id: user.id,
            displayName: displayName,
            email: email,
            isNewUser: user.isNewUser
        )
    }

    @MainActor
    private static func disconnectGoogleIfNeeded() async throws {
        guard GIDSignIn.sharedInstance.currentUser != nil else { return }
        try await GIDSignIn.sharedInstance.disconnectResult()
    }

    @MainActor
    private static func reauthenticatePasswordUser(_ user: User, password: String?) async throws {
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let email = user.email, !trimmedPassword.isEmpty else {
            throw FirebaseIntegrationError.accountDeletionRequiresRecentSignIn
        }

        let credential = EmailAuthProvider.credential(withEmail: email, password: trimmedPassword)
        try await user.reauthenticateResult(with: credential)
    }

    @MainActor
    private static func reauthenticateGoogleUser(_ user: User) async throws {
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
        try await user.reauthenticateResult(with: credential)
    }

    @MainActor
    private static func reauthenticateAppleUserAndRevokeToken(_ user: User) async throws {
        guard let presentingViewController = UIApplication.shared.climbTopViewController,
              let presentationAnchor = presentingViewController.view.window ?? UIApplication.shared.climbKeyWindow else {
            throw FirebaseIntegrationError.presentationUnavailable
        }

        let rawNonce = try randomNonceString()
        let request = ASAuthorizationAppleIDProvider().createRequest()
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
            fullName: nil
        )
        try await user.reauthenticateResult(with: credential)

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
            email: googleResult.user.profile?.email ?? firebaseResult.user.email ?? "",
            isNewUser: firebaseResult.additionalUserInfo?.isNewUser ?? false
        )
    }

    @discardableResult
    static func createUser(
        email: String,
        password: String,
        displayName: String
    ) async throws -> FirebaseSignedInUser {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), password.count >= 6 else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        do {
            let result = try await Auth.auth().createUserResult(email: normalizedEmail, password: password)
            try await result.user.updateDisplayName(displayName)
            return FirebaseSignedInUser(
                id: result.user.uid,
                displayName: displayName.isEmpty ? "Climber" : displayName,
                email: result.user.email ?? normalizedEmail,
                isNewUser: true
            )
        } catch {
            guard isEmailAlreadyInUse(error) else {
                throw mappedAuthError(error)
            }
            throw FirebaseIntegrationError.accountAlreadyExists
        }
    }

    @discardableResult
    static func signInExistingUser(email: String, password: String) async throws -> FirebaseSignedInUser {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), password.count >= 6 else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        do {
            let result = try await Auth.auth().signInResult(email: normalizedEmail, password: password)
            return FirebaseSignedInUser(
                id: result.user.uid,
                displayName: result.user.displayName ?? "Climber",
                email: result.user.email ?? normalizedEmail
            )
        } catch {
            throw mappedAuthError(error)
        }
    }

    private static func isEmailAlreadyInUse(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == AuthErrors.domain &&
            nsError.code == AuthErrorCode.emailAlreadyInUse.rawValue
    }

    static func mappedAuthError(_ error: Error) -> Error {
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
        case .wrongPassword, .userNotFound, .invalidCredential:
            return FirebaseIntegrationError.invalidLoginCredentials
        case .requiresRecentLogin:
            return FirebaseIntegrationError.accountDeletionRequiresRecentSignIn
        case .keychainError:
            return FirebaseIntegrationError.secureCredentialStorageUnavailable
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

    private static func randomNonceString(length: Int = 32) throws -> String {
        guard length > 0 else {
            throw FirebaseIntegrationError.secureRandomGenerationFailed
        }

        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var randomBytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)

        guard result == errSecSuccess else {
            throw FirebaseIntegrationError.secureRandomGenerationFailed
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
    case invalidLoginCredentials
    case savedProfileMissing
    case accountDeletionRequiresRecentSignIn
    case accountAlreadyExists
    case syncFailed
    case appleAuthorizationCodeMissing
    case appleTokenMissing
    case googleClientIDMissing
    case googleTokenMissing
    case presentationUnavailable
    case secureRandomGenerationFailed
    case secureCredentialStorageUnavailable
    case encodingFailed
    case decodingFailed
    case remoteMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidAccountInfo:
            "Enter a valid email and a password with at least 6 characters."
        case .authenticationNotConfigured:
            "Firebase Authentication is not enabled for this project yet. Enable Email/Password sign-in in Firebase Console, then try again."
        case .invalidLoginCredentials:
            "The email or password is incorrect."
        case .savedProfileMissing:
            "This account does not have a saved Climb profile yet. Create a new profile to continue."
        case .accountDeletionRequiresRecentSignIn:
            "For security, sign in again and then delete your account."
        case .accountAlreadyExists:
            "An account already exists for this email. Log in to load your saved climb."
        case .syncFailed:
            "Your changes could not sync. Check your connection and try again."
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
        case .secureRandomGenerationFailed:
            "A secure sign-in request could not be created. Try again."
        case .secureCredentialStorageUnavailable:
            "Secure sign-in storage is unavailable. Restart your device and try again."
        case .encodingFailed:
            "Unable to prepare your Firebase data."
        case .decodingFailed:
            "Unable to read your Firebase data."
        case .remoteMessage(let message):
            message
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

private struct RemoteCommunityGroupState {
    var id: String
    var name: String
    var subtitle: String
    var activeChallenge: String
    var ownerID: String
    var creatorID: String
    var adminIDs: [String]
    var memberIDs: [String]
    var memberNames: [String: String]
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
        if localSnapshot.profile?.id == userID {
            return localSnapshot
        }

        do {
            let document = try await withTimeout(seconds: 4) {
                try await self.snapshotDocument(for: userID).getDocumentResult()
            }
            guard let payload = document.data()?["payload"] as? String,
                  let data = Data(base64Encoded: payload) else {
                if localSnapshot.profile?.id == userID {
                    return localSnapshot
                }
                return .empty
            }

            let snapshot = try decoder.decode(AppStateSnapshot.self, from: data)
            try? await fallback.saveSnapshot(snapshot)
            return snapshot
        } catch {
            if localSnapshot.profile?.id == userID {
                return localSnapshot
            }
            return .empty
        }
    }

    func loadGlobalLeaderboard(limit: Int) async throws -> [LeaderboardEntry] {
        guard Auth.auth().currentUser?.uid != nil else {
            return try await fallback.loadGlobalLeaderboard(limit: limit)
        }

        do {
            let snapshot = try await withTimeout(seconds: 4) {
                try await self.firestore
                    .collection("leaderboards")
                    .order(by: "ovrScore", descending: true)
                    .limit(to: max(1, limit))
                    .getDocumentsResult()
            }

            let entries = snapshot.documents.compactMap { document in
                Self.leaderboardEntry(from: document.data(), fallbackID: document.documentID)
            }
            return Array(entries.sortedForGlobalRank.prefix(limit))
        } catch {
            return try await fallback.loadGlobalLeaderboard(limit: limit)
        }
    }

    func completeMission(
        missionID: String,
        hardestPart: String,
        lessonLearned: String,
        effortRating: Int,
        improvementPlan: String,
        mood: MoodRating
    ) async throws -> TrustedMissionResult {
        guard Auth.auth().currentUser?.uid != nil else {
            return try await fallback.completeMission(
                missionID: missionID,
                hardestPart: hardestPart,
                lessonLearned: lessonLearned,
                effortRating: effortRating,
                improvementPlan: improvementPlan,
                mood: mood
            )
        }

        let result: TrustedMissionResult = try await callCloudFunction(
            named: "completeMission",
            body: CompleteMissionRequest(
                missionID: missionID,
                hardestPart: hardestPart,
                lessonLearned: lessonLearned,
                effortRating: effortRating,
                improvementPlan: improvementPlan,
                mood: mood.rawValue
            )
        )
        try? await mergeTrustedMissionResult(result)
        return result
    }

    func failMission(missionID: String, reason: String) async throws -> TrustedMissionResult {
        guard Auth.auth().currentUser?.uid != nil else {
            return try await fallback.failMission(missionID: missionID, reason: reason)
        }

        let result: TrustedMissionResult = try await callCloudFunction(
            named: "failMission",
            body: FailMissionRequest(missionID: missionID, reason: reason)
        )
        try? await mergeTrustedMissionResult(result)
        return result
    }

    func completeRecoveryMission(missionID: String) async throws -> TrustedMissionResult {
        guard Auth.auth().currentUser?.uid != nil else {
            return try await fallback.completeRecoveryMission(missionID: missionID)
        }

        let result: TrustedMissionResult = try await callCloudFunction(
            named: "completeRecoveryMission",
            body: RecoveryMissionRequest(missionID: missionID)
        )
        try? await mergeTrustedMissionResult(result)
        return result
    }

    func loadRecentEncouragementPosts(limit: Int) async throws -> [EncouragementPost] {
        guard Auth.auth().currentUser?.uid != nil else {
            return try await fallback.loadRecentEncouragementPosts(limit: limit)
        }

        do {
            let snapshot = try await withTimeout(seconds: 4) {
                try await self.firestore
                    .collection("posts")
                    .order(by: "createdAt", descending: true)
                    .limit(to: max(1, limit))
                    .getDocumentsResult()
            }

            return snapshot.documents.compactMap { document in
                Self.encouragementPost(from: document.data(), fallbackID: document.documentID)
            }
        } catch {
            return try await fallback.loadRecentEncouragementPosts(limit: limit)
        }
    }

    func createEncouragementPost(_ post: EncouragementPost) async throws -> EncouragementPost {
        guard let userID = Auth.auth().currentUser?.uid else {
            return try await fallback.createEncouragementPost(post)
        }

        let response: CommunityPostResponse = try await callCloudFunction(
            named: "createCommunityPost",
            body: CreateCommunityPostRequest(id: post.id, body: post.body)
        )
        let createdPost = response.post
        guard createdPost.authorID == userID else {
            throw FirebaseIntegrationError.syncFailed
        }
        _ = try? await fallback.createEncouragementPost(createdPost)
        return createdPost
    }

    func addAmen(to postID: String) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            try await fallback.addAmen(to: postID)
            return
        }

        let _: EmptyCloudFunctionResponse = try await callCloudFunction(
            named: "addCommunityPostAmen",
            body: CommunityPostIDRequest(postID: postID)
        )
        try? await fallback.addAmen(to: postID)
    }

    func reportEncouragementPost(_ report: ModerationReport) async throws {
        guard let userID = Auth.auth().currentUser?.uid else {
            try await fallback.reportEncouragementPost(report)
            return
        }

        guard report.reportedByUserID == userID else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        let _: EmptyCloudFunctionResponse = try await callCloudFunction(
            named: "reportCommunityPost",
            body: ReportCommunityPostRequest(postID: report.postID, reason: report.reason)
        )
        try? await fallback.reportEncouragementPost(report)
    }

    func deleteEncouragementPost(postID: String, authorID: String) async throws {
        guard let userID = Auth.auth().currentUser?.uid else {
            try await fallback.deleteEncouragementPost(postID: postID, authorID: authorID)
            return
        }

        guard userID == authorID else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        let _: EmptyCloudFunctionResponse = try await callCloudFunction(
            named: "deleteCommunityPost",
            body: CommunityPostIDRequest(postID: postID)
        )
        try? await fallback.deleteEncouragementPost(postID: postID, authorID: authorID)
    }

    func loadCommunityGroups(limit: Int) async throws -> [ClimbGroup] {
        guard let userID = Auth.auth().currentUser?.uid else {
            return try await fallback.loadCommunityGroups(limit: limit)
        }

        do {
            let snapshot = try await withTimeout(seconds: 4) {
                try await self.firestore
                    .collection("groups")
                    .order(by: "updatedAt", descending: true)
                    .limit(to: max(1, limit))
                    .getDocumentsResult()
            }

            let groups = snapshot.documents.compactMap { document in
                Self.communityGroup(
                    from: document.data(),
                    fallbackID: document.documentID,
                    currentUserID: userID
                )
            }
            return groups
        } catch {
            return try await fallback.loadCommunityGroups(limit: limit)
        }
    }

    func loadCommunityGroup(id: String) async throws -> ClimbGroup? {
        guard let userID = Auth.auth().currentUser?.uid else {
            return try await fallback.loadCommunityGroup(id: id)
        }

        do {
            let document = try await withTimeout(seconds: 4) {
                try await self.firestore.collection("groups").document(id).getDocumentResult()
            }
            guard document.exists else {
                return try await fallback.loadCommunityGroup(id: id)
            }
            return document.data().flatMap {
                Self.communityGroup(from: $0, fallbackID: document.documentID, currentUserID: userID)
            }
        } catch {
            return try await fallback.loadCommunityGroup(id: id)
        }
    }

    func createCommunityGroup(_ group: ClimbGroup) async throws -> ClimbGroup {
        _ = try await fallback.createCommunityGroup(group)

        guard Auth.auth().currentUser?.uid != nil else {
            return group
        }

        let response: CommunityGroupResponse = try await callCloudFunction(
            named: "createCommunityGroup",
            body: CreateCommunityGroupRequest(
                id: group.id,
                name: group.name,
                subtitle: group.subtitle,
                activeChallenge: group.activeChallenge
            )
        )
        return response.group
    }

    func joinCommunityGroup(_ groupID: String, displayName: String) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            try await fallback.joinCommunityGroup(groupID, displayName: displayName)
            return
        }

        let _: CommunityGroupResponse = try await callCloudFunction(
            named: "joinCommunityGroup",
            body: JoinCommunityGroupRequest(groupID: groupID, displayName: displayName)
        )
        try? await fallback.joinCommunityGroup(groupID, displayName: displayName)
    }

    func leaveCommunityGroup(_ groupID: String) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            try await fallback.leaveCommunityGroup(groupID)
            return
        }

        let _: CommunityGroupResponse = try await callCloudFunction(
            named: "leaveCommunityGroup",
            body: CommunityGroupIDRequest(groupID: groupID)
        )
        try? await fallback.leaveCommunityGroup(groupID)
    }

    func updateCommunityGroupDetails(groupID: String, name: String, subtitle: String, challenge: String) async throws {
        try await fallback.updateCommunityGroupDetails(groupID: groupID, name: name, subtitle: subtitle, challenge: challenge)

        guard Auth.auth().currentUser?.uid != nil else { return }

        let _: CommunityGroupResponse = try await callCloudFunction(
            named: "updateCommunityGroup",
            body: UpdateCommunityGroupRequest(
                groupID: groupID,
                name: name,
                subtitle: subtitle,
                activeChallenge: challenge
            )
        )
    }

    func setCommunityGroupAdmin(groupID: String, memberID: String, isAdmin: Bool) async throws {
        try await fallback.setCommunityGroupAdmin(groupID: groupID, memberID: memberID, isAdmin: isAdmin)

        guard Auth.auth().currentUser?.uid != nil else { return }

        let _: CommunityGroupResponse = try await callCloudFunction(
            named: "setCommunityGroupAdmin",
            body: SetCommunityGroupAdminRequest(groupID: groupID, memberID: memberID, isAdmin: isAdmin)
        )
    }

    func removeCommunityGroupMember(groupID: String, memberID: String) async throws {
        try await fallback.removeCommunityGroupMember(groupID: groupID, memberID: memberID)

        guard Auth.auth().currentUser?.uid != nil else { return }

        let _: CommunityGroupResponse = try await callCloudFunction(
            named: "removeCommunityGroupMember",
            body: RemoveCommunityGroupMemberRequest(groupID: groupID, memberID: memberID)
        )
    }

    func deleteCommunityGroup(_ groupID: String) async throws {
        try await fallback.deleteCommunityGroup(groupID)

        guard Auth.auth().currentUser?.uid != nil else { return }

        let _: EmptyCloudFunctionResponse = try await callCloudFunction(
            named: "deleteCommunityGroup",
            body: CommunityGroupIDRequest(groupID: groupID)
        )
    }

    func loadAccountabilityPartners(for profile: UserProfile) async throws -> [AccountabilityPartner] {
        guard let userID = Auth.auth().currentUser?.uid else {
            return try await fallback.loadAccountabilityPartners(for: profile)
        }

        do {
            let ownedSnapshot = try await withTimeout(seconds: 4) {
                try await self.firestore
                    .collection("partnerLinks")
                    .whereField("ownerID", isEqualTo: userID)
                    .getDocumentsResult()
            }
            let acceptedSnapshot = try await withTimeout(seconds: 4) {
                try await self.firestore
                    .collection("partnerLinks")
                    .whereField("acceptedByID", isEqualTo: userID)
                    .getDocumentsResult()
            }

            var partnersByID: [String: AccountabilityPartner] = [:]
            for document in ownedSnapshot.documents + acceptedSnapshot.documents {
                guard let partner = Self.accountabilityPartner(
                    from: document.data(),
                    fallbackID: document.documentID,
                    currentUserID: userID
                ) else { continue }
                partnersByID[partner.id] = partner
            }

            return partnersByID.values.sorted {
                if $0.isPending != $1.isPending {
                    return !$0.isPending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            return try await fallback.loadAccountabilityPartners(for: profile)
        }
    }

    func createAccountabilityPartnerInvite(for profile: UserProfile) async throws -> String {
        guard let userID = Auth.auth().currentUser?.uid else {
            return try await fallback.createAccountabilityPartnerInvite(for: profile)
        }

        let code = Self.inviteCode()
        let data: [String: Any] = [
            "id": code,
            "ownerID": userID,
            "ownerName": profile.displayName,
            "ownerFocus": profile.mainStruggle.rawValue,
            "acceptedByID": "",
            "acceptedByName": "",
            "acceptedByFocus": "",
            "status": "pending",
            "ownerCheckInCount": 0,
            "acceptedCheckInCount": 0,
            "ownerNudgeCount": 0,
            "acceptedNudgeCount": 0,
            "ownerEncouragementCount": 0,
            "acceptedEncouragementCount": 0,
            "lastInteraction": "Invite created",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "userID": userID
        ]

        try await firestore.collection("partnerLinks").document(code).setDataResult(data, merge: false)
        _ = try? await fallback.createAccountabilityPartnerInvite(for: profile)
        return code
    }

    func acceptAccountabilityPartnerInvite(code: String, profile: UserProfile) async throws {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let userID = Auth.auth().currentUser?.uid else {
            try await fallback.acceptAccountabilityPartnerInvite(code: normalizedCode, profile: profile)
            return
        }

        let reference = firestore.collection("partnerLinks").document(normalizedCode)
        let document = try await reference.getDocumentResult()
        guard document.exists,
              let ownerID = document.data()?["ownerID"] as? String,
              ownerID != userID else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        try await reference.updateDataResult([
            "acceptedByID": userID,
            "acceptedByName": profile.displayName,
            "acceptedByFocus": profile.mainStruggle.rawValue,
            "status": "accepted",
            "lastInteraction": "\(profile.displayName) joined the accountability pair",
            "updatedAt": FieldValue.serverTimestamp()
        ])
        try? await fallback.acceptAccountabilityPartnerInvite(code: normalizedCode, profile: profile)
    }

    func updateAccountabilityPartnerActivity(_ partner: AccountabilityPartner, action: AccountabilityPartnerAction, message: String?) async throws {
        guard let userID = Auth.auth().currentUser?.uid else {
            try await fallback.updateAccountabilityPartnerActivity(partner, action: action, message: message)
            return
        }

        let reference = firestore.collection("partnerLinks").document(partner.id)
        let document = try await reference.getDocumentResult()
        guard let data = document.data(),
              let ownerID = data["ownerID"] as? String else {
            return
        }

        let prefix: String
        if ownerID == userID {
            prefix = "owner"
        } else if data["acceptedByID"] as? String == userID {
            prefix = "accepted"
        } else {
            return
        }

        let displayName = Auth.auth().currentUser?.displayName ?? "Your partner"
        var update: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]

        switch action {
        case .checkIn:
            update["\(prefix)CheckInCount"] = FieldValue.increment(Int64(1))
            update["\(prefix)LastCheckInAt"] = FieldValue.serverTimestamp()
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            update["lastInteraction"] = trimmedMessage.isEmpty ? "\(displayName) checked in" : String(trimmedMessage.prefix(100))
        case .nudge:
            update["\(prefix)NudgeCount"] = FieldValue.increment(Int64(1))
            update["lastInteraction"] = "\(displayName) sent a nudge"
        case .encouragement:
            update["\(prefix)EncouragementCount"] = FieldValue.increment(Int64(1))
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            update["lastInteraction"] = trimmedMessage.isEmpty ? "\(displayName) sent encouragement" : String(trimmedMessage.prefix(80))
        }

        try await reference.updateDataResult(update)
        try? await fallback.updateAccountabilityPartnerActivity(partner, action: action, message: message)
    }

    func saveSnapshot(_ snapshot: AppStateSnapshot) async throws {
        guard let userID = Auth.auth().currentUser?.uid else {
            try await fallback.saveSnapshot(snapshot)
            return
        }

        try await fallback.saveSnapshot(snapshot)

        do {
            try await withTimeout(seconds: 12) {
                try await self.saveRemoteSnapshot(snapshot, userID: userID)
            }
        } catch {
            #if DEBUG
            print("Firebase sync deferred: \(error.localizedDescription)")
            #endif
        }
    }

    func clearLocalSnapshot() async throws {
        try await fallback.clearLocalSnapshot()
    }

    func deleteAccountData(userID: String) async throws {
        try await deleteBackendAccountData(userID: userID)
        try await fallback.clearLocalSnapshot()
        try? await removeUserFromJoinedCommunityGroups(userID: userID)

        let collections = [
            "missions",
            "devotionals",
            "journalEntries",
            "progress",
            "groups",
            "partnerLinks",
            "posts",
            "reports",
            "leaderboards"
        ]

        for collection in collections {
            try? await deleteDocuments(in: collection, userID: userID)
        }
        try? await deletePartnerLinksAcceptedBy(userID: userID)

        try? await deleteKnownUserDocuments(userID: userID)

        let userDocument = firestore.collection("users").document(userID)
        if let stateSnapshot = try? await userDocument.collection("state").getDocumentsResult() {
            try? await deleteDocuments(stateSnapshot.documents.map { $0.reference })
        }
        try? await userDocument.deleteResult()
    }

    private func deleteBackendAccountData(userID: String) async throws {
        guard let cleanupURL = Self.accountDeletionCleanupURL,
              let user = Auth.auth().currentUser,
              user.uid == userID else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        var request = URLRequest(url: cleanupURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try await user.idTokenString(), forHTTPHeaderField: "X-Firebase-Auth")

        if let appCheckToken = try? await AppCheck.appCheck().token(forcingRefresh: false) {
            request.setValue(appCheckToken.token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }

        request.httpBody = try JSONEncoder().encode(AccountDeletionCleanupRequest(userID: userID))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw FirebaseIntegrationError.accountDeletionRequiresRecentSignIn
        }
    }

    private func syncTrustedLeaderboardEntry() async throws {
        let response: LeaderboardSyncResponse = try await callCloudFunction(
            named: "syncLeaderboard",
            body: EmptyCloudFunctionRequest()
        )
        await patchLocalLeaderboard(with: response.entry)
    }

    private func patchLocalLeaderboard(with entry: LeaderboardEntry) async {
        guard var snapshot = try? await fallback.loadSnapshot() else { return }
        snapshot.leaderboard.removeAll { $0.id == entry.id }
        snapshot.leaderboard.insert(entry, at: 0)
        snapshot.leaderboard = Array(snapshot.leaderboard.sortedForGlobalRank.prefix(100))
        try? await fallback.saveSnapshot(snapshot)
    }

    private func mergeTrustedMissionResult(_ result: TrustedMissionResult) async throws {
        var snapshot = try await fallback.loadSnapshot()
        snapshot.profile = result.profile

        if let index = snapshot.missions.firstIndex(where: { $0.id == result.mission.id }) {
            snapshot.missions[index] = result.mission
        } else {
            snapshot.missions.insert(result.mission, at: 0)
        }

        if let journalEntry = result.journalEntry {
            snapshot.journalEntries.removeAll { $0.id == journalEntry.id }
            snapshot.journalEntries.removeAll {
                $0.missionID == journalEntry.missionID &&
                    (($0.failureReason == nil && journalEntry.failureReason == nil) ||
                        ($0.failureReason != nil && journalEntry.failureReason != nil))
            }
            snapshot.journalEntries.insert(journalEntry, at: 0)
        }

        if let progressSnapshot = result.progressSnapshot {
            snapshot.progress.removeAll { $0.id == progressSnapshot.id }
            snapshot.progress.insert(progressSnapshot, at: 0)
            snapshot.progress = Array(snapshot.progress.prefix(30))
        }

        snapshot.leaderboard.removeAll { $0.id == result.leaderboardEntry.id }
        snapshot.leaderboard.insert(result.leaderboardEntry, at: 0)
        snapshot.leaderboard = Array(snapshot.leaderboard.sortedForGlobalRank.prefix(100))
        try await fallback.saveSnapshot(snapshot)
    }

    private func callCloudFunction<RequestBody: Encodable, ResponseBody: Decodable>(
        named functionName: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        guard let url = Self.cloudFunctionURL(named: functionName),
              let user = Auth.auth().currentUser else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try await user.idTokenString(), forHTTPHeaderField: "X-Firebase-Auth")

        if let appCheckToken = try? await AppCheck.appCheck().token(forcingRefresh: false) {
            request.setValue(appCheckToken.token, forHTTPHeaderField: "X-Firebase-AppCheck")
        }

        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirebaseIntegrationError.syncFailed
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if let errorResponse = try? decoder.decode(CloudFunctionErrorResponse.self, from: data),
               let error = errorResponse.error,
               !error.isEmpty {
                throw FirebaseIntegrationError.remoteMessage(error)
            }
            throw FirebaseIntegrationError.syncFailed
        }

        if ResponseBody.self == EmptyCloudFunctionResponse.self {
            return EmptyCloudFunctionResponse() as! ResponseBody
        }

        return try decoder.decode(ResponseBody.self, from: data)
    }

    func deleteUserDocument(collection: String, documentID: String, userID: String) async throws {
        guard Auth.auth().currentUser?.uid == userID else {
            throw FirebaseIntegrationError.invalidAccountInfo
        }

        try await firestore.collection(collection).document(documentID).deleteResult()
    }

    private func saveRemoteSnapshot(_ snapshot: AppStateSnapshot, userID: String) async throws {
        let remoteSnapshot = compactRemoteSnapshot(from: snapshot, userID: userID)
        let data = try encoder.encode(remoteSnapshot)
        let payload = data.base64EncodedString()

        if let profile = remoteSnapshot.profile {
            try await writeUserDocument(profile, userID: userID)
        }

        try await snapshotDocument(for: userID).setDataResult([
            "payload": payload,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        try await writeEncodedCollection(remoteSnapshot.missions, collection: "missions", userID: userID)
        try await writeEncodedCollection(remoteSnapshot.devotionals, collection: "devotionals", userID: userID)
        try await writeEncodedCollection(remoteSnapshot.journalEntries, collection: "journalEntries", userID: userID)
        try await writeEncodedCollection(remoteSnapshot.progress, collection: "progress", userID: userID)
        try? await syncTrustedLeaderboardEntry()
    }

    private func compactRemoteSnapshot(from snapshot: AppStateSnapshot, userID: String) -> AppStateSnapshot {
        AppStateSnapshot(
            profile: snapshot.profile,
            missions: Array(snapshot.missions.prefix(120)),
            devotionals: Array(snapshot.devotionals.prefix(120)),
            journalEntries: Array(snapshot.journalEntries.prefix(240)),
            progress: Array(snapshot.progress.prefix(90)),
            habits: snapshot.habits,
            challenges: snapshot.challenges,
            groups: [],
            posts: [],
            partners: [],
            leaderboard: snapshot.leaderboard.filter { $0.id == userID },
            blockedUserIDs: snapshot.blockedUserIDs,
            moderationReports: [],
            contentFeedback: snapshot.contentFeedback,
            notificationFatigue: snapshot.notificationFatigue,
            monthlyLetters: snapshot.monthlyLetters,
            verseMemory: Array(snapshot.verseMemory.prefix(120)),
            achievementUnlocks: Array(snapshot.achievementUnlocks.prefix(80))
        )
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

    private func updateCommunityGroupMembership(
        groupID: String,
        userID: String,
        displayName: String,
        shouldJoin: Bool
    ) async throws {
        let reference = firestore.collection("groups").document(groupID)
        let document = try await reference.getDocumentResult()
        guard document.exists,
              var state = remoteGroupState(from: document.data() ?? [:], fallbackID: document.documentID) else {
            return
        }

        if shouldJoin {
            guard !state.memberIDs.contains(userID) else { return }
            state.memberIDs.append(userID)
            state.memberNames[userID] = String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        } else {
            guard state.memberIDs.contains(userID), userID != state.ownerID else { return }
            state.memberIDs.removeAll { $0 == userID }
            state.adminIDs.removeAll { $0 == userID }
            state.memberNames.removeValue(forKey: userID)
        }

        try await updateRemoteGroup(reference: reference, state: state)
    }

    private func removeUserFromJoinedCommunityGroups(userID: String) async throws {
        let snapshot = try await firestore
            .collection("groups")
            .whereField("memberIDs", arrayContains: userID)
            .getDocumentsResult()

        for document in snapshot.documents {
            guard var state = remoteGroupState(from: document.data(), fallbackID: document.documentID) else {
                continue
            }
            if state.ownerID == userID {
                continue
            }

            guard state.memberIDs.contains(userID) else { continue }
            state.memberIDs.removeAll { $0 == userID }
            state.adminIDs.removeAll { $0 == userID }
            state.memberNames.removeValue(forKey: userID)
            try await updateRemoteGroup(reference: document.reference, state: state)
        }
    }

    private func remoteGroupState(from data: [String: Any], fallbackID: String) -> RemoteCommunityGroupState? {
        let id = (data["id"] as? String) ?? fallbackID
        let name = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = (data["subtitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeChallenge = (data["activeChallenge"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let name,
              let subtitle,
              let activeChallenge,
              !name.isEmpty,
              !subtitle.isEmpty,
              !activeChallenge.isEmpty else {
            return nil
        }

        let ownerID = ((data["ownerID"] as? String) ?? (data["userID"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var memberIDs = data["memberIDs"] as? [String] ?? []
        var adminIDs = data["adminIDs"] as? [String] ?? []
        var memberNames = Self.stringMap(from: data["memberNames"])

        if ownerID.isEmpty == false {
            if !memberIDs.contains(ownerID) {
                memberIDs.insert(ownerID, at: 0)
            }
            if !adminIDs.contains(ownerID) {
                adminIDs.insert(ownerID, at: 0)
            }
        }

        adminIDs.removeAll { !memberIDs.contains($0) }
        memberIDs = Array(NSOrderedSet(array: memberIDs).compactMap { $0 as? String })
        adminIDs = Array(NSOrderedSet(array: adminIDs).compactMap { $0 as? String })
        for memberID in memberIDs where memberNames[memberID]?.isEmpty ?? true {
            memberNames[memberID] = memberID == ownerID ? "Group Admin" : "Member \(memberID.prefix(6))"
        }

        return RemoteCommunityGroupState(
            id: id,
            name: String(name.prefix(42)),
            subtitle: String(subtitle.prefix(96)),
            activeChallenge: String(activeChallenge.prefix(40)),
            ownerID: ownerID,
            creatorID: (data["userID"] as? String) ?? ownerID,
            adminIDs: adminIDs,
            memberIDs: memberIDs,
            memberNames: memberNames
        )
    }

    private func updateRemoteGroup(reference: DocumentReference, state: RemoteCommunityGroupState) async throws {
        try await reference.updateDataResult([
            "id": state.id,
            "name": state.name,
            "subtitle": state.subtitle,
            "activeChallenge": state.activeChallenge,
            "userID": state.creatorID,
            "ownerID": state.ownerID,
            "adminIDs": state.adminIDs,
            "memberIDs": state.memberIDs,
            "memberNames": state.memberNames,
            "members": state.memberIDs.count,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    private func encodedDictionary<T: Encodable>(from value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseIntegrationError.encodingFailed
        }
        return dictionary
    }

    private static func stringMap(from value: Any?) -> [String: String] {
        guard let rawMap = value as? [String: Any] else {
            return value as? [String: String] ?? [:]
        }
        return rawMap.reduce(into: [String: String]()) { result, item in
            if let stringValue = item.value as? String {
                result[item.key] = stringValue
            }
        }
    }

    private static func communityGroup(
        from data: [String: Any],
        fallbackID: String,
        currentUserID: String
    ) -> ClimbGroup? {
        let id = (data["id"] as? String) ?? fallbackID
        let name = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = (data["subtitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeChallenge = (data["activeChallenge"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var memberIDs = data["memberIDs"] as? [String] ?? []
        let ownerID = ((data["ownerID"] as? String) ?? (data["userID"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var adminIDs = data["adminIDs"] as? [String] ?? []
        var memberNames = stringMap(from: data["memberNames"])

        guard let name,
              let subtitle,
              let activeChallenge,
              !name.isEmpty,
              !subtitle.isEmpty,
              !activeChallenge.isEmpty,
              !isLegacySeedGroup(id: id, name: name, activeChallenge: activeChallenge) else {
            return nil
        }

        let fallbackMemberCount = intValue(from: data["members"]) ?? 0
        if ownerID.isEmpty == false, !memberIDs.contains(ownerID) {
            memberIDs.insert(ownerID, at: 0)
        }
        let memberCount = memberIDs.isEmpty ? fallbackMemberCount : memberIDs.count
        if ownerID.isEmpty == false, !adminIDs.contains(ownerID) {
            adminIDs.append(ownerID)
        }
        adminIDs.removeAll { !memberIDs.contains($0) }
        for memberID in memberIDs where memberNames[memberID]?.isEmpty ?? true {
            memberNames[memberID] = memberID == ownerID ? "Group Admin" : "Member \(memberID.prefix(6))"
        }

        return ClimbGroup(
            id: id,
            name: String(name.prefix(42)),
            subtitle: String(subtitle.prefix(96)),
            members: max(0, memberCount),
            activeChallenge: String(activeChallenge.prefix(40)),
            isJoined: memberIDs.contains(currentUserID),
            ownerID: ownerID,
            adminIDs: adminIDs,
            memberIDs: memberIDs,
            memberNames: memberNames
        )
    }

    private static func isLegacySeedGroup(id: String, name: String, activeChallenge: String) -> Bool {
        guard id.hasPrefix("group-") else { return false }
        if ["Daily Discipline", "Focus Block", "Prayer Rhythm"].contains(name) {
            return true
        }
        return name.hasSuffix(" Path") && activeChallenge == "One Honest Win"
    }

    private static func accountabilityPartner(
        from data: [String: Any],
        fallbackID: String,
        currentUserID: String
    ) -> AccountabilityPartner? {
        let id = ((data["id"] as? String) ?? fallbackID).trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerID = (data["ownerID"] as? String) ?? ""
        let acceptedByID = (data["acceptedByID"] as? String) ?? ""
        guard !id.isEmpty, ownerID == currentUserID || acceptedByID == currentUserID else { return nil }

        let isOwner = ownerID == currentUserID
        let isPending = (data["status"] as? String) != "accepted" || acceptedByID.isEmpty
        let partnerName: String
        let linkedUserID: String?
        let focusValue: String?
        let partnerLastCheckInAt: Date?
        let currentCheckInCount: Int
        let otherCheckInCount: Int
        let currentNudgeCount: Int
        let currentEncouragementCount: Int

        if isOwner {
            partnerName = isPending ? "Waiting for friend" : ((data["acceptedByName"] as? String) ?? "Accountability Partner")
            linkedUserID = acceptedByID.isEmpty ? nil : acceptedByID
            focusValue = data["acceptedByFocus"] as? String
            partnerLastCheckInAt = dateValue(from: data["acceptedLastCheckInAt"])
            currentCheckInCount = intValue(from: data["ownerCheckInCount"]) ?? 0
            otherCheckInCount = intValue(from: data["acceptedCheckInCount"]) ?? 0
            currentNudgeCount = intValue(from: data["ownerNudgeCount"]) ?? 0
            currentEncouragementCount = intValue(from: data["ownerEncouragementCount"]) ?? 0
        } else {
            partnerName = (data["ownerName"] as? String) ?? "Accountability Partner"
            linkedUserID = ownerID
            focusValue = data["ownerFocus"] as? String
            partnerLastCheckInAt = dateValue(from: data["ownerLastCheckInAt"])
            currentCheckInCount = intValue(from: data["acceptedCheckInCount"]) ?? 0
            otherCheckInCount = intValue(from: data["ownerCheckInCount"]) ?? 0
            currentNudgeCount = intValue(from: data["acceptedNudgeCount"]) ?? 0
            currentEncouragementCount = intValue(from: data["acceptedEncouragementCount"]) ?? 0
        }

        let focus = focusValue.flatMap(Struggle.init(rawValue:)) ?? .discipline
        let lastCheckIn = isPending ? "Pending" : relativeDayText(for: partnerLastCheckInAt)
        let sharedStreak = min(currentCheckInCount, otherCheckInCount)
        let weeklyCompletions = min(7, max(currentCheckInCount, otherCheckInCount))
        let lastInteraction = isPending ? "Share invite code \(id)" : ((data["lastInteraction"] as? String) ?? "Ready for today's check-in")

        return AccountabilityPartner(
            id: id,
            name: String(partnerName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)),
            focus: focus,
            lastCheckIn: lastCheckIn,
            checkInCount: currentCheckInCount + otherCheckInCount,
            nudgeCount: currentNudgeCount,
            encouragementCount: currentEncouragementCount,
            lastInteraction: lastInteraction,
            inviteCode: id,
            linkedUserID: linkedUserID,
            isPending: isPending,
            lastCheckInDate: partnerLastCheckInAt,
            sharedStreak: sharedStreak,
            weeklyCompletions: weeklyCompletions
        )
    }

    private static func leaderboardEntry(from data: [String: Any], fallbackID: String) -> LeaderboardEntry? {
        let id = (data["id"] as? String) ?? (data["userID"] as? String) ?? fallbackID
        let name = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ovrScore = intValue(from: data["ovrScore"])
        let streak = intValue(from: data["streak"])

        guard let ovrScore, let streak else { return nil }

        return LeaderboardEntry(
            id: id,
            name: resolvedLeaderboardName(name),
            ovrScore: min(100, max(0, ovrScore)),
            streak: max(0, streak)
        )
    }

    private static func encouragementPost(from data: [String: Any], fallbackID: String) -> EncouragementPost? {
        let id = ((data["id"] as? String) ?? fallbackID).trimmingCharacters(in: .whitespacesAndNewlines)
        let authorID = ((data["authorID"] as? String) ?? (data["userID"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (data["author"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (data["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = dateValue(from: data["createdAt"]) ?? dateValue(from: data["updatedAt"]) ?? Date.distantPast
        let amenCount = intValue(from: data["amenCount"]) ?? 0

        guard !id.isEmpty,
              !authorID.isEmpty,
              let author,
              !author.isEmpty,
              let body,
              !body.isEmpty else {
            return nil
        }

        return EncouragementPost(
            id: id,
            authorID: authorID,
            author: String(author.prefix(40)),
            body: String(body.prefix(280)),
            createdAt: createdAt,
            amenCount: max(0, amenCount)
        )
    }

    private static func resolvedLeaderboardName(_ name: String?) -> String {
        guard let name, !name.isEmpty else {
            return "Climber"
        }
        return String(name.prefix(40))
    }

    private static func intValue(from value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func dateValue(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = value as? Date {
            return date
        }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }

    private static func relativeDayText(for date: Date?) -> String {
        guard let date else { return "Waiting" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let days = calendar.dateComponents([.day], from: date.startOfDay, to: Date().startOfDay).day ?? 0
        return days > 0 ? "\(days)d ago" : "Recently"
    }

    private static func inviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in alphabet.randomElement() })
    }

    private static var accountDeletionCleanupURL: URL? {
        cloudFunctionURL(named: "deleteAccountData")
    }

    private static func cloudFunctionURL(named functionName: String) -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "AIProxyURL") as? String,
              let dailyPlanURL = URL(string: rawValue) else {
            return nil
        }

        return dailyPlanURL.deletingLastPathComponent().appendingPathComponent(functionName)
    }

    private func deleteDocuments(in collection: String, userID: String) async throws {
        let snapshot = try await firestore
            .collection(collection)
            .whereField("userID", isEqualTo: userID)
            .getDocumentsResult()
        try await deleteDocuments(snapshot.documents.map { $0.reference })
    }

    private func deletePartnerLinksAcceptedBy(userID: String) async throws {
        let snapshot = try await firestore
            .collection("partnerLinks")
            .whereField("acceptedByID", isEqualTo: userID)
            .getDocumentsResult()
        try await deleteDocuments(snapshot.documents.map { $0.reference })
    }

    private func deleteKnownUserDocuments(userID: String) async throws {
        let references = [
            firestore.collection("leaderboards").document(userID)
        ]
        try await deleteDocuments(references)
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
    func idTokenString() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: FirebaseIntegration.mappedAuthError(error))
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: FirebaseIntegrationError.invalidAccountInfo)
                }
            }
        }
    }

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

    func reauthenticateResult(with credential: AuthCredential) async throws {
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            reauthenticate(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: FirebaseIntegration.mappedAuthError(error))
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: FirebaseIntegrationError.invalidAccountInfo)
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

    func updateDataResult(_ fields: [AnyHashable: Any]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            updateData(fields) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
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
