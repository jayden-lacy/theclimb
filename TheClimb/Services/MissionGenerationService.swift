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
        let personalization = GrowthPathPersonalization.resolve(for: profile)
        let category = personalization.category
        let failureCount = history.filter { $0.failureReason != nil }.count
        let consistencyCue = profile.currentStreak >= 3 ? "protect the streak" : "restart with one clear win"
        let missionDifficulty = difficulty(for: profile, history: history)
        let missionDuration = duration(for: profile, difficulty: missionDifficulty)

        let devotional = Devotional(
            id: devotionalID,
            date: date,
            title: devotionalTitle(for: profile, date: date),
            bibleVerse: verse(for: profile.mainStruggle),
            verseText: verseText(for: profile.mainStruggle),
            explanation: devotionalExplanation(for: profile.mainStruggle, cue: consistencyCue, personalization: personalization),
            reflectionQuestion: personalization.reflectionPrompt,
            practicalAction: personalization.practicalAction,
            struggle: profile.mainStruggle
        )

        let mission = Mission(
            id: UUID().uuidString,
            date: date,
            title: missionTitle(for: profile, date: date),
            summary: missionSummary(
                for: profile,
                failureCount: failureCount,
                date: date,
                personalization: personalization,
                difficulty: missionDifficulty
            ),
            category: category,
            durationMinutes: missionDuration,
            difficulty: missionDifficulty,
            status: .pending,
            fallbackTitle: "Recovery Step",
            fallbackSummary: personalization.fallbackSummary,
            extraChallenges: extraChallenges(for: profile, personalization: personalization, difficulty: missionDifficulty),
            devotionalID: devotionalID,
            appBlockingEnabled: profile.appBlockingEnabled
        )

        return DailyPlan(
            devotional: devotional,
            mission: mission,
            habits: habits(for: profile, personalization: personalization),
            challenges: challenges(for: profile, difficulty: missionDifficulty, personalization: personalization)
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

    private func duration(for profile: UserProfile, difficulty: Int) -> Int {
        let personalization = GrowthPathPersonalization.resolve(for: profile)
        let growthMinutes: Int = switch profile.ovrScore {
        case ..<55:
            0
        case 55..<68:
            5
        case 68..<80:
            10
        case 80..<90:
            15
        default:
            25
        }
        let base = switch profile.ageGroup {
        case .teen:
            20 + growthMinutes
        case .college:
            30 + growthMinutes
        case .youngAdult:
            35 + growthMinutes
        }
        let streakAdjustment = profile.streakGoal >= 60 ? 5 : (profile.streakGoal <= 14 ? -5 : 0)
        let categoryAdjustment = switch personalization.category {
        case .faith, .selfControl, .social:
            -5
        case .focus, .discipline:
            0
        }
        return max(
            OVRScoring.minimumMissionMinutes(for: difficulty, ageGroup: profile.ageGroup),
            base + streakAdjustment + categoryAdjustment
        )
    }

    private func difficulty(for profile: UserProfile, history: [ReflectionEntry]) -> Int {
        let recentFailureCount = history.prefix(5).filter { $0.failureReason != nil }.count
        return OVRScoring.targetMissionDifficulty(for: profile, recentFailureCount: recentFailureCount)
    }

    private func devotionalTitle(for profile: UserProfile, date: Date) -> String {
        let struggle = profile.mainStruggle
        return switch struggle {
        case .focus:
            personalizedOption(["Single-minded Today", "Undivided Attention", "The Quiet Work"], profile: profile, date: date, salt: "focus-devotional-title")
        case .discipline:
            personalizedOption(["Faithful in the Small", "The Next Right Thing", "Trusted With Today"], profile: profile, date: date, salt: "discipline-devotional-title")
        case .consistency:
            personalizedOption(["Show Up Again", "Do Not Grow Weary", "Another Faithful Day"], profile: profile, date: date, salt: "consistency-devotional-title")
        case .purity:
            personalizedOption(["A Clean Heart", "Guard the First Step", "Renewed Within"], profile: profile, date: date, salt: "purity-devotional-title")
        case .prayer:
            personalizedOption(["Return to Prayer", "Pray Before the Spiral", "A Habit of Return"], profile: profile, date: date, salt: "prayer-devotional-title")
        case .scripture:
            personalizedOption(["Rooted in the Word", "Lamp for the Next Step", "Read and Obey"], profile: profile, date: date, salt: "scripture-devotional-title")
        case .socialPressure:
            personalizedOption(["Courage to Stand", "Renewed Under Pressure", "Truth Before Approval"], profile: profile, date: date, salt: "social-devotional-title")
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
            "Work with your whole heart as an offering to God, not as performance for people."
        case .discipline:
            "Faithfulness in small things trains the heart for larger responsibility."
        case .consistency:
            "Do not quit the good work; endurance carries the harvest you cannot see yet."
        case .purity:
            "Ask God for a clean heart and a steady spirit, not just better behavior."
        case .prayer:
            "Keep returning to prayer until dependence becomes your rhythm."
        case .scripture:
            "God’s Word gives enough light for the next obedient step."
        case .socialPressure:
            "Do not be shaped by the world’s pattern; let God renew the way you think."
        }
    }

    private func devotionalExplanation(for struggle: Struggle, cue: String, personalization: GrowthPathPersonalization) -> String {
        let goalSentence = "Because your path is centered on \(personalization.primaryGoal.lowercased()), today connects the verse to \(personalization.devotionalFocus)."
        return switch struggle {
        case .focus:
            "This verse pulls your attention away from approval and back toward worship. Focus is not only a productivity skill; it is a way of refusing to let every notification, mood, or opinion become your master. \(goalSentence) Today, your work becomes an act of obedience when you do it with a whole heart before God. Your focus for today is to \(cue), give God the first move, and complete the mission with attention."
        case .discipline:
            "Jesus connects small faithfulness with larger responsibility. The task you keep delaying may look ordinary, but it is training your ability to be trusted. \(goalSentence) Discipline is built when you do the next right thing before it feels rewarding. Your focus for today is to \(cue), choose faithfulness in the small thing, and stop waiting for a perfect mood."
        case .consistency:
            "Weariness is one of the main enemies of growth. Paul does not pretend that doing good always feels exciting; he reminds us that the harvest comes after endurance. \(goalSentence) Consistency means you keep showing up when the result is not visible yet. Your focus for today is to \(cue), take one obedient step, and trust that repeated faithfulness is never wasted."
        case .purity:
            "David asks God for more than behavior management; he asks for a clean heart and a renewed spirit. Self-control starts deeper than avoiding a trigger. \(goalSentence) It starts by bringing desire, shame, and weakness into God’s presence instead of hiding them. Your focus for today is to \(cue), remove the first trigger, and choose the action that protects your future self."
        case .prayer:
            "Prayer is not only a scheduled moment; it is a posture of returning to God throughout the day. A short prayer offered honestly is better than a perfect prayer you never begin. \(goalSentence) Today is about lowering the barrier and building a rhythm of return. Your focus for today is to \(cue), speak plainly with God, and let prayer interrupt the spiral before it grows."
        case .scripture:
            "The Word is described as a lamp, not a floodlight. God often gives enough clarity for the next step before He shows the whole road. \(goalSentence) Scripture becomes practical when you let one verse confront one decision today. Your focus for today is to \(cue), read slowly, write down one line, and obey the light you have."
        case .socialPressure:
            "Pressure tries to shape you from the outside in, but transformation starts with a renewed mind. You do not have to match every room you enter. \(goalSentence) Courage grows when your choices are formed by truth before they are tested by people. Your focus for today is to \(cue), decide your response before the pressure hits, and make one visible choice that matches your faith."
        }
    }

    private func missionTitle(for profile: UserProfile, date: Date) -> String {
        let struggle = profile.mainStruggle
        let personalization = GrowthPathPersonalization.resolve(for: profile)
        let goalTitles = [
            personalization.previewMissionTitle,
            personalization.challengeTitle,
            personalization.habitTitle
        ]
        let struggleTitles = switch struggle {
        case .focus:
            ["Deep Work Block", "Phone-Away Focus", "One Undistracted Task"]
        case .discipline:
            ["Finish the Delayed Task", "First Hard Thing", "One Task to Completion"]
        case .consistency:
            ["No-Zero Day", "Keep One Promise", "Small Win Before Night"]
        case .purity:
            ["Self-control Reset", "Remove the First Trigger", "Guardrail Hour"]
        case .prayer:
            ["Prayer Walk", "Ten Honest Prayers", "Pray Before the Phone"]
        case .scripture:
            ["Scripture Before Scroll", "One Passage, One Action", "Read Before Reacting"]
        case .socialPressure:
            ["Encourage First", "Visible Courage", "Choose Before Pressure"]
        }
        return personalizedOption(goalTitles + struggleTitles, profile: profile, date: date, salt: "mission-title-\(personalization.primaryGoal)")
    }

    private func missionSummary(
        for profile: UserProfile,
        failureCount: Int,
        date: Date,
        personalization: GrowthPathPersonalization,
        difficulty: Int
    ) -> String {
        let struggle = profile.mainStruggle
        let recovery = failureCount > 0 ? " Keep it concrete and do not overcorrect." : ""
        let goalCue = personalization.missionCue
        let pressure = " \(OVRScoring.missionPressureLine(for: difficulty))"
        switch struggle {
        case .focus:
            return personalizedOption([
                "Put your phone away, block distracting apps if available, and complete one focused work block.",
                "Choose one task, start a timer, and keep every distraction outside the room until it is done.",
                "Protect a quiet block for the work you have been avoiding. No tabs, no phone, no switching."
            ], profile: profile, date: date, salt: "focus-summary") + recovery + goalCue + pressure
        case .discipline:
            return personalizedOption([
                "Choose one task you have been avoiding and finish the next meaningful step before doing anything easier.",
                "Do the first hard thing before entertainment, scrolling, or low-effort work.",
                "Pick one unfinished responsibility and move it to a clear stopping point."
            ], profile: profile, date: date, salt: "discipline-summary") + recovery + goalCue + pressure
        case .consistency:
            return personalizedOption([
                "Complete one small promise today, even if the rest of the day is messy.",
                "Protect one repeatable action that proves today is not a zero day.",
                "Do the smallest faithful version of the habit before the day gets away from you."
            ], profile: profile, date: date, salt: "consistency-summary") + recovery + goalCue + pressure
        case .purity:
            return personalizedOption([
                "Remove one trigger, pray for a clean heart, and choose an action that protects your future self.",
                "Create one boundary before temptation gets loud, then replace the urge with a better action.",
                "Move away from the first trigger and put your body somewhere that supports obedience."
            ], profile: profile, date: date, salt: "purity-summary") + recovery + goalCue + pressure
        case .prayer:
            return personalizedOption([
                "Spend the mission window in prayer, moving from honesty to surrender to one specific request.",
                "Pray before your first scroll, then write one sentence you need to keep returning to today.",
                "Take a short walk with no audio and talk honestly with God the whole time."
            ], profile: profile, date: date, salt: "prayer-summary") + recovery + goalCue + pressure
        case .scripture:
            return personalizedOption([
                "Read a short passage slowly, write one line that confronts you, and act on it today.",
                "Read before reacting to your phone, then choose one practical action from the passage.",
                "Sit with one verse long enough to name the decision it is calling you to make."
            ], profile: profile, date: date, salt: "scripture-summary") + recovery + goalCue + pressure
        case .socialPressure:
            return personalizedOption([
                "Send encouragement to someone and make one visible choice that matches your values.",
                "Decide your response before pressure hits, then act once in a way that matches your faith.",
                "Choose one relationship where you will be honest, encouraging, and unashamed today."
            ], profile: profile, date: date, salt: "social-summary") + recovery + goalCue + pressure
        }
    }

    private func personalizedOption(_ options: [String], profile: UserProfile, date: Date, salt: String) -> String {
        guard !options.isEmpty else { return "" }
        let day = Int(date.timeIntervalSince1970 / 86_400)
        let source = "\(profile.id)|\(profile.mainStruggle.rawValue)|\(day)|\(salt)"
        let hash = source.unicodeScalars.reduce(UInt64(5381)) { partial, scalar in
            ((partial << 5) &+ partial) &+ UInt64(scalar.value)
        }
        return options[Int(hash % UInt64(options.count))]
    }

    private func extraChallenges(for profile: UserProfile, personalization: GrowthPathPersonalization, difficulty: Int) -> [String] {
        [
            OVRScoring.missionPressureLine(for: difficulty),
            "Complete one \(personalization.primaryGoal.lowercased()) check-in after the mission.",
            "Tell an accountability partner what you did and what resisted you.",
            "Write a one-sentence lesson before bed.",
            profile.streakGoal >= 60 ? "Repeat the mission tomorrow at the same time to protect the long streak." : "Schedule the next small repeat before bed."
        ]
    }

    private func habits(for profile: UserProfile, personalization: GrowthPathPersonalization) -> [GrowthHabit] {
        let struggle = profile.mainStruggle
        let habits = [
            GrowthHabit(id: "goal-\(personalization.challengeTitle.lowercased().replacingOccurrences(of: " ", with: "-"))", title: personalization.habitTitle, cadence: "Daily", isEnabled: true),
            GrowthHabit(id: "morning-prayer", title: "Morning prayer", cadence: "Daily", isEnabled: true),
            GrowthHabit(id: "scripture-before-scroll", title: "Scripture before scroll", cadence: "Daily", isEnabled: struggle == .scripture || struggle == .focus),
            GrowthHabit(id: "partner-checkin", title: "Partner check-in", cadence: "3x weekly", isEnabled: true)
        ]
        return habits.reduce(into: [GrowthHabit]()) { result, habit in
            if !result.contains(where: { $0.id == habit.id }) {
                result.append(habit)
            }
        }
    }

    private func challenges(for profile: UserProfile, difficulty: Int, personalization: GrowthPathPersonalization) -> [GrowthChallenge] {
        let target = OVRScoring.requiredChallengeCompletions(for: difficulty)
        let daysRemaining = OVRScoring.challengeWindowDays(for: difficulty)
        return [
            GrowthChallenge(
                id: "personalized-\(personalization.challengeTitle.lowercased().replacingOccurrences(of: " ", with: "-"))",
                title: "\(OVRScoring.progressionLabel(for: difficulty)) \(personalization.challengeTitle)",
                detail: "\(personalization.planSummary) Complete \(target) level \(difficulty) missions with a reflection after each one.",
                category: personalization.category,
                daysRemaining: daysRemaining,
                difficulty: difficulty,
                targetCompletions: target
            ),
            GrowthChallenge(
                id: "quiet-hour",
                title: "\(OVRScoring.progressionLabel(for: difficulty)) Quiet Block",
                detail: "Protect \(difficulty >= 4 ? "two" : "one") screen-light hour this week for prayer, scripture, and planning. Complete \(target) total level \(difficulty) missions before this challenge clears.",
                category: category(for: profile.mainStruggle),
                daysRemaining: daysRemaining,
                difficulty: difficulty,
                targetCompletions: target
            )
        ]
    }
}
