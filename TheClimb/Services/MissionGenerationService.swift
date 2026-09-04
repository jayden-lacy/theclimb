import Foundation

protocol MissionGenerationService {
    func dailyPlan(
        for profile: UserProfile,
        history: [ReflectionEntry],
        options: DailyPlanGenerationOptions
    ) async throws -> DailyPlan
}

extension MissionGenerationService {
    func dailyPlan(for profile: UserProfile, history: [ReflectionEntry]) async throws -> DailyPlan {
        try await dailyPlan(for: profile, history: history, options: .standard())
    }
}

struct DailyPlanGenerationOptions: Equatable {
    var forceRegenerate: Bool
    var regenerationReason: String?
    var generatedAt: Date
    var contentFeedback: [DailyContentFeedback]

    static func standard(
        generatedAt: Date = Date(),
        contentFeedback: [DailyContentFeedback] = []
    ) -> DailyPlanGenerationOptions {
        DailyPlanGenerationOptions(
            forceRegenerate: false,
            regenerationReason: nil,
            generatedAt: generatedAt,
            contentFeedback: contentFeedback
        )
    }

    static func regeneration(
        reason: String,
        generatedAt: Date = Date(),
        contentFeedback: [DailyContentFeedback] = []
    ) -> DailyPlanGenerationOptions {
        DailyPlanGenerationOptions(
            forceRegenerate: true,
            regenerationReason: reason,
            generatedAt: generatedAt,
            contentFeedback: contentFeedback
        )
    }

    var personalizationSalt: String {
        guard forceRegenerate else { return "standard" }
        let reason = regenerationReason?
            .lowercased()
            .replacingOccurrences(of: " ", with: "-") ?? "different-plan"
        let minuteBucket = Int(generatedAt.timeIntervalSince1970 / 60)
        return "regen-\(reason)-\(minuteBucket)"
    }
}

struct DailyPlan: Equatable {
    var devotional: Devotional
    var mission: Mission
    var habits: [GrowthHabit]
    var challenges: [GrowthChallenge]
}

final class TemplateMissionGenerationService: MissionGenerationService {
    func dailyPlan(
        for profile: UserProfile,
        history: [ReflectionEntry],
        options: DailyPlanGenerationOptions
    ) async throws -> DailyPlan {
        let date = Date().startOfDay
        let devotionalID = UUID().uuidString
        let personalization = GrowthPathPersonalization.resolve(for: profile)
        let category = personalization.category
        let failureCount = history.filter { $0.failureReason != nil }.count
        let consistencyCue = profile.currentStreak >= 3 ? "protect the streak" : "restart with one clear win"
        let missionDifficulty = difficulty(for: profile, history: history, feedback: options.contentFeedback)
        let missionDuration = duration(for: profile, difficulty: missionDifficulty)
        let personalizationSalt = options.personalizationSalt

        let devotional = Devotional(
            id: devotionalID,
            date: date,
            title: devotionalTitle(for: profile, date: date, generationSalt: personalizationSalt),
            bibleVerse: verse(for: profile.mainStruggle),
            verseText: verseText(for: profile.mainStruggle),
            explanation: devotionalExplanation(for: profile.mainStruggle, cue: consistencyCue, personalization: personalization, ageGroup: profile.ageGroup),
            reflectionQuestion: personalization.reflectionPrompt,
            practicalAction: personalization.practicalAction,
            struggle: profile.mainStruggle
        )

        let mission = Mission(
            id: UUID().uuidString,
            date: date,
            title: missionTitle(for: profile, date: date, generationSalt: personalizationSalt),
            summary: missionSummary(
                for: profile,
                failureCount: failureCount,
                date: date,
                personalization: personalization,
                difficulty: missionDifficulty,
                generationSalt: personalizationSalt
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

        let plan = DailyPlan(
            devotional: devotional,
            mission: mission,
            habits: habits(for: profile, personalization: personalization),
            challenges: challenges(for: profile, difficulty: missionDifficulty, personalization: personalization)
        )
        let behaviorAdjustedPlan = BehaviorPersonalization.apply(
            to: plan,
            history: history,
            feedback: options.contentFeedback
        )
        return FirstWeekRamp.apply(to: behaviorAdjustedPlan, profile: profile, date: date)
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
        if profile.onboarding != nil {
            return OVRScoring.minimumMissionMinutes(for: difficulty, profile: profile)
        }

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
        let base = profile.ageGroup.baseMissionMinutes + growthMinutes
        let streakAdjustment = profile.streakGoal >= 60 ? 5 : (profile.streakGoal <= 14 ? -5 : 0)
        let categoryAdjustment = switch personalization.category {
        case .faith, .selfControl, .social:
            -5
        case .focus, .discipline:
            0
        }
        return max(
            OVRScoring.minimumMissionMinutes(for: difficulty, profile: profile),
            base + streakAdjustment + categoryAdjustment
        )
    }

    private func difficulty(
        for profile: UserProfile,
        history: [ReflectionEntry],
        feedback: [DailyContentFeedback]
    ) -> Int {
        let recentFailureCount = history.prefix(5).filter { $0.failureReason != nil }.count
        let baseDifficulty = OVRScoring.targetMissionDifficulty(for: profile, recentFailureCount: recentFailureCount)
        let recentMissionFeedback = feedback
            .filter { $0.contentKind == .mission }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(6)

        let adjustment = recentMissionFeedback.reduce(0) { total, feedback in
            switch feedback.rating {
            case .tooEasy:
                total + 1
            case .tooHard:
                total - 1
            case .notRelevant, .good:
                total
            }
        }

        return min(5, max(1, baseDifficulty + max(-1, min(1, adjustment))))
    }

    private func devotionalTitle(for profile: UserProfile, date: Date, generationSalt: String) -> String {
        let struggle = profile.mainStruggle
        return switch struggle {
        case .focus:
            personalizedOption(["Single-minded Today", "Undivided Attention", "The Quiet Work"], profile: profile, date: date, salt: "focus-devotional-title-\(generationSalt)")
        case .discipline:
            personalizedOption(["Faithful in the Small", "The Next Right Thing", "Trusted With Today"], profile: profile, date: date, salt: "discipline-devotional-title-\(generationSalt)")
        case .consistency:
            personalizedOption(["Show Up Again", "Do Not Grow Weary", "Another Faithful Day"], profile: profile, date: date, salt: "consistency-devotional-title-\(generationSalt)")
        case .purity:
            personalizedOption(["A Clean Heart", "Guard the First Step", "Renewed Within"], profile: profile, date: date, salt: "purity-devotional-title-\(generationSalt)")
        case .prayer:
            personalizedOption(["Return to Prayer", "Pray Before the Spiral", "A Habit of Return"], profile: profile, date: date, salt: "prayer-devotional-title-\(generationSalt)")
        case .scripture:
            personalizedOption(["Rooted in the Word", "Lamp for the Next Step", "Read and Obey"], profile: profile, date: date, salt: "scripture-devotional-title-\(generationSalt)")
        case .socialPressure:
            personalizedOption(["Courage to Stand", "Renewed Under Pressure", "Truth Before Approval"], profile: profile, date: date, salt: "social-devotional-title-\(generationSalt)")
        }
    }

    private func verse(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "Colossians 3:23 (WEB)"
        case .discipline:
            "Luke 16:10 (WEB)"
        case .consistency:
            "Galatians 6:9 (WEB)"
        case .purity:
            "Psalm 51:10 (WEB)"
        case .prayer:
            "1 Thessalonians 5:17 (WEB)"
        case .scripture:
            "Psalm 119:105 (WEB)"
        case .socialPressure:
            "Romans 12:2 (WEB)"
        }
    }

    private func verseText(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "And whatever you do, work heartily, as for the Lord, and not for men,"
        case .discipline:
            "He who is faithful in a very little is faithful also in much. He who is dishonest in a very little is also dishonest in much."
        case .consistency:
            "Let us not be weary in doing good, for we will reap in due season, if we don't give up."
        case .purity:
            "Create in me a clean heart, O God. Renew a right spirit within me."
        case .prayer:
            "Pray without ceasing."
        case .scripture:
            "Your word is a lamp to my feet, and a light for my path."
        case .socialPressure:
            "Don't be conformed to this world, but be transformed by the renewing of your mind, so that you may prove what is the good, well-pleasing, and perfect will of God."
        }
    }

    private func devotionalExplanation(for struggle: Struggle, cue: String, personalization: GrowthPathPersonalization, ageGroup: AgeGroup) -> String {
        let goalSentence = "Because your path is centered on \(personalization.primaryGoal.lowercased()), today connects the verse to \(personalization.devotionalFocus)."
        let maturitySentence = ageGroup.lessonMaturityLine
        return switch struggle {
        case .focus:
            "This verse pulls your attention away from approval and back toward worship. Focus is not only a productivity skill; it is a way of refusing to let every notification, mood, or opinion become your master. \(goalSentence) \(maturitySentence) Today, your work becomes an act of obedience when you do it with a whole heart before God. Your focus for today is to \(cue), give God the first move, and complete the mission with attention."
        case .discipline:
            "Jesus connects small faithfulness with larger responsibility. The task you keep delaying may look ordinary, but it is training your ability to be trusted. \(goalSentence) \(maturitySentence) Discipline is built when you do the next right thing before it feels rewarding. Your focus for today is to \(cue), choose faithfulness in the small thing, and stop waiting for a perfect mood."
        case .consistency:
            "Weariness is one of the main enemies of growth. Paul does not pretend that doing good always feels exciting; he reminds us that the harvest comes after endurance. \(goalSentence) \(maturitySentence) Consistency means you keep showing up when the result is not visible yet. Your focus for today is to \(cue), take one obedient step, and trust that repeated faithfulness is never wasted."
        case .purity:
            "David asks God for more than behavior management; he asks for a clean heart and a renewed spirit. Self-control starts deeper than avoiding a trigger. \(goalSentence) \(maturitySentence) It starts by bringing desire, shame, and weakness into God’s presence instead of hiding them. Your focus for today is to \(cue), remove the first trigger, and choose the action that protects your future self."
        case .prayer:
            "Prayer is not only a scheduled moment; it is a posture of returning to God throughout the day. A short prayer offered honestly is better than a perfect prayer you never begin. \(goalSentence) \(maturitySentence) Today is about lowering the barrier and building a rhythm of return. Your focus for today is to \(cue), speak plainly with God, and let prayer interrupt the spiral before it grows."
        case .scripture:
            "The Word is described as a lamp, not a floodlight. God often gives enough clarity for the next step before He shows the whole road. \(goalSentence) \(maturitySentence) Scripture becomes practical when you let one verse confront one decision today. Your focus for today is to \(cue), read slowly, write down one line, and obey the light you have."
        case .socialPressure:
            "Pressure tries to shape you from the outside in, but transformation starts with a renewed mind. You do not have to match every room you enter. \(goalSentence) \(maturitySentence) Courage grows when your choices are formed by truth before they are tested by people. Your focus for today is to \(cue), decide your response before the pressure hits, and make one visible choice that matches your faith."
        }
    }

    private func missionTitle(for profile: UserProfile, date: Date, generationSalt: String) -> String {
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
        return personalizedOption(goalTitles + struggleTitles, profile: profile, date: date, salt: "mission-title-\(personalization.primaryGoal)-\(generationSalt)")
    }

    private func missionSummary(
        for profile: UserProfile,
        failureCount: Int,
        date: Date,
        personalization: GrowthPathPersonalization,
        difficulty: Int,
        generationSalt: String
    ) -> String {
        let struggle = profile.mainStruggle
        let recovery = failureCount > 0 ? " Keep it concrete and do not overcorrect." : ""
        let goalCue = personalization.missionCue
        let pressure = " \(OVRScoring.missionPressureLine(for: difficulty))"
        let ageCue = " \(profile.ageGroup.missionMaturityLine)"
        switch struggle {
        case .focus:
            return personalizedOption([
                "Put your phone away, block distracting apps if available, and complete one focused work block.",
                "Choose one task, start a timer, and keep every distraction outside the room until it is done.",
                "Protect a quiet block for the work you have been avoiding. No tabs, no phone, no switching."
            ], profile: profile, date: date, salt: "focus-summary-\(generationSalt)") + recovery + goalCue + pressure + ageCue
        case .discipline:
            return personalizedOption([
                "Choose one task you have been avoiding and finish the next meaningful step before doing anything easier.",
                "Do the first hard thing before entertainment, scrolling, or low-effort work.",
                "Pick one unfinished responsibility and move it to a clear stopping point."
            ], profile: profile, date: date, salt: "discipline-summary-\(generationSalt)") + recovery + goalCue + pressure + ageCue
        case .consistency:
            return personalizedOption([
                "Complete one small promise today, even if the rest of the day is messy.",
                "Protect one repeatable action that proves today is not a zero day.",
                "Do the smallest faithful version of the habit before the day gets away from you."
            ], profile: profile, date: date, salt: "consistency-summary-\(generationSalt)") + recovery + goalCue + pressure + ageCue
        case .purity:
            return personalizedOption([
                "Remove one trigger, pray for a clean heart, and choose an action that protects your future self.",
                "Create one boundary before temptation gets loud, then replace the urge with a better action.",
                "Move away from the first trigger and put your body somewhere that supports obedience."
            ], profile: profile, date: date, salt: "purity-summary-\(generationSalt)") + recovery + goalCue + pressure + ageCue
        case .prayer:
            return personalizedOption([
                "Spend the mission window in prayer, moving from honesty to surrender to one specific request.",
                "Pray before your first scroll, then write one sentence you need to keep returning to today.",
                "Take a short walk with no audio and talk honestly with God the whole time."
            ], profile: profile, date: date, salt: "prayer-summary-\(generationSalt)") + recovery + goalCue + pressure + ageCue
        case .scripture:
            return personalizedOption([
                "Read a short passage slowly, write one line that confronts you, and act on it today.",
                "Read before reacting to your phone, then choose one practical action from the passage.",
                "Sit with one verse long enough to name the decision it is calling you to make."
            ], profile: profile, date: date, salt: "scripture-summary-\(generationSalt)") + recovery + goalCue + pressure + ageCue
        case .socialPressure:
            return personalizedOption([
                "Send encouragement to someone and make one visible choice that matches your values.",
                "Decide your response before pressure hits, then act once in a way that matches your faith.",
                "Choose one relationship where you will be honest, encouraging, and unashamed today."
            ], profile: profile, date: date, salt: "social-summary-\(generationSalt)") + recovery + goalCue + pressure + ageCue
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

enum BehaviorPersonalization {
    static func apply(
        to plan: DailyPlan,
        history: [ReflectionEntry],
        feedback: [DailyContentFeedback]
    ) -> DailyPlan {
        var updatedPlan = plan
        let recentEntries = Array(history.prefix(5))
        let recentFailure = recentEntries.first { ($0.failureReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        let hardestPart = recentEntries
            .map { $0.hardestPart.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let improvementPlan = recentEntries
            .map { $0.improvementPlan.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let missionFeedback = feedback
            .filter { $0.contentKind == .mission }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(4)
        let tooEasyCount = missionFeedback.filter { $0.rating == .tooEasy }.count
        let tooHardCount = missionFeedback.filter { $0.rating == .tooHard }.count

        if let reason = recentFailure?.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            updatedPlan.mission.summary += " Counter the recent miss directly: \(reason.lowercased())."
            updatedPlan.mission.extraChallenges.insert("Name the first warning sign before it grows.", at: 0)
        } else if let hardestPart {
            updatedPlan.mission.summary += " Build around the hard part you reported: \(hardestPart.lowercased())."
        }

        if let improvementPlan {
            updatedPlan.devotional.practicalAction = "\(updatedPlan.devotional.practicalAction) Use your own plan today: \(improvementPlan)."
        }

        if tooEasyCount > tooHardCount {
            updatedPlan.mission.durationMinutes = min(120, updatedPlan.mission.durationMinutes + 5)
            updatedPlan.mission.extraChallenges.insert("Make it measurable: write the start time, finish time, and result.", at: 0)
        } else if tooHardCount > tooEasyCount {
            updatedPlan.mission.extraChallenges.insert("Lower the setup friction: prepare the space first, then start the timer.", at: 0)
        }

        updatedPlan.mission.extraChallenges = Array(updatedPlan.mission.extraChallenges.deduplicatedCaseInsensitive().prefix(5))
        return updatedPlan
    }
}

enum FirstWeekRamp {
    struct Step: Equatable {
        let day: Int
        let title: String
        let objective: String
        let spiritualAngle: String
        let missionMechanic: String
        let missionCue: String
        let practicalAction: String
        let reflectionFocus: String
        let habitFocus: String
        let extraChallenge: String
        let durationBiasMinutes: Int
        let personalizationRule: String
    }

    static func step(for profile: UserProfile, date: Date = Date().startOfDay) -> Step? {
        let calendar = Calendar.current
        let joinedDate = calendar.startOfDay(for: profile.joinedAt)
        let planDate = calendar.startOfDay(for: date)
        guard let dayOffset = calendar.dateComponents([.day], from: joinedDate, to: planDate).day,
              0...6 ~= dayOffset else {
            return nil
        }
        return steps[dayOffset]
    }

    static func apply(to plan: DailyPlan, profile: UserProfile, date: Date = Date().startOfDay) -> DailyPlan {
        guard let step = step(for: profile, date: date) else { return plan }

        var updatedPlan = plan
        updatedPlan.mission.summary = [
            step.missionCue,
            updatedPlan.mission.summary,
            step.personalizationRule
        ]
        .deduplicatedCaseInsensitive()
        .joined(separator: " ")
        updatedPlan.mission.durationMinutes = min(120, updatedPlan.mission.durationMinutes + step.durationBiasMinutes)
        updatedPlan.mission.extraChallenges = ([step.extraChallenge] + updatedPlan.mission.extraChallenges)
            .deduplicatedCaseInsensitive()
            .prefix(5)
            .map { $0 }
        updatedPlan.devotional.explanation = [
            updatedPlan.devotional.explanation,
            "First-week focus: \(step.spiritualAngle)."
        ]
        .deduplicatedCaseInsensitive()
        .joined(separator: " ")
        updatedPlan.devotional.reflectionQuestion = step.reflectionFocus
        updatedPlan.devotional.practicalAction = "\(step.practicalAction) \(updatedPlan.devotional.practicalAction)"

        let habit = GrowthHabit(
            id: "first-week-day-\(step.day)",
            title: "First week: \(step.habitFocus)",
            cadence: "Daily",
            isEnabled: true
        )
        if !updatedPlan.habits.contains(where: { $0.id == habit.id || $0.title.caseInsensitiveCompare(habit.title) == .orderedSame }) {
            updatedPlan.habits.insert(habit, at: 0)
            updatedPlan.habits = Array(updatedPlan.habits.prefix(4))
        }

        if !updatedPlan.challenges.isEmpty {
            updatedPlan.challenges[0].title = "\(step.title) \(updatedPlan.challenges[0].title)"
            updatedPlan.challenges[0].detail = [
                step.objective,
                updatedPlan.challenges[0].detail
            ]
            .deduplicatedCaseInsensitive()
            .joined(separator: " ")
        }
        return updatedPlan
    }

    private static let steps: [Step] = [
        Step(
            day: 1,
            title: "Start clean",
            objective: "Prove that one small act of obedience can start the climb.",
            spiritualAngle: "small beginnings, honest return, and obedience before emotion",
            missionMechanic: "one written commitment plus one short mission block",
            missionCue: "Day 1 must feel like a clean start: one honest prayer, one written sentence, and one small action completed before overthinking.",
            practicalAction: "Pray one honest sentence, write the exact promise for today, and begin the mission within two minutes.",
            reflectionFocus: "What resistance showed up before you even started?",
            habitFocus: "first promise kept",
            extraChallenge: "Name the exact moment today usually gets away from you.",
            durationBiasMinutes: 0,
            personalizationRule: "Keep the mission simple, but make the success condition concrete enough that you cannot fake completion."
        ),
        Step(
            day: 2,
            title: "Remove friction",
            objective: "Make obedience easier by changing the environment before pressure rises.",
            spiritualAngle: "wisdom, preparation, and removing what competes for attention",
            missionMechanic: "environment reset before the main action",
            missionCue: "Day 2 must remove one known obstacle before the mission begins.",
            practicalAction: "Move or block one distraction, clear the mission space, and start before checking another app.",
            reflectionFocus: "Which obstacle had more control over you than you expected?",
            habitFocus: "remove one obstacle early",
            extraChallenge: "Set up tomorrow's first step before bed.",
            durationBiasMinutes: 0,
            personalizationRule: "Use your main struggle to choose the obstacle: phone, delayed task, trigger, approval pressure, or prayer avoidance."
        ),
        Step(
            day: 3,
            title: "Hold attention",
            objective: "Train one uninterrupted block of attention.",
            spiritualAngle: "undivided attention, worship through focus, and staying present",
            missionMechanic: "single-task timer with no context switching",
            missionCue: "Day 3 trains attention: finish one block without switching tasks, apps, tabs, or conversations.",
            practicalAction: "Put your phone away, breathe for ten seconds, name the one task, and stay until the timer ends.",
            reflectionFocus: "What tried to pull your attention away first?",
            habitFocus: "one-task start",
            extraChallenge: "Write what pulled at your attention after the mission.",
            durationBiasMinutes: 5,
            personalizationRule: "If your goal is phone or focus related, make app blocking or physical phone distance part of the setup."
        ),
        Step(
            day: 4,
            title: "Tell the truth",
            objective: "Turn discipline into honest self-awareness and accountability.",
            spiritualAngle: "truth, confession, humility, and bringing hidden resistance to God",
            missionMechanic: "mission plus accountability check-in",
            missionCue: "Day 4 must include honest reflection and one accountability action, not only task completion.",
            practicalAction: "Ask God to show the real resistance underneath the habit, then send one honest update to a partner or trusted person.",
            reflectionFocus: "What did you not want to admit about the resistance?",
            habitFocus: "honest check-in",
            extraChallenge: "Send one accountability update before the day ends.",
            durationBiasMinutes: 5,
            personalizationRule: "Use your recent hardest part as the thing you need to tell the truth about."
        ),
        Step(
            day: 5,
            title: "Repeat the win",
            objective: "Convert one good moment into a repeatable rhythm.",
            spiritualAngle: "endurance, repetition, and faithfulness after the newness fades",
            missionMechanic: "same cue, same time, repeatable action",
            missionCue: "Day 5 repeats a faithful pattern at the same time or cue if possible.",
            practicalAction: "Anchor today's action to the same cue used yesterday, then set tomorrow's cue before the day ends.",
            reflectionFocus: "What made this action repeatable or fragile?",
            habitFocus: "same cue repeat",
            extraChallenge: "Protect a five-minute reset before your weakest hour.",
            durationBiasMinutes: 5,
            personalizationRule: "Make the mission feel like a rhythm you could keep for seven more days, not a one-off stunt."
        ),
        Step(
            day: 6,
            title: "Raise the standard",
            objective: "Add one stricter boundary now that you have evidence you can follow through.",
            spiritualAngle: "self-control, surrender, and choosing the harder faithful option",
            missionMechanic: "stronger boundary plus full timer completion",
            missionCue: "Day 6 raises the standard with one cleaner boundary, a full timer, and no easy escape route.",
            practicalAction: "Choose the stricter version of the boundary today and keep it until the reflection is submitted.",
            reflectionFocus: "What escape route did you want to keep available?",
            habitFocus: "stricter boundary",
            extraChallenge: "Avoid the easiest escape route until the mission is complete.",
            durationBiasMinutes: 10,
            personalizationRule: "If app blocking is enabled, use the blocking window. If not, use a physical boundary."
        ),
        Step(
            day: 7,
            title: "Review and commit",
            objective: "Review the first week and choose the next seven-day rhythm.",
            spiritualAngle: "remembrance, gratitude, commitment, and wisdom for the next step",
            missionMechanic: "weekly review plus one commitment action",
            missionCue: "Day 7 closes the first week with a short review before the main action and a next-rhythm commitment.",
            practicalAction: "Write one lesson from the week, thank God for one specific sign of growth, and choose the habit you will keep next week.",
            reflectionFocus: "What pattern from this week is God asking you to continue?",
            habitFocus: "next seven-day commitment",
            extraChallenge: "Choose the one habit you will keep for the next seven days.",
            durationBiasMinutes: 10,
            personalizationRule: "Make the mission feel like a weekly review and recommitment, not just another task."
        )
    ]
}

private extension Array where Element == String {
    func deduplicatedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        return filter { value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
