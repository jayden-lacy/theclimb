import Foundation

struct ClimbTimeMonitorConfiguration: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let maximumDailySeconds = 24 * 60 * 60

    var schemaVersion: Int
    var ownerUserID: String
    var dayKey: String
    var baseAllowanceSeconds: Int
    var allowanceSeconds: Int
    var hardStopSeconds: Int
    var updatedAt: Date

    init(
        ownerUserID: String,
        dayKey: String,
        baseAllowanceSeconds: Int,
        allowanceSeconds: Int,
        hardStopSeconds: Int,
        updatedAt: Date
    ) {
        let normalizedHardStop = min(
            max(hardStopSeconds, 0),
            Self.maximumDailySeconds
        )
        schemaVersion = Self.currentSchemaVersion
        self.ownerUserID = ownerUserID
        self.dayKey = dayKey
        self.baseAllowanceSeconds = min(
            max(baseAllowanceSeconds, 0),
            normalizedHardStop
        )
        self.allowanceSeconds = min(
            max(allowanceSeconds, 0),
            normalizedHardStop
        )
        self.hardStopSeconds = normalizedHardStop
        self.updatedAt = updatedAt
    }

    func effectiveAllowance(for currentDayKey: String) -> Int {
        currentDayKey == dayKey ? allowanceSeconds : baseAllowanceSeconds
    }
}

struct ClimbTimeUsageEvidence: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var ownerUserID: String
    var dayKey: String
    var observedSeconds: Int
    var callbackIDs: [String]
    var updatedAt: Date

    static func fresh(
        ownerUserID: String,
        dayKey: String,
        at date: Date
    ) -> ClimbTimeUsageEvidence {
        ClimbTimeUsageEvidence(
            schemaVersion: currentSchemaVersion,
            ownerUserID: ownerUserID,
            dayKey: dayKey,
            observedSeconds: 0,
            callbackIDs: [],
            updatedAt: date
        )
    }
}

struct ClimbTimeUsageTransition: Equatable {
    var previousObservedSeconds: Int
    var evidence: ClimbTimeUsageEvidence

    var didAdvance: Bool {
        evidence.observedSeconds > previousObservedSeconds
    }
}

struct ClimbTimeThresholdPlan: Equatable {
    var preferredCheckpointSeconds: Int = 60
    var maximumEventCount: Int = 120

    func thresholds(
        allowanceSeconds: Int,
        hardStopSeconds: Int
    ) -> [Int] {
        let hardStop = min(
            max(hardStopSeconds, 0),
            ClimbTimeMonitorConfiguration.maximumDailySeconds
        )
        guard hardStop > 0 else { return [] }

        let preferred = max(preferredCheckpointSeconds, 1)
        let regularCheckpointBudget = max(maximumEventCount - 2, 1)
        let minimumForEventBudget = Int(
            ceil(Double(hardStop) / Double(regularCheckpointBudget))
        )
        let checkpoint = max(preferred, minimumForEventBudget)
        let normalizedAllowance = min(max(allowanceSeconds, 0), hardStop)

        var values = Set<Int>()
        var next = checkpoint
        while next < hardStop {
            values.insert(next)
            next += checkpoint
        }
        if normalizedAllowance > 0 {
            values.insert(normalizedAllowance)
        }
        values.insert(hardStop)
        return values.sorted()
    }
}

enum ClimbTimeMonitorShared {
    static let appGroupID = "group.com.jaydenlacy.theclimb"
    static let activityName = "the-climb.climb-time"
    static let managedStoreName = "TheClimbClimbTime"
    static let eventPrefix = "the-climb.climb-time.usage."
    static let configurationKey = "the-climb.climb-time.monitor-configuration.v1"
    static let evidenceKey = "the-climb.climb-time.usage-evidence.v1"
    static let selectionKey = "the-climb.screen-time-selection.v1"

    static func dayKey(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d@%@",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            calendar.timeZone.identifier
        )
    }

    static func eventName(for thresholdSeconds: Int) -> String {
        eventPrefix + String(max(thresholdSeconds, 0))
    }

    static func thresholdSeconds(from eventName: String) -> Int? {
        guard eventName.hasPrefix(eventPrefix) else { return nil }
        let suffix = eventName.dropFirst(eventPrefix.count)
        guard let seconds = Int(suffix), seconds >= 0 else { return nil }
        return seconds
    }
}

enum ClimbTimeMonitorStoreError: Error, Equatable {
    case appGroupUnavailable
    case encodingFailed
    case unsupportedSchema(Int)
}

protocol ClimbTimeUsageEvidenceStoring {
    func loadEvidence() throws -> ClimbTimeUsageEvidence?
    @discardableResult
    func recordThreshold(
        ownerUserID: String,
        dayKey: String,
        thresholdSeconds: Int,
        callbackID: String,
        at date: Date
    ) throws -> ClimbTimeUsageTransition
    func clear() throws
}

struct AppGroupClimbTimeMonitorStore: ClimbTimeUsageEvidenceStoring {
    private let defaults: UserDefaults?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults? = UserDefaults(
            suiteName: ClimbTimeMonitorShared.appGroupID
        )
    ) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    func loadConfiguration() throws -> ClimbTimeMonitorConfiguration? {
        guard let defaults else {
            throw ClimbTimeMonitorStoreError.appGroupUnavailable
        }
        guard let data = defaults.data(forKey: ClimbTimeMonitorShared.configurationKey),
              let configuration = try? decoder.decode(
                ClimbTimeMonitorConfiguration.self,
                from: data
              ) else {
            return nil
        }
        guard configuration.schemaVersion <= ClimbTimeMonitorConfiguration.currentSchemaVersion else {
            throw ClimbTimeMonitorStoreError.unsupportedSchema(configuration.schemaVersion)
        }
        return configuration
    }

    func saveConfiguration(_ configuration: ClimbTimeMonitorConfiguration) throws {
        guard let defaults else {
            throw ClimbTimeMonitorStoreError.appGroupUnavailable
        }
        guard let data = try? encoder.encode(configuration) else {
            throw ClimbTimeMonitorStoreError.encodingFailed
        }
        defaults.set(data, forKey: ClimbTimeMonitorShared.configurationKey)
    }

    func loadEvidence() throws -> ClimbTimeUsageEvidence? {
        guard let defaults else {
            throw ClimbTimeMonitorStoreError.appGroupUnavailable
        }
        guard let data = defaults.data(forKey: ClimbTimeMonitorShared.evidenceKey),
              let evidence = try? decoder.decode(
                ClimbTimeUsageEvidence.self,
                from: data
              ) else {
            return nil
        }
        guard evidence.schemaVersion <= ClimbTimeUsageEvidence.currentSchemaVersion else {
            throw ClimbTimeMonitorStoreError.unsupportedSchema(evidence.schemaVersion)
        }
        return evidence
    }

    @discardableResult
    func recordThreshold(
        ownerUserID: String,
        dayKey: String,
        thresholdSeconds: Int,
        callbackID: String,
        at date: Date
    ) throws -> ClimbTimeUsageTransition {
        let previous = try loadEvidence()
        var evidence: ClimbTimeUsageEvidence
        if let previous,
           previous.ownerUserID == ownerUserID,
           previous.dayKey == dayKey {
            evidence = previous
        } else {
            evidence = .fresh(
                ownerUserID: ownerUserID,
                dayKey: dayKey,
                at: date
            )
        }

        let previousObservedSeconds = evidence.observedSeconds
        evidence.observedSeconds = max(
            previousObservedSeconds,
            max(thresholdSeconds, 0)
        )
        if !callbackID.isEmpty, !evidence.callbackIDs.contains(callbackID) {
            evidence.callbackIDs.append(callbackID)
            evidence.callbackIDs = Array(evidence.callbackIDs.suffix(160))
        }
        evidence.updatedAt = date
        try saveEvidence(evidence)
        return ClimbTimeUsageTransition(
            previousObservedSeconds: previousObservedSeconds,
            evidence: evidence
        )
    }

    func clear() throws {
        guard let defaults else {
            throw ClimbTimeMonitorStoreError.appGroupUnavailable
        }
        defaults.removeObject(forKey: ClimbTimeMonitorShared.configurationKey)
        defaults.removeObject(forKey: ClimbTimeMonitorShared.evidenceKey)
    }

    private func saveEvidence(_ evidence: ClimbTimeUsageEvidence) throws {
        guard let defaults else {
            throw ClimbTimeMonitorStoreError.appGroupUnavailable
        }
        guard let data = try? encoder.encode(evidence) else {
            throw ClimbTimeMonitorStoreError.encodingFailed
        }
        defaults.set(data, forKey: ClimbTimeMonitorShared.evidenceKey)
        defaults.synchronize()
    }
}
