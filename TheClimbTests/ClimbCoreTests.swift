import XCTest
@testable import The_Climb__Daily_Faith

final class ClimbCoreTests: XCTestCase {
    func testAgeGroupsIncreaseMissionMaturity() {
        XCTAssertEqual(AgeGroup.earlyTeen.baseMissionMinutes, 15)
        XCTAssertEqual(AgeGroup.youngAdult.baseMissionMinutes, 30)
        XCTAssertLessThan(AgeGroup.earlyTeen.difficultyAdjustment, AgeGroup.youngAdult.difficultyAdjustment)
        XCTAssertNotEqual(AgeGroup.earlyTeen.lessonMaturityLine, AgeGroup.youngAdult.lessonMaturityLine)
    }

    func testPhoneGoalCreatesFocusFirstGrowthPath() {
        let path = GrowthPathPersonalization.resolve(
            goals: ["Control my phone use", "Grow closer to God"],
            struggle: .focus,
            streakGoal: 30,
            ageGroup: .college
        )

        XCTAssertEqual(path.category, .focus)
        XCTAssertEqual(path.primaryGoal, "Control my phone use")
        XCTAssertTrue(path.planSummary.localizedCaseInsensitiveContains("app blocking"))
        XCTAssertTrue(path.practicalAction.localizedCaseInsensitiveContains("block"))
    }

    func testMissionDifficultyRisesWithOverallAndMaturity() {
        let starter = makeProfile(ageGroup: .earlyTeen, ovr: 50, longestStreak: 0)
        let advanced = makeProfile(ageGroup: .youngAdult, ovr: 88, longestStreak: 30)

        let starterDifficulty = OVRScoring.targetMissionDifficulty(for: starter)
        let advancedDifficulty = OVRScoring.targetMissionDifficulty(for: advanced)

        XCTAssertGreaterThan(advancedDifficulty, starterDifficulty)
        XCTAssertTrue((1...5).contains(starterDifficulty))
        XCTAssertTrue((1...5).contains(advancedDifficulty))

        XCTAssertEqual(
            OVRScoring.targetMissionDifficulty(
                for: makeProfile(ageGroup: .youngAdult, ovr: 100, longestStreak: 100)
            ),
            5
        )
        XCTAssertEqual(
            OVRScoring.targetMissionDifficulty(
                for: makeProfile(ageGroup: .earlyTeen, ovr: 0, longestStreak: 0)
            ),
            1
        )
    }

    func testOverallGrowthSlowsAtHigherScores() {
        let earlyGain = OVRScoring.completionDelta(
            previousStreak: 3,
            effortRating: 5,
            missionDifficulty: 5,
            currentOVR: 50
        )
        let advancedGain = OVRScoring.completionDelta(
            previousStreak: 3,
            effortRating: 5,
            missionDifficulty: 5,
            currentOVR: 90
        )

        XCTAssertGreaterThan(earlyGain, advancedGain)
        XCTAssertGreaterThanOrEqual(advancedGain, 1)
    }

    func testAchievementProgressIsClampedAndUnlocksAtTarget() {
        var achievement = AchievementProgress(
            id: "test",
            title: "Test Badge",
            subtitle: "Test progress",
            detail: "A deterministic test achievement.",
            systemImage: "checkmark.seal.fill",
            category: .focus,
            tone: .green,
            currentValue: 2,
            targetValue: 4,
            unlockedAt: nil
        )

        XCTAssertFalse(achievement.isUnlocked)
        XCTAssertEqual(achievement.progress, 0.5, accuracy: 0.001)
        XCTAssertNil(AchievementUnlock(achievement: achievement))

        achievement.currentValue = 8
        XCTAssertTrue(achievement.isUnlocked)
        XCTAssertEqual(achievement.progress, 1, accuracy: 0.001)
        XCTAssertNotNil(AchievementUnlock(achievement: achievement))
    }

    func testBadgeEngineProducesNoUnlockedBadgesForNewProfile() {
        let profile = makeProfile(ageGroup: .college, ovr: 50, longestStreak: 0)
        let achievements = AchievementEngine.build(
            profile: profile,
            missions: [],
            journalEntries: [],
            habits: [],
            groups: [],
            posts: [],
            partners: [],
            verseMemory: [],
            prayerStats: .empty
        )

        XCTAssertEqual(achievements.count, 16)
        XCTAssertTrue(achievements.allSatisfy { !$0.isUnlocked })
    }

    private func makeProfile(
        ageGroup: AgeGroup,
        ovr: Int,
        longestStreak: Int
    ) -> UserProfile {
        UserProfile(
            id: "test-user",
            displayName: "Test User",
            ageGroup: ageGroup,
            goals: ["Control my phone use"],
            mainStruggle: .focus,
            streakGoal: 30,
            notificationHour: 8,
            notificationMinute: 0,
            ovrScore: ovr,
            currentStreak: longestStreak,
            longestStreak: longestStreak,
            recoveryStreak: 0,
            appBlockingEnabled: false,
            joinedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
