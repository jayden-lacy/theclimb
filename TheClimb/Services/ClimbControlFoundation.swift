import Foundation

// MARK: - Daily Climb

enum DailyClimbActionKind: String, Codable, CaseIterable, Identifiable {
    case scripture
    case prayer
    case mission
    case screenGoal
    case reflection

    var id: String { rawValue }
}

enum DailyClimbActionState: String, Codable, Equatable {
    case ready
    case inProgress
    case completed
    case needsAttention
    case unavailable
}

struct DailyClimbAction: Identifiable, Codable, Equatable {
    var id: DailyClimbActionKind { kind }
    var kind: DailyClimbActionKind
    var title: String
    var state: DailyClimbActionState
    var detail: String?
}

struct DailyClimb: Codable, Equatable {
    var dayKey: String
    var actions: [DailyClimbAction]

    var completedCount: Int {
        actions.filter { $0.state == .completed }.count
    }

    var progress: Double {
        guard !actions.isEmpty else { return 0 }
        return Double(completedCount) / Double(actions.count)
    }
}

struct DailyClimbInput: Equatable {
    var dayKey: String
    var scriptureReference: String?
    var scriptureCompleted: Bool
    var prayerAvailable: Bool
    var prayerCompleted: Bool
    var missionTitle: String?
    var missionState: DailyClimbActionState
    var screenGoalAvailable: Bool
    var screenGoalCompleted: Bool
    var reflectionAvailable: Bool
    var reflectionCompleted: Bool
}

struct DailyClimbService {
    func makeDailyClimb(from input: DailyClimbInput) -> DailyClimb {
        DailyClimb(
            dayKey: input.dayKey,
            actions: [
                DailyClimbAction(
                    kind: .scripture,
                    title: "Scripture",
                    state: input.scriptureCompleted ? .completed : .ready,
                    detail: input.scriptureReference
                ),
                DailyClimbAction(
                    kind: .prayer,
                    title: "Prayer",
                    state: input.prayerCompleted
                        ? .completed
                        : (input.prayerAvailable ? .ready : .unavailable),
                    detail: input.prayerCompleted ? "Completed today" : nil
                ),
                DailyClimbAction(
                    kind: .mission,
                    title: "Daily Mission",
                    state: input.missionState,
                    detail: input.missionTitle
                ),
                DailyClimbAction(
                    kind: .screenGoal,
                    title: "Screen Goal",
                    state: input.screenGoalCompleted
                        ? .completed
                        : (input.screenGoalAvailable ? .inProgress : .unavailable),
                    detail: input.screenGoalAvailable ? "Climb Time active" : "Choose distractions"
                ),
                DailyClimbAction(
                    kind: .reflection,
                    title: "Reflection",
                    state: input.reflectionCompleted
                        ? .completed
                        : (input.reflectionAvailable ? .ready : .unavailable),
                    detail: input.reflectionCompleted ? "Saved privately" : nil
                )
            ]
        )
    }
}

// MARK: - Climb Time and rewards

struct HardStopPolicy: Codable, Equatable {
    var isEnabled: Bool
    var dailyLimitSeconds: Int

    init(isEnabled: Bool = true, dailyLimitSeconds: Int) {
        self.isEnabled = isEnabled
        self.dailyLimitSeconds = max(0, dailyLimitSeconds)
    }
}

struct ScriptureRewardTier: Codable, Equatable {
    var requiredActiveReadingSeconds: Int
    var cumulativeRewardSeconds: Int

    init(requiredActiveReadingSeconds: Int, cumulativeRewardSeconds: Int) {
        self.requiredActiveReadingSeconds = max(0, requiredActiveReadingSeconds)
        self.cumulativeRewardSeconds = max(0, cumulativeRewardSeconds)
    }
}

struct RewardPolicy: Codable, Equatable {
    var baseDailyAllowanceSeconds: Int
    var maximumEarnedSecondsPerDay: Int
    var hardStop: HardStopPolicy
    var scriptureTiers: [ScriptureRewardTier]
    var missionRewardSecondsByDifficulty: [Int]
    var prayerRewardSeconds: Int
    var reflectionRewardSeconds: Int
    var bibleGameRewardSeconds: Int
    var maximumBibleGameRewardSecondsPerDay: Int

    static let balanced = RewardPolicy(
        baseDailyAllowanceSeconds: 30 * 60,
        maximumEarnedSecondsPerDay: 20 * 60,
        hardStop: HardStopPolicy(dailyLimitSeconds: 60 * 60),
        scriptureTiers: [
            ScriptureRewardTier(
                requiredActiveReadingSeconds: 5 * 60,
                cumulativeRewardSeconds: 5 * 60
            ),
            ScriptureRewardTier(
                requiredActiveReadingSeconds: 10 * 60,
                cumulativeRewardSeconds: 8 * 60
            ),
            ScriptureRewardTier(
                requiredActiveReadingSeconds: 15 * 60,
                cumulativeRewardSeconds: 10 * 60
            )
        ],
        missionRewardSecondsByDifficulty: [3, 3, 4, 4, 5],
        prayerRewardSeconds: 2 * 60,
        reflectionRewardSeconds: 2 * 60,
        bibleGameRewardSeconds: 60,
        maximumBibleGameRewardSecondsPerDay: 2 * 60
    )

    func scriptureRewardSeconds(forActiveReadingSeconds seconds: Int) -> Int {
        scriptureTiers
            .filter { seconds >= $0.requiredActiveReadingSeconds }
            .map(\.cumulativeRewardSeconds)
            .max() ?? 0
    }

    func missionRewardSeconds(forDifficulty difficulty: Int) -> Int {
        guard !missionRewardSecondsByDifficulty.isEmpty else { return 0 }
        let index = min(max(difficulty, 1), missionRewardSecondsByDifficulty.count) - 1
        return max(0, missionRewardSecondsByDifficulty[index]) * 60
    }
}

enum ClimbTimeRewardSource: String, Codable, Equatable {
    case scripture
    case mission
    case prayer
    case reflection
    case bibleGame
}

struct ClimbTimeRewardEvent: Identifiable, Codable, Equatable {
    var id: String
    var source: ClimbTimeRewardSource
    var sourceID: String
    var awardedSeconds: Int
    var awardedAt: Date
}

struct ClimbTimeWallet: Codable, Equatable {
    var dayKey: String
    var baseAllowanceSeconds: Int
    var earnedSeconds: Int
    var consumedSeconds: Int
    var hardStopSeconds: Int
    var activeScriptureSeconds: Int
    var bibleGameRewardSeconds: Int
    var rewards: [ClimbTimeRewardEvent]
    var updatedAt: Date

    var availableSeconds: Int {
        max(0, min(baseAllowanceSeconds + earnedSeconds, hardStopSeconds) - consumedSeconds)
    }

    var hardStopRemainingSeconds: Int {
        max(0, hardStopSeconds - consumedSeconds)
    }

    var isHardStopReached: Bool {
        hardStopSeconds > 0 && consumedSeconds >= hardStopSeconds
    }

    static func fresh(
        dayKey: String,
        policy: RewardPolicy,
        at date: Date
    ) -> ClimbTimeWallet {
        ClimbTimeWallet(
            dayKey: dayKey,
            baseAllowanceSeconds: max(0, policy.baseDailyAllowanceSeconds),
            earnedSeconds: 0,
            consumedSeconds: 0,
            hardStopSeconds: policy.hardStop.isEnabled
                ? max(0, policy.hardStop.dailyLimitSeconds)
                : Int.max,
            activeScriptureSeconds: 0,
            bibleGameRewardSeconds: 0,
            rewards: [],
            updatedAt: date
        )
    }
}

struct ClimbTimeService {
    func awardMission(
        missionID: String,
        difficulty: Int,
        to wallet: ClimbTimeWallet,
        policy: RewardPolicy,
        at date: Date = Date()
    ) -> ClimbTimeWallet {
        award(
            source: .mission,
            sourceID: missionID,
            requestedSeconds: policy.missionRewardSeconds(forDifficulty: difficulty),
            to: wallet,
            policy: policy,
            at: date
        )
    }

    func awardPrayer(
        sessionID: String,
        to wallet: ClimbTimeWallet,
        policy: RewardPolicy,
        at date: Date = Date()
    ) -> ClimbTimeWallet {
        award(
            source: .prayer,
            sourceID: sessionID,
            requestedSeconds: policy.prayerRewardSeconds,
            to: wallet,
            policy: policy,
            at: date
        )
    }

    func awardReflection(
        reflectionID: String,
        to wallet: ClimbTimeWallet,
        policy: RewardPolicy,
        at date: Date = Date()
    ) -> ClimbTimeWallet {
        award(
            source: .reflection,
            sourceID: reflectionID,
            requestedSeconds: policy.reflectionRewardSeconds,
            to: wallet,
            policy: policy,
            at: date
        )
    }

    func awardBibleGame(
        sessionID: String,
        to wallet: ClimbTimeWallet,
        policy: RewardPolicy,
        at date: Date = Date()
    ) -> ClimbTimeWallet {
        let remainingGameCapacity = max(
            0,
            policy.maximumBibleGameRewardSecondsPerDay - wallet.bibleGameRewardSeconds
        )
        let requested = min(policy.bibleGameRewardSeconds, remainingGameCapacity)
        var updated = award(
            source: .bibleGame,
            sourceID: sessionID,
            requestedSeconds: requested,
            to: wallet,
            policy: policy,
            at: date
        )
        let awarded = max(0, updated.earnedSeconds - wallet.earnedSeconds)
        updated.bibleGameRewardSeconds += awarded
        return updated
    }

    func recordActiveScriptureReading(
        totalActiveSeconds: Int,
        in wallet: ClimbTimeWallet,
        policy: RewardPolicy,
        at date: Date = Date()
    ) -> ClimbTimeWallet {
        var updated = wallet
        updated.activeScriptureSeconds = max(
            wallet.activeScriptureSeconds,
            max(0, totalActiveSeconds)
        )
        let alreadyAwarded = wallet.rewards
            .filter { $0.source == .scripture }
            .reduce(0) { $0 + $1.awardedSeconds }
        let targetReward = policy.scriptureRewardSeconds(
            forActiveReadingSeconds: updated.activeScriptureSeconds
        )
        let delta = max(0, targetReward - alreadyAwarded)
        guard delta > 0 else {
            updated.updatedAt = date
            return updated
        }
        return award(
            source: .scripture,
            sourceID: "scripture-tier:\(targetReward)",
            requestedSeconds: delta,
            to: updated,
            policy: policy,
            at: date
        )
    }

    func recordEligibleUsage(
        totalSeconds: Int,
        in wallet: ClimbTimeWallet,
        at date: Date = Date()
    ) -> ClimbTimeWallet {
        var updated = wallet
        updated.consumedSeconds = min(
            wallet.hardStopSeconds,
            max(wallet.consumedSeconds, max(0, totalSeconds))
        )
        updated.updatedAt = date
        return updated
    }

    private func award(
        source: ClimbTimeRewardSource,
        sourceID: String,
        requestedSeconds: Int,
        to wallet: ClimbTimeWallet,
        policy: RewardPolicy,
        at date: Date
    ) -> ClimbTimeWallet {
        let normalizedID = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty,
              requestedSeconds > 0,
              !wallet.rewards.contains(where: {
                  $0.source == source && $0.sourceID == normalizedID
              }) else {
            return wallet
        }

        let dailyCapacity = max(0, policy.maximumEarnedSecondsPerDay - wallet.earnedSeconds)
        let hardStopCapacity = max(
            0,
            wallet.hardStopSeconds - wallet.baseAllowanceSeconds - wallet.earnedSeconds
        )
        let awardedSeconds = min(requestedSeconds, dailyCapacity, hardStopCapacity)
        guard awardedSeconds > 0 else { return wallet }

        var updated = wallet
        updated.earnedSeconds += awardedSeconds
        updated.rewards.append(
            ClimbTimeRewardEvent(
                id: "\(source.rawValue):\(normalizedID)",
                source: source,
                sourceID: normalizedID,
                awardedSeconds: awardedSeconds,
                awardedAt: date
            )
        )
        updated.updatedAt = date
        return updated
    }
}

// MARK: - Scripture Before Scroll

enum ScriptureBeforeScrollMode: String, Codable, CaseIterable {
    case off
    case morningOnly
    case dailyReset
    case custom
}

struct ScriptureBeforeScrollPolicy: Codable, Equatable {
    var mode: ScriptureBeforeScrollMode
    var activeReadingRequirementSeconds: Int
    var requiresAssignedPassage: Bool
    var requiresDevotional: Bool
    var requiresPrayer: Bool

    static let disabled = ScriptureBeforeScrollPolicy(
        mode: .off,
        activeReadingRequirementSeconds: 0,
        requiresAssignedPassage: false,
        requiresDevotional: false,
        requiresPrayer: false
    )
}

struct ScriptureBeforeScrollStatus: Codable, Equatable {
    var dayKey: String
    var activeReadingSeconds: Int
    var assignedPassageCompleted: Bool
    var devotionalCompleted: Bool
    var prayerCompleted: Bool
    var updatedAt: Date

    func isSatisfied(for policy: ScriptureBeforeScrollPolicy) -> Bool {
        guard policy.mode != .off else { return true }
        let readingSatisfied = activeReadingSeconds >= max(
            0,
            policy.activeReadingRequirementSeconds
        )
        return readingSatisfied
            && (!policy.requiresAssignedPassage || assignedPassageCompleted)
            && (!policy.requiresDevotional || devotionalCompleted)
            && (!policy.requiresPrayer || prayerCompleted)
    }

    static func fresh(dayKey: String, at date: Date) -> ScriptureBeforeScrollStatus {
        ScriptureBeforeScrollStatus(
            dayKey: dayKey,
            activeReadingSeconds: 0,
            assignedPassageCompleted: false,
            devotionalCompleted: false,
            prayerCompleted: false,
            updatedAt: date
        )
    }
}

// MARK: - Restriction precedence

enum EffectiveRestrictionDisposition: String, Codable, Equatable {
    case allowed
    case shielded
    case temporarilyAllowed
    case essentialAlwaysAllowed
}

enum EffectiveRestrictionReason: String, Codable, Equatable {
    case essentialAccess
    case emergencyOverride
    case committedMode
    case activeMode
    case scheduledMode
    case sleepMode
    case scriptureBeforeScroll
    case hardStop
    case climbTime
    case noRestriction
}

struct EffectiveRestrictionInput: Equatable {
    var isEssential: Bool
    var emergencyOverrideActive: Bool
    var committedModeActive: Bool
    var activeModeBlocksSelection: Bool
    var scheduledModeBlocksSelection: Bool
    var sleepModeBlocksSelection: Bool
    var scriptureBeforeScrollRequired: Bool
    var hardStopReached: Bool
    var hasClimbTimeAvailable: Bool
    var intentionalUnlockActive: Bool
}

struct EffectiveRestrictionDecision: Equatable {
    var disposition: EffectiveRestrictionDisposition
    var reason: EffectiveRestrictionReason
}

struct EffectiveRestrictionPolicyService {
    func resolve(_ input: EffectiveRestrictionInput) -> EffectiveRestrictionDecision {
        if input.isEssential {
            return decision(.essentialAlwaysAllowed, .essentialAccess)
        }
        if input.emergencyOverrideActive {
            return decision(.temporarilyAllowed, .emergencyOverride)
        }
        if input.committedModeActive {
            return decision(.shielded, .committedMode)
        }
        if input.activeModeBlocksSelection {
            return decision(.shielded, .activeMode)
        }
        if input.scheduledModeBlocksSelection {
            return decision(.shielded, .scheduledMode)
        }
        if input.sleepModeBlocksSelection {
            return decision(.shielded, .sleepMode)
        }
        if input.scriptureBeforeScrollRequired {
            return decision(.shielded, .scriptureBeforeScroll)
        }
        if input.hardStopReached {
            return decision(.shielded, .hardStop)
        }
        if !input.hasClimbTimeAvailable {
            return decision(.shielded, .climbTime)
        }
        if input.intentionalUnlockActive {
            return decision(.temporarilyAllowed, .climbTime)
        }
        return decision(.allowed, .noRestriction)
    }

    private func decision(
        _ disposition: EffectiveRestrictionDisposition,
        _ reason: EffectiveRestrictionReason
    ) -> EffectiveRestrictionDecision {
        EffectiveRestrictionDecision(disposition: disposition, reason: reason)
    }
}

// MARK: - Persistence and daily reset

struct ClimbControlStateEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var ownerUserID: String
    var wallet: ClimbTimeWallet
    var scriptureBeforeScrollPolicy: ScriptureBeforeScrollPolicy
    var scriptureBeforeScrollStatus: ScriptureBeforeScrollStatus
    var createdAt: Date
    var updatedAt: Date

    static func fresh(
        ownerUserID: String,
        policy: RewardPolicy,
        at date: Date,
        calendar: Calendar
    ) -> ClimbControlStateEnvelope {
        let dayKey = ClimbDayKey.make(for: date, calendar: calendar)
        return ClimbControlStateEnvelope(
            schemaVersion: currentSchemaVersion,
            ownerUserID: ownerUserID,
            wallet: .fresh(dayKey: dayKey, policy: policy, at: date),
            scriptureBeforeScrollPolicy: .disabled,
            scriptureBeforeScrollStatus: .fresh(dayKey: dayKey, at: date),
            createdAt: date,
            updatedAt: date
        )
    }
}

enum ClimbDayKey {
    static func make(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d@%@",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            calendar.timeZone.identifier
        )
    }
}

struct DailyResetService {
    func reconcile(
        _ envelope: ClimbControlStateEnvelope,
        policy: RewardPolicy,
        at date: Date,
        calendar: Calendar
    ) -> ClimbControlStateEnvelope {
        let dayKey = ClimbDayKey.make(for: date, calendar: calendar)
        guard envelope.wallet.dayKey != dayKey
                || envelope.scriptureBeforeScrollStatus.dayKey != dayKey else {
            return envelope
        }

        var updated = envelope
        updated.wallet = .fresh(dayKey: dayKey, policy: policy, at: date)
        updated.scriptureBeforeScrollStatus = .fresh(dayKey: dayKey, at: date)
        updated.updatedAt = date
        return updated
    }
}

enum ClimbControlStateStoreError: Error, Equatable {
    case appGroupUnavailable
    case encodingFailed
    case decodingFailed
    case unsupportedSchema(Int)
}

protocol ClimbControlStateStoring {
    func load() throws -> ClimbControlStateEnvelope?
    func save(_ envelope: ClimbControlStateEnvelope) throws
    func clear() throws
}

final class AppGroupClimbControlStateStore: ClimbControlStateStoring {
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let envelopeKey = "the-climb.climb-control.envelope.v1"

    private let defaults: UserDefaults?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: AppGroupClimbControlStateStore.appGroupID
        )
    ) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    func load() throws -> ClimbControlStateEnvelope? {
        guard let defaults else {
            throw ClimbControlStateStoreError.appGroupUnavailable
        }
        guard let data = defaults.data(forKey: Self.envelopeKey) else {
            return nil
        }
        guard let envelope = try? decoder.decode(
            ClimbControlStateEnvelope.self,
            from: data
        ) else {
            throw ClimbControlStateStoreError.decodingFailed
        }
        guard envelope.schemaVersion <= ClimbControlStateEnvelope.currentSchemaVersion else {
            throw ClimbControlStateStoreError.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope
    }

    func save(_ envelope: ClimbControlStateEnvelope) throws {
        guard let defaults else {
            throw ClimbControlStateStoreError.appGroupUnavailable
        }
        guard let data = try? encoder.encode(envelope) else {
            throw ClimbControlStateStoreError.encodingFailed
        }
        defaults.set(data, forKey: Self.envelopeKey)
    }

    func clear() throws {
        guard let defaults else {
            throw ClimbControlStateStoreError.appGroupUnavailable
        }
        defaults.removeObject(forKey: Self.envelopeKey)
    }
}

final class ClimbControlRuntimeService {
    private let store: ClimbControlStateStoring
    private let usageEvidenceStore: ClimbTimeUsageEvidenceStoring
    private let rewardPolicy: RewardPolicy
    private let calendar: () -> Calendar
    private let now: () -> Date
    private let climbTimeService = ClimbTimeService()
    private let dailyResetService = DailyResetService()

    init(
        store: ClimbControlStateStoring = AppGroupClimbControlStateStore(),
        usageEvidenceStore: ClimbTimeUsageEvidenceStoring = AppGroupClimbTimeMonitorStore(),
        rewardPolicy: RewardPolicy = .balanced,
        calendar: @escaping () -> Calendar = { .current },
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.usageEvidenceStore = usageEvidenceStore
        self.rewardPolicy = rewardPolicy
        self.calendar = calendar
        self.now = now
    }

    func loadState(ownerUserID: String) throws -> ClimbControlStateEnvelope {
        let date = now()
        let currentCalendar = calendar()
        guard var envelope = try store.load(),
              envelope.ownerUserID == ownerUserID else {
            try? usageEvidenceStore.clear()
            let fresh = ClimbControlStateEnvelope.fresh(
                ownerUserID: ownerUserID,
                policy: rewardPolicy,
                at: date,
                calendar: currentCalendar
            )
            try store.save(fresh)
            return fresh
        }

        var reconciled = dailyResetService.reconcile(
            envelope,
            policy: rewardPolicy,
            at: date,
            calendar: currentCalendar
        )
        let evidence: ClimbTimeUsageEvidence?
        do {
            evidence = try usageEvidenceStore.loadEvidence()
        } catch {
            try? usageEvidenceStore.clear()
            evidence = nil
        }
        if let evidence,
           evidence.ownerUserID == ownerUserID,
           evidence.dayKey == reconciled.wallet.dayKey,
           evidence.observedSeconds > reconciled.wallet.consumedSeconds {
            reconciled.wallet = climbTimeService.recordEligibleUsage(
                totalSeconds: evidence.observedSeconds,
                in: reconciled.wallet,
                at: date
            )
            reconciled.updatedAt = date
        }
        if reconciled != envelope {
            envelope = reconciled
            try store.save(envelope)
        }
        return envelope
    }

    func awardMission(
        ownerUserID: String,
        missionID: String,
        difficulty: Int
    ) throws -> ClimbControlStateEnvelope {
        var envelope = try loadState(ownerUserID: ownerUserID)
        envelope.wallet = climbTimeService.awardMission(
            missionID: missionID,
            difficulty: difficulty,
            to: envelope.wallet,
            policy: rewardPolicy,
            at: now()
        )
        envelope.updatedAt = now()
        try store.save(envelope)
        return envelope
    }

    func awardReflection(
        ownerUserID: String,
        reflectionID: String
    ) throws -> ClimbControlStateEnvelope {
        var envelope = try loadState(ownerUserID: ownerUserID)
        envelope.wallet = climbTimeService.awardReflection(
            reflectionID: reflectionID,
            to: envelope.wallet,
            policy: rewardPolicy,
            at: now()
        )
        envelope.updatedAt = now()
        try store.save(envelope)
        return envelope
    }

    func recordEligibleUsage(
        ownerUserID: String,
        totalSeconds: Int
    ) throws -> ClimbControlStateEnvelope {
        var envelope = try loadState(ownerUserID: ownerUserID)
        envelope.wallet = climbTimeService.recordEligibleUsage(
            totalSeconds: totalSeconds,
            in: envelope.wallet,
            at: now()
        )
        envelope.updatedAt = now()
        try store.save(envelope)
        return envelope
    }

    func clear() throws {
        try store.clear()
        try usageEvidenceStore.clear()
    }
}
