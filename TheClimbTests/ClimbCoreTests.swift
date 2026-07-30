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

    func testTemporaryExceptionCannotSuppressPermanentProtection() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let permanent = makePolicy(
            id: "permanent",
            source: .permanentProtection,
            strictness: .locked,
            blocksAdultWebContent: true,
            startsAt: now.addingTimeInterval(-60),
            endsAt: nil
        )
        let exception = makePolicy(
            id: "break",
            source: .temporaryException,
            strictness: .flexible,
            blocksAdultWebContent: false,
            startsAt: now.addingTimeInterval(-10),
            endsAt: now.addingTimeInterval(300),
            temporaryExceptionForPolicyID: permanent.id
        )

        let resolution = ScreenTimePolicyResolver().resolve([permanent, exception], at: now)

        XCTAssertEqual(resolution.activePolicyIDs, [permanent.id])
        XCTAssertTrue(resolution.suppressedPolicyIDs.isEmpty)
        XCTAssertTrue(resolution.permanentProtectionActive)
        XCTAssertTrue(resolution.blocksAdultWebContent)
    }

    func testTemporaryExceptionSuppressesOnlyItsFlexibleTarget() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let mission = makePolicy(
            id: "mission",
            source: .mission,
            strictness: .intentional,
            blocksAdultWebContent: false,
            startsAt: now.addingTimeInterval(-60),
            endsAt: now.addingTimeInterval(600)
        )
        let boundary = makePolicy(
            id: "boundary",
            source: .boundary,
            strictness: .locked,
            blocksAdultWebContent: true,
            startsAt: now.addingTimeInterval(-60),
            endsAt: now.addingTimeInterval(900)
        )
        let exception = makePolicy(
            id: "mission-break",
            source: .temporaryException,
            strictness: .flexible,
            blocksAdultWebContent: false,
            startsAt: now.addingTimeInterval(-10),
            endsAt: now.addingTimeInterval(120),
            temporaryExceptionForPolicyID: mission.id
        )

        let resolution = ScreenTimePolicyResolver().resolve(
            [mission, boundary, exception],
            at: now
        )

        XCTAssertEqual(resolution.activePolicyIDs, [boundary.id])
        XCTAssertEqual(resolution.suppressedPolicyIDs, [mission.id])
        XCTAssertTrue(resolution.blocksAdultWebContent)
        XCTAssertEqual(resolution.strongestStrictness, .locked)
    }

    func testPolicyResolverIgnoresExpiredPoliciesAndFindsNextTransition() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = makePolicy(
            id: "expired",
            source: .mission,
            strictness: .intentional,
            blocksAdultWebContent: true,
            startsAt: now.addingTimeInterval(-600),
            endsAt: now
        )
        let future = makePolicy(
            id: "future",
            source: .rhythm,
            strictness: .intentional,
            blocksAdultWebContent: false,
            startsAt: now.addingTimeInterval(300),
            endsAt: now.addingTimeInterval(900)
        )

        let resolution = ScreenTimePolicyResolver().resolve([expired, future], at: now)

        XCTAssertFalse(resolution.isProtectionActive)
        XCTAssertEqual(resolution.nextTransitionAt, future.startsAt)
    }

    func testScreenTimeMigrationIsIdempotentAndPreservesLegacyValues() throws {
        let suiteName = "TheClimbTests.ScreenTimeMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(false, forKey: ScreenTimePolicyMigrationService.legacyAdultContentKey)
        defaults.set(Data([0x01]), forKey: ScreenTimePolicyMigrationService.legacySelectionKey)
        defaults.set("mission-1", forKey: ScreenTimePolicyMigrationService.legacyMissionIDKey)
        defaults.set(
            now.addingTimeInterval(-60).timeIntervalSince1970,
            forKey: ScreenTimePolicyMigrationService.legacyMissionStartedAtKey
        )
        defaults.set(
            now.addingTimeInterval(600).timeIntervalSince1970,
            forKey: ScreenTimePolicyMigrationService.legacyMissionEndsAtKey
        )

        let store = AppGroupScreenTimePolicyStore(defaults: defaults)
        let migration = ScreenTimePolicyMigrationService(
            store: store,
            legacyDefaults: defaults,
            now: { now }
        )

        let first = try migration.runIfNeeded()
        let second = try migration.runIfNeeded()

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.preferences.adultContentProtectionRequested)
        XCTAssertTrue(first.preferences.hasSavedSelection)
        XCTAssertEqual(first.policies.map(\.id), ["mission:mission-1"])
        XCTAssertEqual(
            defaults.string(forKey: ScreenTimePolicyMigrationService.legacyMissionIDKey),
            "mission-1"
        )
        XCTAssertNotNil(defaults.data(forKey: ScreenTimePolicyMigrationService.legacySelectionKey))
    }

    func testScreenTimeMigrationRecoversCorruptEnvelopeFromLegacyKeys() throws {
        let suiteName = "TheClimbTests.ScreenTimeCorruption.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            Data("not-json".utf8),
            forKey: AppGroupScreenTimePolicyStore.envelopeKey
        )
        defaults.set(true, forKey: ScreenTimePolicyMigrationService.legacyAdultContentKey)
        defaults.set(Data([0x02]), forKey: ScreenTimePolicyMigrationService.legacySelectionKey)
        let store = AppGroupScreenTimePolicyStore(defaults: defaults)
        let migration = ScreenTimePolicyMigrationService(
            store: store,
            legacyDefaults: defaults,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let recovered = try migration.runIfNeeded()

        XCTAssertEqual(recovered.schemaVersion, ScreenTimePolicyEnvelope.currentSchemaVersion)
        XCTAssertNotNil(recovered.migratedAt)
        XCTAssertTrue(recovered.preferences.adultContentProtectionRequested)
        XCTAssertTrue(recovered.preferences.hasSavedSelection)
    }

    func testMissionDeactivationPreservesPermanentPolicies() throws {
        let suiteName = "TheClimbTests.ScreenTimeCoordinator.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = AppGroupScreenTimePolicyStore(defaults: defaults)
        var envelope = ScreenTimePolicyEnvelope.empty(at: now)
        envelope.migratedAt = now
        envelope.policies = [
            makePolicy(
                id: "permanent",
                source: .permanentProtection,
                strictness: .locked,
                blocksAdultWebContent: true,
                startsAt: now.addingTimeInterval(-60),
                endsAt: nil
            ),
            .mission(
                missionID: "mission-1",
                startsAt: now.addingTimeInterval(-60),
                endsAt: now.addingTimeInterval(600),
                blocksAdultWebContent: true
            )
        ]
        try store.save(envelope)

        let coordinator = ScreenTimePolicyCoordinator(
            store: store,
            defaults: defaults,
            now: { now }
        )
        let updated = coordinator.deactivateMissionPolicies()

        XCTAssertEqual(updated.policies.map(\.id), ["permanent"])
        XCTAssertTrue(coordinator.resolution(at: now).permanentProtectionActive)
    }

    func testProtectionHealthRequiresAuthorizationAndSharedStorage() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let signal = ProtectionHealthSignal(
            authorization: .denied,
            appGroupAccessible: false,
            hasSavedSelection: true,
            adultProtectionExpected: true,
            expectedEnforcementActive: true,
            policyUpdatedAt: now,
            enforcementHeartbeatAt: now,
            safariLayerConfigured: false,
            safariLayerHealthy: false,
            networkLayerConfigured: false,
            networkLayerHealthy: false
        )

        let report = ProtectionHealthEvaluator().evaluate(signal, at: now)

        XCTAssertEqual(report.status, .actionRequired)
        XCTAssertEqual(report.reasons, [.authorizationRequired, .appGroupUnavailable])
    }

    func testProtectionHealthDoesNotClaimFullProtectionWithoutHeartbeat() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let signal = ProtectionHealthSignal(
            authorization: .approved,
            appGroupAccessible: true,
            hasSavedSelection: true,
            adultProtectionExpected: true,
            expectedEnforcementActive: true,
            policyUpdatedAt: now,
            enforcementHeartbeatAt: nil,
            safariLayerConfigured: false,
            safariLayerHealthy: false,
            networkLayerConfigured: false,
            networkLayerHealthy: false
        )

        let report = ProtectionHealthEvaluator().evaluate(signal, at: now)

        XCTAssertEqual(report.status, .partiallyProtected)
        XCTAssertEqual(report.reasons, [.enforcementHeartbeatMissing])
    }

    func testProductionFlagsExposeOnlyImplementedScreenTimeCapability() {
        XCTAssertTrue(ScreenTimeFeatureFlags.production.isEnabled(.immediateFocus))
        XCTAssertTrue(ScreenTimeFeatureFlags.production.isEnabled(.recurringRhythms))
        XCTAssertTrue(ScreenTimeFeatureFlags.production.isEnabled(.appBoundaries))
        XCTAssertTrue(ScreenTimeFeatureFlags.production.isEnabled(.permanentProtection))
        XCTAssertTrue(ScreenTimeFeatureFlags.production.isEnabled(.safariExtension))
        XCTAssertFalse(ScreenTimeFeatureFlags.production.isEnabled(.networkFiltering))
    }

    func testCrossMidnightRhythmUsesPreviousScheduledDay() throws {
        let mondayAtTen = utcDate(2027, 1, 4, 22, 0)
        let tuesdayAtOne = utcDate(2027, 1, 5, 1, 0)
        let tuesdayAtSix = utcDate(2027, 1, 5, 6, 0)
        let rhythm = FocusRhythm(
            id: "night",
            sourceID: .rhythm("night"),
            name: "Night",
            purpose: .sleep,
            strictness: .intentional,
            weekdays: [.monday],
            startTime: try LocalTime(hour: 22, minute: 0),
            endTime: try LocalTime(hour: 6, minute: 0),
            timeZoneIdentifier: "UTC",
            selectionReference: FocusSelectionReference(
                rawValue: ScreenTimeSelectionReference.defaultSelection
            ),
            essentialAppsReference: nil,
            blocksAdultWebContent: true,
            isEnabled: true,
            createdAt: mondayAtTen,
            updatedAt: mondayAtTen
        )

        let evaluation = FocusRhythmEvaluator().evaluate(rhythm, at: tuesdayAtOne)

        XCTAssertEqual(evaluation.activeOccurrence?.startsAt, mondayAtTen)
        XCTAssertEqual(evaluation.activeOccurrence?.endsAt, tuesdayAtSix)
    }

    func testAttentionReportUsesOnlyRecordedProtectedIntervals() {
        let start = utcDate(2027, 1, 4, 8, 0)
        let end = start.addingTimeInterval(30 * 60)
        let sourceID = FocusSourceID.session("session-1")
        let record = ProtectedTimeRecord(
            id: "session-1",
            sourceID: sourceID,
            sourceKind: .focusSession,
            purpose: .prayer,
            strictness: .intentional,
            startedAt: start,
            endedAt: end,
            plannedDuration: 30 * 60,
            outcome: .completed,
            breakSegments: [
                ProtectedTimeBreakSegment(
                    id: "break",
                    sourceID: sourceID,
                    startsAt: start.addingTimeInterval(10 * 60),
                    endsAt: start.addingTimeInterval(15 * 60)
                )
            ],
            enforcementEvidence: .policyConfirmed
        )

        let report = AttentionReportService().report(
            from: [record],
            within: DateInterval(
                start: start.addingTimeInterval(-60),
                end: end.addingTimeInterval(60)
            )
        )

        XCTAssertEqual(report.evidence, .protectedTimeRecords)
        XCTAssertEqual(report.recordCount, 1)
        XCTAssertEqual(report.protectedDuration, 25 * 60, accuracy: 0.01)
        XCTAssertEqual(report.completionRate, 1, accuracy: 0.001)
    }

    func testAdultDomainNormalizerDropsURLPathAndNormalizesCase() throws {
        let domain = try AdultProtectionDomainNormalizer().normalize(
            "HTTPS://Account.Example.COM:443/private/path?token=ignored"
        )

        XCTAssertEqual(domain.rawValue, "account.example.com")
    }

    func testApprovedSpecificAllowRuleBeatsParentBlockRule() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let blockedDomain = try AdultProtectionDomain(validating: "example.com")
        let allowedDomain = try AdultProtectionDomain(validating: "safe.example.com")
        let rules = [
            AdultProtectionDomainRule(
                id: "parent-block",
                domain: blockedDomain,
                action: .block,
                matchScope: .domainAndSubdomains,
                source: .signedRemote,
                effectiveFrom: nil,
                expiresAt: nil
            ),
            AdultProtectionDomainRule(
                id: "approved-allow",
                domain: allowedDomain,
                action: .allow,
                matchScope: .exact,
                source: .locallyApprovedAllow,
                effectiveFrom: nil,
                expiresAt: nil
            )
        ]

        let decision = try AdultProtectionRuleEngine().evaluate(
            domainInput: "safe.example.com",
            rules: rules,
            at: now
        )

        XCTAssertEqual(decision.disposition, .allow)
        XCTAssertEqual(decision.matchedRuleID, "approved-allow")
    }

    func testStrictProtectionRequiresFullDisableDelay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let configuration = AdultProtectionConfiguration(
            mode: .strict,
            isEnabled: true,
            requestsAppleAutomaticAdultWebContentFilter: true,
            selectionReference: ScreenTimeSelectionReference.defaultSelection,
            ruleSetIdentifier: nil,
            ruleSetVersion: nil,
            activatedAt: now,
            updatedAt: now
        )
        let service = AdultProtectionDisableRequestService()
        let request = service.makeRequest(
            id: "disable",
            configuration: configuration,
            reason: .changeProtectionMode,
            at: now
        )

        let early = service.evaluate(
            request,
            accountabilityApproval: nil,
            at: now.addingTimeInterval(60 * 60)
        )
        let eligible = service.evaluate(
            request,
            accountabilityApproval: nil,
            at: now.addingTimeInterval(24 * 60 * 60)
        )

        XCTAssertEqual(early.state, .waitingForDelay)
        XCTAssertFalse(early.canExecute)
        XCTAssertEqual(eligible.state, .eligible)
        XCTAssertTrue(eligible.canExecute)
    }

    func testCapabilitySnapshotDoesNotClaimUnavailableFilteringLayers() {
        let snapshot = CurrentBuildAdultProtectionCapabilityProvider().currentSnapshot(
            screenTimeAuthorization: .approved,
            screenTimePolicyActive: false,
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(
            snapshot.capability(for: .safariContentBlocker)?.implementationState,
            .includedInCurrentBuild
        )
        XCTAssertEqual(
            snapshot.capability(for: .networkFilter)?.implementationState,
            .notIncludedInCurrentBuild
        )
    }

    func testStandardPermanentProtectionCanDisableImmediatelyWithoutRemovingMission() throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let runtimeStore = InMemoryAdultProtectionRuntimeStore(
            envelope: makeAdultRuntimeEnvelope(mode: .standard, at: now)
        )
        let policySuite = "TheClimbTests.AdultPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: policySuite))
        defer { defaults.removePersistentDomain(forName: policySuite) }
        let policyStore = AppGroupScreenTimePolicyStore(defaults: defaults)
        var policyEnvelope = ScreenTimePolicyEnvelope.empty(at: now)
        policyEnvelope.migratedAt = now
        let configuration = try XCTUnwrap(runtimeStore.envelope.configuration)
        policyEnvelope.policies = [
            AdultProtectionScreenTimePolicyAdapter().makeDesiredPolicy(
                from: configuration
            ),
            .mission(
                missionID: "mission-1",
                startsAt: now,
                endsAt: now.addingTimeInterval(1_800),
                blocksAdultWebContent: true
            )
        ]
        try policyStore.save(policyEnvelope)
        let coordinator = ScreenTimePolicyCoordinator(
            store: policyStore,
            defaults: defaults,
            now: { now }
        )
        let runtime = AdultProtectionRuntimeService(
            authorizationProvider: StubScreenTimeAuthorizationProvider(.approved),
            runtimeStore: runtimeStore,
            policyCoordinator: coordinator,
            now: { now }
        )

        let request = try runtime.requestDisable(reason: .noLongerNeeded)
        XCTAssertTrue(try runtime.disableEligibility(requestID: request.id).canExecute)

        now.addTimeInterval(1)
        let updated = try runtime.executeDisable(requestID: request.id)

        XCTAssertFalse(try XCTUnwrap(updated.configuration).isEnabled)
        XCTAssertFalse(coordinator.resolution(at: now).permanentProtectionActive)
        XCTAssertEqual(coordinator.prepare().policies.map(\.source), [.mission])
    }

    func testStrictPermanentProtectionCannotDisableBeforeTwentyFourHours() throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let runtimeStore = InMemoryAdultProtectionRuntimeStore(
            envelope: makeAdultRuntimeEnvelope(mode: .strict, at: now)
        )
        let runtime = AdultProtectionRuntimeService(
            authorizationProvider: StubScreenTimeAuthorizationProvider(.approved),
            runtimeStore: runtimeStore,
            now: { now }
        )

        let request = try runtime.requestDisable(reason: .noLongerNeeded)
        XCTAssertThrowsError(try runtime.executeDisable(requestID: request.id)) { error in
            guard case AdultProtectionRuntimeError.disableRequestNotReady = error else {
                return XCTFail("Expected disableRequestNotReady, received \(error)")
            }
        }

        now.addTimeInterval(24 * 60 * 60)
        let updated = try runtime.executeDisable(requestID: request.id)

        XCTAssertFalse(try XCTUnwrap(updated.configuration).isEnabled)
        XCTAssertEqual(updated.disableRequests.first?.status, .executed)
    }

    func testWebsiteReviewStoresNormalizedAllowRuleWithoutRawURL() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let runtimeStore = InMemoryAdultProtectionRuntimeStore(
            envelope: makeAdultRuntimeEnvelope(mode: .standard, at: now)
        )
        let runtime = AdultProtectionRuntimeService(
            authorizationProvider: StubScreenTimeAuthorizationProvider(.approved),
            runtimeStore: runtimeStore,
            now: { now }
        )

        let request = try runtime.requestWebsiteReview(
            domain: "HTTPS://School.Example.org/path?student=private",
            reason: .education
        )
        let updated = try runtime.approveWebsiteReview(requestID: request.id)

        XCTAssertEqual(request.domain.rawValue, "school.example.org")
        XCTAssertEqual(updated.rules.map(\.domain.rawValue), ["school.example.org"])
        XCTAssertEqual(updated.rules.map(\.action), [.allow])
        XCTAssertEqual(updated.events.last?.kind, .allowedByException)
    }

    func testUserBlockedDomainIsNormalizedAndRemovable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let runtimeStore = InMemoryAdultProtectionRuntimeStore(
            envelope: makeAdultRuntimeEnvelope(mode: .standard, at: now)
        )
        let runtime = AdultProtectionRuntimeService(
            authorizationProvider: StubScreenTimeAuthorizationProvider(.approved),
            runtimeStore: runtimeStore,
            now: { now }
        )

        let blocked = try runtime.addBlockedDomain(
            "HTTPS://Trigger.Example.org/private"
        )
        let rule = try XCTUnwrap(blocked.rules.first)

        XCTAssertEqual(rule.domain.rawValue, "trigger.example.org")
        XCTAssertEqual(rule.source, .userAddedBlocked)
        XCTAssertEqual(rule.matchScope, .domainAndSubdomains)

        let removed = try runtime.removeBlockedDomain(ruleID: rule.id)
        XCTAssertTrue(removed.rules.isEmpty)
    }

    func testAdultProtectionRuntimeStoreRejectsCorruptEnvelope() throws {
        let suiteName = "TheClimbTests.AdultRuntimeCorrupt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            Data("not-json".utf8),
            forKey: AppGroupAdultProtectionRuntimeStore.envelopeKey
        )

        XCTAssertThrowsError(
            try AppGroupAdultProtectionRuntimeStore(defaults: defaults).load()
        ) { error in
            XCTAssertEqual(
                error as? AdultProtectionRuntimeStoreError,
                .decodingFailed
            )
        }
    }

    func testAdultProtectionRuntimeStoreMigratesLegacyDefaultsToFile() throws {
        let suiteName = "TheClimbTests.AdultRuntimeMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TheClimbTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let fileURL = directoryURL.appendingPathComponent(
            "adult-protection.json",
            isDirectory: false
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let envelope = makeAdultRuntimeEnvelope(mode: .strict, at: date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        defaults.set(
            try encoder.encode(envelope),
            forKey: AppGroupAdultProtectionRuntimeStore.envelopeKey
        )

        let store = AppGroupAdultProtectionRuntimeStore(
            defaults: defaults,
            fileURL: fileURL
        )
        let migrated = try store.load()

        XCTAssertEqual(migrated, envelope)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(
            defaults.data(
                forKey: AppGroupAdultProtectionRuntimeStore.envelopeKey
            )
        )
        XCTAssertEqual(try store.load(), envelope)
    }

    func testIntentionalEarlyExitRequiresReasonAndCreatesDelay() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = try FocusSessionService(identifier: { "session-1" }).start(
            FocusSessionRequest(
                purpose: .prayer,
                customPurposeName: nil,
                plannedDuration: 25 * 60,
                strictness: .intentional,
                selectionReference: FocusSelectionReference(
                    rawValue: ScreenTimeSelectionReference.defaultSelection
                ),
                essentialAppsReference: nil,
                blocksAdultWebContent: true
            ),
            at: now
        )
        let store = InMemoryFocusSessionDomainStore(
            envelope: FocusSessionDomainEnvelope(
                activeSessions: [session],
                createdAt: now,
                updatedAt: now
            )
        )
        let runtime = FocusSessionRuntimeService(
            domainStore: store,
            now: { now }
        )

        XCTAssertThrowsError(
            try runtime.requestEarlyExit(sessionID: session.id, reason: " ")
        ) { error in
            XCTAssertEqual(
                error as? FocusSessionRuntimeError,
                .intentionalExitReasonRequired
            )
        }

        let resolution = try runtime.requestEarlyExit(
            sessionID: session.id,
            reason: "I need to answer the door"
        )
        guard case .pending(let request) = resolution else {
            return XCTFail("Expected a pending intentional exit")
        }
        XCTAssertEqual(request.reason, "I need to answer the door")
        XCTAssertEqual(
            request.earliestExecutionAt.timeIntervalSince(request.requestedAt),
            5,
            accuracy: 0.001
        )
        XCTAssertEqual(store.envelope.earlyExitRequests, [request])
    }

    func testLockedSessionRejectsEarlyExit() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = try FocusSessionService(identifier: { "locked" }).start(
            FocusSessionRequest(
                purpose: .deepWork,
                customPurposeName: nil,
                plannedDuration: 30 * 60,
                strictness: .locked,
                selectionReference: FocusSelectionReference(
                    rawValue: ScreenTimeSelectionReference.defaultSelection
                ),
                essentialAppsReference: nil,
                blocksAdultWebContent: true
            ),
            at: now
        )
        let runtime = FocusSessionRuntimeService(
            domainStore: InMemoryFocusSessionDomainStore(
                envelope: FocusSessionDomainEnvelope(
                    activeSessions: [session],
                    createdAt: now,
                    updatedAt: now
                )
            ),
            now: { now }
        )

        XCTAssertThrowsError(
            try runtime.requestEarlyExit(
                sessionID: session.id,
                reason: "Changed my mind"
            )
        ) { error in
            XCTAssertEqual(
                error as? FocusSessionRuntimeError,
                .lockedSessionCannotEndEarly
            )
        }
    }

    func testRhythmPauseExpiresWithoutRemovingPermanentProtection() throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let rhythm = FocusRhythm(
            id: "morning",
            sourceID: .rhythm("morning"),
            name: "Morning Scripture",
            purpose: .bibleStudy,
            strictness: .intentional,
            weekdays: Set(Weekday.allCases),
            startTime: try LocalTime(hour: 7, minute: 0),
            endTime: try LocalTime(hour: 7, minute: 30),
            timeZoneIdentifier: "UTC",
            selectionReference: FocusSelectionReference(
                rawValue: ScreenTimeSelectionReference.defaultSelection
            ),
            essentialAppsReference: nil,
            blocksAdultWebContent: true,
            isEnabled: true,
            createdAt: now,
            updatedAt: now
        )
        let store = InMemoryFocusSessionDomainStore(
            envelope: FocusSessionDomainEnvelope(
                rhythms: [rhythm],
                createdAt: now,
                updatedAt: now
            )
        )
        let suiteName = "TheClimbTests.RhythmPause.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policyStore = AppGroupScreenTimePolicyStore(defaults: defaults)
        var policyEnvelope = ScreenTimePolicyEnvelope.empty(at: now)
        policyEnvelope.migratedAt = now
        policyEnvelope.policies = [
            makePolicy(
                id: "permanent",
                source: .permanentProtection,
                strictness: .locked,
                blocksAdultWebContent: true,
                startsAt: now.addingTimeInterval(-60),
                endsAt: nil
            ),
            FocusRhythmEvaluator().policy(
                for: rhythm,
                occurrence: FocusRhythmOccurrence(
                    rhythmID: rhythm.id,
                    sourceID: rhythm.sourceID,
                    startsAt: now.addingTimeInterval(-60),
                    endsAt: now.addingTimeInterval(1_800)
                )
            )
        ]
        try policyStore.save(policyEnvelope)
        let coordinator = ScreenTimePolicyCoordinator(
            store: policyStore,
            defaults: defaults,
            now: { now }
        )
        let runtime = FocusSessionRuntimeService(
            policyCoordinator: coordinator,
            domainStore: store,
            now: { now }
        )

        let paused = try runtime.pauseRhythms(
            until: now.addingTimeInterval(3_600),
            reason: .travel
        )

        XCTAssertEqual(paused.rhythmPause?.reason, .travel)
        XCTAssertTrue(coordinator.resolution(at: now).permanentProtectionActive)
        XCTAssertFalse(
            coordinator.prepare().policies.contains {
                $0.source == .rhythm
            }
        )

        now.addTimeInterval(3_601)
        store.envelope.rhythms = []
        let resumed = try runtime.resumeRhythmsIfPauseExpired()
        XCTAssertNil(resumed.rhythmPause)
        XCTAssertTrue(coordinator.resolution(at: now).permanentProtectionActive)
    }

    func testStewardshipScoreUsesEvidenceWithoutWritingOVR() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let interval = DateInterval(
            start: start,
            end: start.addingTimeInterval(7 * 24 * 60 * 60)
        )
        let records = [
            StewardshipCompletionRecord(
                id: "mission-1",
                kind: .mission,
                itemID: "mission-1",
                scheduledAt: start,
                completedAt: start,
                outcome: .completed
            ),
            StewardshipCompletionRecord(
                id: "mission-2",
                kind: .mission,
                itemID: "mission-2",
                scheduledAt: start.addingTimeInterval(86_400),
                completedAt: nil,
                outcome: .missed
            ),
            StewardshipCompletionRecord(
                id: "reflection-1",
                kind: .reflection,
                itemID: "reflection-1",
                scheduledAt: start,
                completedAt: start,
                outcome: .completed
            )
        ]
        let result = StewardshipScoreEngine().score(
            evidence: StewardshipScoreEvidence(
                protectedFocusRecords: [],
                rhythmAdherenceRecords: [],
                boundaryAdherenceRecords: [],
                completionRecords: records
            ),
            within: interval,
            evaluatedAt: interval.end
        )

        XCTAssertEqual(result.state, .scored)
        XCTAssertEqual(result.score, 70)
        XCTAssertEqual(result.meaning, .behavioralStewardshipNotSpiritualWorth)
    }

    func testAttentionAssistOnlyRecommendsFromCurrentEvidence() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let evaluation = AttentionAssistEngine().evaluate(
            signals: [
                .devotionalStillOpen(
                    AttentionAssistDevotionalSignal(
                        signalID: "devotional-signal",
                        devotionalReference: "devotional-1",
                        observedAt: now.addingTimeInterval(-60),
                        expiresAt: now.addingTimeInterval(3_600),
                        plannedCompletionBy: now.addingTimeInterval(-30),
                        isCompleted: false
                    )
                )
            ],
            preferences: .recommended(
                frequency: .balanced,
                quietHours: nil,
                timeZoneIdentifier: "UTC"
            ),
            deliveryHistory: [],
            at: now
        )

        XCTAssertEqual(evaluation.candidates.map(\.kind), [.devotionalStillOpen])
        XCTAssertEqual(
            evaluation.candidates.first?.evidence.source,
            .localFaithCompletionState
        )
    }

    func testExistingUserReceivesShortScreenTimeUpgrade() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try ScreenTimeUpgradeMigrationEngine().migrate(
            existingState: nil,
            input: ScreenTimeUpgradeMigrationInput(
                profilePresence: .existing,
                targetExperienceVersion: 1
            ),
            at: now
        )

        XCTAssertEqual(result.decision, .presentExistingUserUpgrade)
        XCTAssertEqual(result.flowKind, .existingUserShortUpgrade)
        XCTAssertEqual(result.nextStep, .upgradeIntroduction)
        XCTAssertTrue(result.didChangeState)
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

    private func makePolicy(
        id: String,
        source: ProtectionSourceKind,
        strictness: ProtectionStrictness,
        blocksAdultWebContent: Bool,
        startsAt: Date?,
        endsAt: Date?,
        temporaryExceptionForPolicyID: String? = nil
    ) -> ProtectionPolicy {
        let createdAt = startsAt ?? Date(timeIntervalSince1970: 1_800_000_000)
        return ProtectionPolicy(
            id: id,
            source: source,
            strictness: strictness,
            selectionReference: ScreenTimeSelectionReference.defaultSelection,
            blocksAdultWebContent: blocksAdultWebContent,
            isEnabled: true,
            startsAt: startsAt,
            endsAt: endsAt,
            temporaryExceptionForPolicyID: temporaryExceptionForPolicyID,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeAdultRuntimeEnvelope(
        mode: AdultProtectionMode,
        at date: Date
    ) -> AdultProtectionRuntimeEnvelope {
        AdultProtectionRuntimeEnvelope(
            schemaVersion: AdultProtectionRuntimeEnvelope.currentSchemaVersion,
            configuration: AdultProtectionConfiguration(
                mode: mode,
                isEnabled: true,
                requestsAppleAutomaticAdultWebContentFilter: true,
                selectionReference: nil,
                ruleSetIdentifier: nil,
                ruleSetVersion: nil,
                activatedAt: date,
                updatedAt: date
            ),
            rules: [],
            allowRequests: [],
            disableRequests: [],
            events: [],
            updatedAt: date
        )
    }

    private func utcDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        ) ?? Date(timeIntervalSince1970: 0)
    }
}

private final class InMemoryAdultProtectionRuntimeStore:
    AdultProtectionRuntimeStoring {
    var envelope: AdultProtectionRuntimeEnvelope

    init(envelope: AdultProtectionRuntimeEnvelope) {
        self.envelope = envelope
    }

    func load() throws -> AdultProtectionRuntimeEnvelope {
        envelope
    }

    func save(_ envelope: AdultProtectionRuntimeEnvelope) throws {
        self.envelope = envelope
    }
}

private final class InMemoryFocusSessionDomainStore: FocusSessionDomainStoring {
    var envelope: FocusSessionDomainEnvelope

    init(envelope: FocusSessionDomainEnvelope) {
        self.envelope = envelope
    }

    var hasStoredEnvelope: Bool {
        true
    }

    func load() throws -> FocusSessionDomainEnvelope {
        envelope
    }

    func save(_ envelope: FocusSessionDomainEnvelope) throws {
        self.envelope = envelope
    }
}

private final class StubScreenTimeAuthorizationProvider:
    ScreenTimeAuthorizationProviding {
    private let status: ScreenTimeAuthorizationState

    init(_ status: ScreenTimeAuthorizationState) {
        self.status = status
    }

    func currentStatus() -> ScreenTimeAuthorizationState {
        status
    }

    func requestAuthorization() async -> ScreenTimeAuthorizationState {
        status
    }
}
