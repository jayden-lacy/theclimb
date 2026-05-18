import Foundation

protocol MissionGenerationService {
    func dailyPlan(for profile: UserProfile, history: [ReflectionEntry]) async throws -> DailyPlan
}

struct DailyPlan: Equatable {
    var devotional: Devotional
    var mission: Mission
    var habits: [GrowthHabit]
    var challenges: [GrowthChallenge]
}

final class TemplateMissionGenerationService: MissionGenerationService {
    func dailyPlan(for profile: UserProfile, history: [ReflectionEntry]) async throws -> DailyPlan {
        let date = Date().startOfDay
        let devotionalID = UUID().uuidString
        let category = category(for: profile.mainStruggle)
        let failureCount = history.filter { $0.failureReason != nil }.count
        let consistencyCue = profile.currentStreak >= 3 ? "protect the streak" : "restart with one clear win"

        let devotional = Devotional(
            id: devotionalID,
            date: date,
            title: devotionalTitle(for: profile.mainStruggle),
            bibleVerse: verse(for: profile.mainStruggle),
            verseText: verseText(for: profile.mainStruggle),
            explanation: devotionalExplanation(for: profile.mainStruggle, cue: consistencyCue),
            reflectionQuestion: "Where do you need obedience before motivation today?",
            practicalAction: "Name one distraction, remove it for the mission window, and begin before you feel ready.",
            struggle: profile.mainStruggle
        )

        let mission = Mission(
            id: UUID().uuidString,
            date: date,
            title: missionTitle(for: profile.mainStruggle),
            summary: missionSummary(for: profile.mainStruggle, failureCount: failureCount),
            category: category,
            durationMinutes: duration(for: profile),
            difficulty: min(5, max(1, 2 + profile.currentStreak / 3)),
            status: .pending,
            fallbackTitle: "Recovery Step",
            fallbackSummary: "Complete 8 focused minutes, pray honestly about what got in the way, and write the next right step.",
            extraChallenges: extraChallenges(for: profile.mainStruggle),
            devotionalID: devotionalID,
            appBlockingEnabled: profile.appBlockingEnabled
        )

        return DailyPlan(
            devotional: devotional,
            mission: mission,
            habits: habits(for: profile.mainStruggle),
            challenges: challenges(for: profile.mainStruggle)
        )
    }

    private func category(for struggle: Struggle) -> MissionCategory {
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

    private func duration(for profile: UserProfile) -> Int {
        switch profile.ageGroup {
        case .teen:
            20
        case .college:
            30
        case .youngAdult:
            35
        }
    }

    private func devotionalTitle(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "Single-minded Today"
        case .discipline:
            "Faithful in the Small"
        case .consistency:
            "Show Up Again"
        case .purity:
            "A Clean Heart"
        case .prayer:
            "Return to Prayer"
        case .scripture:
            "Rooted in the Word"
        case .socialPressure:
            "Courage to Stand"
        }
    }

    private func verse(for struggle: Struggle) -> String {
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

    private func verseText(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "\"And whatsoever ye do, do it heartily, as to the Lord, and not unto men.\""
        case .discipline:
            "\"He that is faithful in that which is least is faithful also in much: and he that is unjust in the least is unjust also in much.\""
        case .consistency:
            "\"And let us not be weary in well doing: for in due season we shall reap, if we faint not.\""
        case .purity:
            "\"Create in me a clean heart, O God; and renew a right spirit within me.\""
        case .prayer:
            "\"Pray without ceasing.\""
        case .scripture:
            "\"Thy word is a lamp unto my feet, and a light unto my path.\""
        case .socialPressure:
            "\"And be not conformed to this world: but be ye transformed by the renewing of your mind.\""
        }
    }

    private func devotionalExplanation(for struggle: Struggle, cue: String) -> String {
        switch struggle {
        case .focus:
            "This verse pulls your attention away from approval and back toward worship. Focus is not only a productivity skill; it is a way of refusing to let every notification, mood, or opinion become your master. Today, your work becomes an act of obedience when you do it with a whole heart before God. Your focus for today is to \(cue), give God the first move, and complete the mission with attention."
        case .discipline:
            "Jesus connects small faithfulness with larger responsibility. The task you keep delaying may look ordinary, but it is training your ability to be trusted. Discipline is built when you do the next right thing before it feels rewarding. Your focus for today is to \(cue), choose faithfulness in the small thing, and stop waiting for a perfect mood."
        case .consistency:
            "Weariness is one of the main enemies of growth. Paul does not pretend that doing good always feels exciting; he reminds us that the harvest comes after endurance. Consistency means you keep showing up when the result is not visible yet. Your focus for today is to \(cue), take one obedient step, and trust that repeated faithfulness is never wasted."
        case .purity:
            "David asks God for more than behavior management; he asks for a clean heart and a renewed spirit. Self-control starts deeper than avoiding a trigger. It starts by bringing desire, shame, and weakness into God’s presence instead of hiding them. Your focus for today is to \(cue), remove the first trigger, and choose the action that protects your future self."
        case .prayer:
            "Prayer is not only a scheduled moment; it is a posture of returning to God throughout the day. A short prayer offered honestly is better than a perfect prayer you never begin. Today is about lowering the barrier and building a rhythm of return. Your focus for today is to \(cue), speak plainly with God, and let prayer interrupt the spiral before it grows."
        case .scripture:
            "The Word is described as a lamp, not a floodlight. God often gives enough clarity for the next step before He shows the whole road. Scripture becomes practical when you let one verse confront one decision today. Your focus for today is to \(cue), read slowly, write down one line, and obey the light you have."
        case .socialPressure:
            "Pressure tries to shape you from the outside in, but transformation starts with a renewed mind. You do not have to match every room you enter. Courage grows when your choices are formed by truth before they are tested by people. Your focus for today is to \(cue), decide your response before the pressure hits, and make one visible choice that matches your faith."
        }
    }

    private func missionTitle(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "Deep Work Block"
        case .discipline:
            "Finish the Delayed Task"
        case .consistency:
            "No-Zero Day"
        case .purity:
            "Self-control Reset"
        case .prayer:
            "Prayer Walk"
        case .scripture:
            "Scripture Before Scroll"
        case .socialPressure:
            "Encourage First"
        }
    }

    private func missionSummary(for struggle: Struggle, failureCount: Int) -> String {
        let recovery = failureCount > 0 ? " Keep it concrete and do not overcorrect." : ""
        switch struggle {
        case .focus:
            return "Put your phone away, block distracting apps if available, and complete one focused work block.\(recovery)"
        case .discipline:
            return "Choose one task you have been avoiding and finish the next meaningful step before doing anything easier.\(recovery)"
        case .consistency:
            return "Complete one small promise today, even if the rest of the day is messy.\(recovery)"
        case .purity:
            return "Remove one trigger, pray for a clean heart, and choose an action that protects your future self.\(recovery)"
        case .prayer:
            return "Spend the mission window in prayer, moving from honesty to surrender to one specific request.\(recovery)"
        case .scripture:
            return "Read a short passage slowly, write one line that confronts you, and act on it today.\(recovery)"
        case .socialPressure:
            return "Send encouragement to someone and make one visible choice that matches your values.\(recovery)"
        }
    }

    private func extraChallenges(for struggle: Struggle) -> [String] {
        [
            "Check in with an accountability partner after the mission.",
            "Write a one-sentence lesson before bed.",
            "Repeat the mission tomorrow at the same time."
        ]
    }

    private func habits(for struggle: Struggle) -> [GrowthHabit] {
        [
            GrowthHabit(id: "morning-prayer", title: "Morning prayer", cadence: "Daily", isEnabled: true),
            GrowthHabit(id: "scripture-before-scroll", title: "Scripture before scroll", cadence: "Daily", isEnabled: struggle == .scripture || struggle == .focus),
            GrowthHabit(id: "partner-checkin", title: "Partner check-in", cadence: "3x weekly", isEnabled: true)
        ]
    }

    private func challenges(for struggle: Struggle) -> [GrowthChallenge] {
        [
            GrowthChallenge(
                id: "seven-day-climb",
                title: "7-Day Climb",
                detail: "Complete seven daily missions with a reflection after each one.",
                category: .discipline,
                daysRemaining: 7
            ),
            GrowthChallenge(
                id: "quiet-hour",
                title: "Quiet Hour",
                detail: "Protect one screen-light hour this week for prayer, scripture, and planning.",
                category: category(for: struggle),
                daysRemaining: 5
            )
        ]
    }
}
