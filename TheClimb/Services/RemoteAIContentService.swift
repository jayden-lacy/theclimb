import FirebaseAppCheck
import FirebaseAuth
import Foundation

/// Calls a secure AI proxy, such as a Firebase Cloud Function, and falls back to
/// the local generator if the backend is not configured. Do not ship OpenAI API
/// keys in an iOS client bundle.
final class RemoteAIContentService: MissionGenerationService {
    private let proxyURL: URL?
    private let fallback: MissionGenerationService
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(proxyURL: URL? = RemoteAIContentService.defaultProxyURL, fallback: MissionGenerationService = TemplateMissionGenerationService()) {
        self.proxyURL = proxyURL
        self.fallback = fallback
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func dailyPlan(for profile: UserProfile, history: [ReflectionEntry]) async throws -> DailyPlan {
        guard let proxyURL else {
            return try await fallback.dailyPlan(for: profile, history: history)
        }

        do {
            var request = URLRequest(url: proxyURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let idToken = try await Auth.auth().currentUser?.idTokenResult() {
                request.setValue(idToken, forHTTPHeaderField: "X-Firebase-Auth")
            }
            if let appCheckToken = try? await AppCheck.appCheck().token(forcingRefresh: false) {
                request.setValue(appCheckToken.token, forHTTPHeaderField: "X-Firebase-AppCheck")
            }
            request.httpBody = try encoder.encode(
                AIDailyPlanRequest(
                    profile: profile,
                    recentHistory: Array(history.prefix(12)),
                    generatedAt: Date()
                )
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw AIContentError.badResponse
            }

            let decodedResponse = try decoder.decode(AIDailyPlanResponse.self, from: data)
            guard decodedResponse.isUsable else {
                throw AIContentError.invalidPayload
            }

            return decodedResponse.dailyPlan(for: profile)
        } catch {
            return try await fallback.dailyPlan(for: profile, history: history)
        }
    }

    private static var defaultProxyURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "AIProxyURL") as? String,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(string: rawValue)
    }
}

private enum AIContentError: Error {
    case badResponse
    case invalidPayload
}

private extension User {
    func idTokenResult() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: AIContentError.badResponse)
                }
            }
        }
    }
}

private struct AIDailyPlanRequest: Encodable {
    let profile: UserProfile
    let recentHistory: [ReflectionEntry]
    let generatedAt: Date
}

private struct AIDailyPlanResponse: Decodable {
    let devotional: AIDevotional
    let mission: AIMission
    let habits: [AIHabit]
    let challenges: [AIChallenge]

    var isUsable: Bool {
        devotional.isUsable &&
            mission.isUsable &&
            habits.prefix(4).allSatisfy(\.isUsable) &&
            challenges.prefix(4).allSatisfy(\.isUsable)
    }

    func dailyPlan(for profile: UserProfile) -> DailyPlan {
        let devotionalID = UUID().uuidString
        let category = MissionCategory(rawValue: mission.category) ?? fallbackCategory(for: profile.mainStruggle)

        return DailyPlan(
            devotional: Devotional(
                id: devotionalID,
                date: Date().startOfDay,
                title: devotional.title,
                bibleVerse: devotional.bibleVerse,
                verseText: devotional.verseText,
                explanation: devotional.explanation,
                reflectionQuestion: devotional.reflectionQuestion,
                practicalAction: devotional.practicalAction,
                struggle: profile.mainStruggle
            ),
            mission: Mission(
                id: UUID().uuidString,
                date: Date().startOfDay,
                title: mission.title,
                summary: mission.summary,
                category: category,
                durationMinutes: min(max(mission.durationMinutes, 5), 120),
                difficulty: min(max(mission.difficulty, 1), 5),
                status: .pending,
                fallbackTitle: mission.fallbackTitle,
                fallbackSummary: mission.fallbackSummary,
                extraChallenges: mission.extraChallenges,
                devotionalID: devotionalID,
                appBlockingEnabled: profile.appBlockingEnabled
            ),
            habits: habits.map {
                GrowthHabit(
                    id: $0.id.isEmpty ? UUID().uuidString : $0.id,
                    title: $0.title,
                    cadence: $0.cadence,
                    isEnabled: $0.isEnabled
                )
            },
            challenges: challenges.map {
                GrowthChallenge(
                    id: $0.id.isEmpty ? UUID().uuidString : $0.id,
                    title: $0.title,
                    detail: $0.detail,
                    category: MissionCategory(rawValue: $0.category) ?? category,
                    daysRemaining: max(1, $0.daysRemaining)
                )
            }
        )
    }

    private func fallbackCategory(for struggle: Struggle) -> MissionCategory {
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
}

private struct AIDevotional: Decodable {
    let title: String
    let bibleVerse: String
    let verseText: String
    let explanation: String
    let reflectionQuestion: String
    let practicalAction: String

    var isUsable: Bool {
        [
            title,
            bibleVerse,
            verseText,
            explanation,
            reflectionQuestion,
            practicalAction
        ].allSatisfy { !$0.trimmedForValidation.isEmpty } && explanation.count >= 120
    }
}

private struct AIMission: Decodable {
    let title: String
    let summary: String
    let category: String
    let durationMinutes: Int
    let difficulty: Int
    let fallbackTitle: String
    let fallbackSummary: String
    let extraChallenges: [String]

    var isUsable: Bool {
        [
            title,
            summary,
            category,
            fallbackTitle,
            fallbackSummary
        ].allSatisfy { !$0.trimmedForValidation.isEmpty } &&
            durationMinutes >= 5 &&
            difficulty >= 1 &&
            !extraChallenges.contains { $0.trimmedForValidation.isEmpty }
    }
}

private struct AIHabit: Decodable {
    let id: String
    let title: String
    let cadence: String
    let isEnabled: Bool

    var isUsable: Bool {
        !title.trimmedForValidation.isEmpty && !cadence.trimmedForValidation.isEmpty
    }
}

private struct AIChallenge: Decodable {
    let id: String
    let title: String
    let detail: String
    let category: String
    let daysRemaining: Int

    var isUsable: Bool {
        [
            title,
            detail,
            category
        ].allSatisfy { !$0.trimmedForValidation.isEmpty } && daysRemaining >= 1
    }
}

private extension String {
    var trimmedForValidation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
