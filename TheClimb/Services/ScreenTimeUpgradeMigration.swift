import Foundation

// MARK: - Upgrade audience and flow

enum ScreenTimeUpgradeProfilePresence: String, Codable {
    case unresolved
    case absent
    case existing
}

enum ScreenTimeUpgradeFlowKind: String, Codable {
    case newUserScreenTimeSetup
    case existingUserShortUpgrade
}

enum ScreenTimeUpgradeProgressStatus: String, Codable {
    case notStarted
    case inProgress
    case completed
}

enum ScreenTimeUpgradePresentationDecision: String, Codable {
    case deferUntilProfileResolved
    case presentNewUserSetup
    case presentExistingUserUpgrade
    case resumeSetup
    case deferredByUser
    case alreadyCompleted
}

enum ScreenTimeSetupStep: String, Codable, CaseIterable {
    case upgradeIntroduction
    case capabilityExplanation
    case screenTimeGoal
    case distractionSelection
    case focusPurposes
    case adultProtectionPreference
    case accountabilityPreference
    case preferredFocusSchedule
    case screenTimeAuthorization
    case firstFocusRhythmOffer
    case permanentProtectionOffer
    case finish
}

struct ScreenTimeUpgradeFlowDefinition: Codable, Equatable {
    var kind: ScreenTimeUpgradeFlowKind
    var steps: [ScreenTimeSetupStep]

    static func definition(
        for kind: ScreenTimeUpgradeFlowKind
    ) -> ScreenTimeUpgradeFlowDefinition {
        switch kind {
        case .newUserScreenTimeSetup:
            return ScreenTimeUpgradeFlowDefinition(
                kind: kind,
                steps: [
                    .screenTimeGoal,
                    .distractionSelection,
                    .focusPurposes,
                    .adultProtectionPreference,
                    .accountabilityPreference,
                    .preferredFocusSchedule,
                    .screenTimeAuthorization,
                    .firstFocusRhythmOffer,
                    .finish
                ]
            )
        case .existingUserShortUpgrade:
            return ScreenTimeUpgradeFlowDefinition(
                kind: kind,
                steps: [
                    .upgradeIntroduction,
                    .capabilityExplanation,
                    .screenTimeAuthorization,
                    .distractionSelection,
                    .firstFocusRhythmOffer,
                    .permanentProtectionOffer,
                    .finish
                ]
            )
        }
    }

    func contains(_ step: ScreenTimeSetupStep) -> Bool {
        steps.contains(step)
    }

    func canSkip(_ step: ScreenTimeSetupStep) -> Bool {
        switch step {
        case .firstFocusRhythmOffer,
             .permanentProtectionOffer,
             .adultProtectionPreference,
             .accountabilityPreference,
             .preferredFocusSchedule:
            return true
        case .upgradeIntroduction,
             .capabilityExplanation,
             .screenTimeGoal,
             .distractionSelection,
             .focusPurposes,
             .screenTimeAuthorization,
             .finish:
            return false
        }
    }

    func canDefer(_ step: ScreenTimeSetupStep) -> Bool {
        switch step {
        case .screenTimeAuthorization, .distractionSelection:
            return true
        default:
            return false
        }
    }
}

// MARK: - Versioned setup-only state

struct ScreenTimeUpgradeProgress: Identifiable, Codable, Equatable {
    var id: Int {
        experienceVersion
    }

    var experienceVersion: Int
    var flowKind: ScreenTimeUpgradeFlowKind
    var status: ScreenTimeUpgradeProgressStatus
    var completedSteps: [ScreenTimeSetupStep]
    var skippedSteps: [ScreenTimeSetupStep]
    var deferredSteps: [ScreenTimeSetupStep]
    var startedAt: Date?
    var lastPresentedAt: Date?
    var remindAfter: Date?
    var acknowledgedAt: Date?
    var completedAt: Date?
    var updatedAt: Date

    func nextStep() -> ScreenTimeSetupStep? {
        guard status != .completed else {
            return nil
        }
        let resolved = Set(completedSteps + skippedSteps + deferredSteps)
        return ScreenTimeUpgradeFlowDefinition
            .definition(for: flowKind)
            .steps
            .first { !resolved.contains($0) }
    }

    var isAcknowledged: Bool {
        acknowledgedAt != nil
    }
}

struct ScreenTimeUpgradeMigrationState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var progressByExperienceVersion: [ScreenTimeUpgradeProgress]
    var createdAt: Date
    var migratedAt: Date?
    var updatedAt: Date

    func progress(for experienceVersion: Int) -> ScreenTimeUpgradeProgress? {
        progressByExperienceVersion.first {
            $0.experienceVersion == experienceVersion
        }
    }
}

struct ScreenTimeUpgradeMigrationInput: Codable, Equatable {
    var profilePresence: ScreenTimeUpgradeProfilePresence
    var targetExperienceVersion: Int
}

struct ScreenTimeUpgradeMigrationResult: Codable, Equatable {
    var state: ScreenTimeUpgradeMigrationState?
    var decision: ScreenTimeUpgradePresentationDecision
    var flowKind: ScreenTimeUpgradeFlowKind?
    var nextStep: ScreenTimeSetupStep?
    var didChangeState: Bool

    var shouldPresent: Bool {
        decision == .presentNewUserSetup
            || decision == .presentExistingUserUpgrade
            || decision == .resumeSetup
    }
}

enum ScreenTimeUpgradeMigrationError: Error, Equatable {
    case invalidTargetExperienceVersion
    case unsupportedSchemaVersion(Int)
    case futureExperienceVersion(Int)
}

protocol ScreenTimeUpgradeMigrating {
    func migrate(
        existingState: ScreenTimeUpgradeMigrationState?,
        input: ScreenTimeUpgradeMigrationInput,
        at date: Date
    ) throws -> ScreenTimeUpgradeMigrationResult
}

struct ScreenTimeUpgradeMigrationEngine: ScreenTimeUpgradeMigrating {
    func migrate(
        existingState: ScreenTimeUpgradeMigrationState?,
        input: ScreenTimeUpgradeMigrationInput,
        at date: Date = Date()
    ) throws -> ScreenTimeUpgradeMigrationResult {
        guard input.targetExperienceVersion > 0 else {
            throw ScreenTimeUpgradeMigrationError.invalidTargetExperienceVersion
        }

        let originalState = existingState
        var state = try normalized(existingState, at: date)

        if let highestVersion = state?.progressByExperienceVersion
            .map(\.experienceVersion)
            .max(),
           highestVersion > input.targetExperienceVersion {
            throw ScreenTimeUpgradeMigrationError.futureExperienceVersion(highestVersion)
        }

        if let progress = state?.progress(for: input.targetExperienceVersion) {
            return result(
                state: state,
                progress: progress,
                decision: decision(for: progress, at: date),
                changedFrom: originalState
            )
        }

        guard input.profilePresence != .unresolved else {
            return ScreenTimeUpgradeMigrationResult(
                state: state,
                decision: .deferUntilProfileResolved,
                flowKind: nil,
                nextStep: nil,
                didChangeState: state != originalState
            )
        }

        let flowKind: ScreenTimeUpgradeFlowKind =
            input.profilePresence == .existing
            ? .existingUserShortUpgrade
            : .newUserScreenTimeSetup
        let progress = ScreenTimeUpgradeProgress(
            experienceVersion: input.targetExperienceVersion,
            flowKind: flowKind,
            status: .notStarted,
            completedSteps: [],
            skippedSteps: [],
            deferredSteps: [],
            startedAt: nil,
            lastPresentedAt: nil,
            remindAfter: nil,
            acknowledgedAt: nil,
            completedAt: nil,
            updatedAt: date
        )

        if state == nil {
            state = ScreenTimeUpgradeMigrationState(
                schemaVersion: ScreenTimeUpgradeMigrationState.currentSchemaVersion,
                progressByExperienceVersion: [progress],
                createdAt: date,
                migratedAt: date,
                updatedAt: date
            )
        } else {
            state?.progressByExperienceVersion.append(progress)
            state?.progressByExperienceVersion.sort {
                $0.experienceVersion < $1.experienceVersion
            }
            state?.updatedAt = date
        }

        return ScreenTimeUpgradeMigrationResult(
            state: state,
            decision: flowKind == .existingUserShortUpgrade
                ? .presentExistingUserUpgrade
                : .presentNewUserSetup,
            flowKind: flowKind,
            nextStep: progress.nextStep(),
            didChangeState: state != originalState
        )
    }

    private func normalized(
        _ state: ScreenTimeUpgradeMigrationState?,
        at date: Date
    ) throws -> ScreenTimeUpgradeMigrationState? {
        guard var state = state else {
            return nil
        }
        guard state.schemaVersion
                <= ScreenTimeUpgradeMigrationState.currentSchemaVersion else {
            throw ScreenTimeUpgradeMigrationError.unsupportedSchemaVersion(
                state.schemaVersion
            )
        }

        var progressByVersion: [Int: ScreenTimeUpgradeProgress] = [:]
        for progress in state.progressByExperienceVersion {
            guard progress.experienceVersion > 0 else {
                continue
            }
            let normalizedProgress = normalize(progress)
            if let existing = progressByVersion[progress.experienceVersion] {
                if normalizedProgress.updatedAt > existing.updatedAt {
                    progressByVersion[progress.experienceVersion] = normalizedProgress
                }
            } else {
                progressByVersion[progress.experienceVersion] = normalizedProgress
            }
        }

        let normalizedProgress = progressByVersion.values.sorted {
            $0.experienceVersion < $1.experienceVersion
        }
        let requiresMigration =
            state.schemaVersion != ScreenTimeUpgradeMigrationState.currentSchemaVersion
            || normalizedProgress != state.progressByExperienceVersion
        guard requiresMigration else {
            return state
        }

        state.schemaVersion = ScreenTimeUpgradeMigrationState.currentSchemaVersion
        state.progressByExperienceVersion = normalizedProgress
        state.migratedAt = date
        state.updatedAt = date
        return state
    }

    private func normalize(
        _ progress: ScreenTimeUpgradeProgress
    ) -> ScreenTimeUpgradeProgress {
        var progress = progress
        let definition = ScreenTimeUpgradeFlowDefinition.definition(for: progress.flowKind)
        let validSteps = Set(definition.steps)
        var claimed = Set<ScreenTimeSetupStep>()

        progress.completedSteps = orderedUnique(
            progress.completedSteps.filter {
                validSteps.contains($0) && claimed.insert($0).inserted
            },
            definition: definition
        )
        progress.skippedSteps = orderedUnique(
            progress.skippedSteps.filter {
                validSteps.contains($0)
                    && definition.canSkip($0)
                    && claimed.insert($0).inserted
            },
            definition: definition
        )
        progress.deferredSteps = orderedUnique(
            progress.deferredSteps.filter {
                validSteps.contains($0)
                    && definition.canDefer($0)
                    && claimed.insert($0).inserted
            },
            definition: definition
        )

        let resolved = Set(
            progress.completedSteps + progress.skippedSteps + progress.deferredSteps
        )
        if resolved.count == definition.steps.count {
            progress.status = .completed
            if progress.completedAt == nil {
                progress.completedAt = progress.updatedAt
            }
            if progress.acknowledgedAt == nil {
                progress.acknowledgedAt = progress.completedAt
            }
        } else if resolved.isEmpty {
            progress.status = .notStarted
            progress.completedAt = nil
        } else {
            progress.status = .inProgress
            progress.completedAt = nil
        }
        return progress
    }

    private func orderedUnique(
        _ steps: [ScreenTimeSetupStep],
        definition: ScreenTimeUpgradeFlowDefinition
    ) -> [ScreenTimeSetupStep] {
        let values = Set(steps)
        return definition.steps.filter(values.contains)
    }

    private func decision(
        for progress: ScreenTimeUpgradeProgress,
        at date: Date
    ) -> ScreenTimeUpgradePresentationDecision {
        if progress.status == .completed || progress.isAcknowledged {
            return .alreadyCompleted
        }
        if let remindAfter = progress.remindAfter, remindAfter > date {
            return .deferredByUser
        }
        if progress.status == .notStarted {
            return progress.flowKind == .existingUserShortUpgrade
                ? .presentExistingUserUpgrade
                : .presentNewUserSetup
        }
        return .resumeSetup
    }

    private func result(
        state: ScreenTimeUpgradeMigrationState?,
        progress: ScreenTimeUpgradeProgress,
        decision: ScreenTimeUpgradePresentationDecision,
        changedFrom originalState: ScreenTimeUpgradeMigrationState?
    ) -> ScreenTimeUpgradeMigrationResult {
        ScreenTimeUpgradeMigrationResult(
            state: state,
            decision: decision,
            flowKind: progress.flowKind,
            nextStep: decision == .alreadyCompleted || decision == .deferredByUser
                ? nil
                : progress.nextStep(),
            didChangeState: state != originalState
        )
    }
}

// MARK: - Setup progress transitions

enum ScreenTimeSetupStepOutcome: String, Codable {
    case completed
    case skipped
    case deferred
}

enum ScreenTimeUpgradeProgressError: Error, Equatable {
    case experienceNotFound
    case flowAlreadyCompleted
    case unexpectedStep
    case stepCannotBeSkipped
    case stepCannotBeDeferred
    case invalidReminderDate
}

struct ScreenTimeUpgradeProgressService {
    func markPresented(
        state: ScreenTimeUpgradeMigrationState,
        experienceVersion: Int,
        at date: Date = Date()
    ) throws -> ScreenTimeUpgradeMigrationState {
        try updatingProgress(
            state: state,
            experienceVersion: experienceVersion,
            at: date
        ) { progress in
            guard progress.status != .completed else {
                throw ScreenTimeUpgradeProgressError.flowAlreadyCompleted
            }
            progress.lastPresentedAt = date
            progress.remindAfter = nil
            if progress.startedAt == nil {
                progress.startedAt = date
            }
            if progress.status == .notStarted {
                progress.status = .inProgress
            }
        }
    }

    func record(
        step: ScreenTimeSetupStep,
        outcome: ScreenTimeSetupStepOutcome,
        state: ScreenTimeUpgradeMigrationState,
        experienceVersion: Int,
        at date: Date = Date()
    ) throws -> ScreenTimeUpgradeMigrationState {
        try updatingProgress(
            state: state,
            experienceVersion: experienceVersion,
            at: date
        ) { progress in
            let definition = ScreenTimeUpgradeFlowDefinition.definition(
                for: progress.flowKind
            )
            guard progress.status != .completed else {
                throw ScreenTimeUpgradeProgressError.flowAlreadyCompleted
            }

            let alreadyResolved = progress.completedSteps.contains(step)
                || progress.skippedSteps.contains(step)
                || progress.deferredSteps.contains(step)
            if alreadyResolved {
                return
            }
            guard progress.nextStep() == step else {
                throw ScreenTimeUpgradeProgressError.unexpectedStep
            }

            switch outcome {
            case .completed:
                progress.completedSteps.append(step)
            case .skipped:
                guard definition.canSkip(step) else {
                    throw ScreenTimeUpgradeProgressError.stepCannotBeSkipped
                }
                progress.skippedSteps.append(step)
            case .deferred:
                guard definition.canDefer(step) else {
                    throw ScreenTimeUpgradeProgressError.stepCannotBeDeferred
                }
                progress.deferredSteps.append(step)
            }

            if progress.startedAt == nil {
                progress.startedAt = date
            }
            let resolvedCount = Set(
                progress.completedSteps
                    + progress.skippedSteps
                    + progress.deferredSteps
            ).count
            if resolvedCount == definition.steps.count {
                progress.status = .completed
                progress.completedAt = date
                progress.acknowledgedAt = date
                progress.remindAfter = nil
            } else {
                progress.status = .inProgress
            }
        }
    }

    func deferPresentation(
        state: ScreenTimeUpgradeMigrationState,
        experienceVersion: Int,
        until reminderDate: Date,
        at date: Date = Date()
    ) throws -> ScreenTimeUpgradeMigrationState {
        guard reminderDate > date else {
            throw ScreenTimeUpgradeProgressError.invalidReminderDate
        }
        return try updatingProgress(
            state: state,
            experienceVersion: experienceVersion,
            at: date
        ) { progress in
            guard progress.status != .completed else {
                throw ScreenTimeUpgradeProgressError.flowAlreadyCompleted
            }
            progress.remindAfter = reminderDate
        }
    }

    func acknowledgeWithoutSetup(
        state: ScreenTimeUpgradeMigrationState,
        experienceVersion: Int,
        at date: Date = Date()
    ) throws -> ScreenTimeUpgradeMigrationState {
        try updatingProgress(
            state: state,
            experienceVersion: experienceVersion,
            at: date
        ) { progress in
            guard progress.status != .completed else {
                return
            }
            progress.acknowledgedAt = date
            progress.remindAfter = nil
        }
    }

    private func updatingProgress(
        state: ScreenTimeUpgradeMigrationState,
        experienceVersion: Int,
        at date: Date,
        update: (inout ScreenTimeUpgradeProgress) throws -> Void
    ) throws -> ScreenTimeUpgradeMigrationState {
        guard let index = state.progressByExperienceVersion.firstIndex(where: {
            $0.experienceVersion == experienceVersion
        }) else {
            throw ScreenTimeUpgradeProgressError.experienceNotFound
        }

        var state = state
        var progress = state.progressByExperienceVersion[index]
        let originalProgress = progress
        try update(&progress)
        guard progress != originalProgress else {
            return state
        }

        progress.updatedAt = date
        state.progressByExperienceVersion[index] = progress
        state.updatedAt = date
        return state
    }
}

// MARK: - Dedicated setup-state persistence

enum ScreenTimeUpgradeStateStoreError: Error, Equatable {
    case appGroupUnavailable
    case encodingFailed
    case decodingFailed
    case unsupportedSchemaVersion(Int)
    case readbackVerificationFailed
}

protocol ScreenTimeUpgradeStateStoring {
    func load() throws -> ScreenTimeUpgradeMigrationState?
    func save(_ state: ScreenTimeUpgradeMigrationState) throws
}

final class AppGroupScreenTimeUpgradeStateStore: ScreenTimeUpgradeStateStoring {
    static let appGroupIdentifier = "group.com.jaydenlacy.theclimb"
    static let storageKey = "the-climb.screen-time-upgrade-state.v1"

    private let defaults: UserDefaults?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: AppGroupScreenTimeUpgradeStateStore.appGroupIdentifier
        )
    ) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    func load() throws -> ScreenTimeUpgradeMigrationState? {
        guard let defaults = defaults else {
            throw ScreenTimeUpgradeStateStoreError.appGroupUnavailable
        }
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return nil
        }

        let state: ScreenTimeUpgradeMigrationState
        do {
            state = try decoder.decode(ScreenTimeUpgradeMigrationState.self, from: data)
        } catch {
            throw ScreenTimeUpgradeStateStoreError.decodingFailed
        }
        guard state.schemaVersion
                <= ScreenTimeUpgradeMigrationState.currentSchemaVersion else {
            throw ScreenTimeUpgradeStateStoreError.unsupportedSchemaVersion(
                state.schemaVersion
            )
        }
        return state
    }

    func save(_ state: ScreenTimeUpgradeMigrationState) throws {
        guard let defaults = defaults else {
            throw ScreenTimeUpgradeStateStoreError.appGroupUnavailable
        }
        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw ScreenTimeUpgradeStateStoreError.encodingFailed
        }
        defaults.set(data, forKey: Self.storageKey)

        guard let readbackData = defaults.data(forKey: Self.storageKey),
              let readbackState = try? decoder.decode(
                ScreenTimeUpgradeMigrationState.self,
                from: readbackData
              ),
              readbackState == state else {
            throw ScreenTimeUpgradeStateStoreError.readbackVerificationFailed
        }
    }
}

final class ScreenTimeUpgradeMigrationService {
    private let store: ScreenTimeUpgradeStateStoring
    private let engine: ScreenTimeUpgradeMigrating
    private let now: () -> Date

    init(
        store: ScreenTimeUpgradeStateStoring,
        engine: ScreenTimeUpgradeMigrating = ScreenTimeUpgradeMigrationEngine(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.engine = engine
        self.now = now
    }

    @discardableResult
    func run(
        input: ScreenTimeUpgradeMigrationInput
    ) throws -> ScreenTimeUpgradeMigrationResult {
        let existingState = try store.load()
        let result = try engine.migrate(
            existingState: existingState,
            input: input,
            at: now()
        )

        if result.didChangeState, let state = result.state {
            try store.save(state)
            guard try store.load() == state else {
                throw ScreenTimeUpgradeStateStoreError.readbackVerificationFailed
            }
        }
        return result
    }
}
