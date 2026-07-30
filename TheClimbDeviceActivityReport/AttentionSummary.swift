import Foundation
import os

struct AttentionSummary: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    struct Day: Codable, Equatable, Identifiable, Sendable {
        let date: Date
        let screenTime: TimeInterval
        let pickupCount: Int

        var id: Date { date }
    }

    struct DistractingHour: Codable, Equatable, Sendable {
        let start: Date
        let screenTime: TimeInterval
    }

    let version: Int
    let generatedAt: Date
    let intervalStart: Date?
    let intervalEnd: Date?
    let days: [Day]
    let totalScreenTime: TimeInterval
    let averageDailyScreenTime: TimeInterval
    let totalPickupCount: Int
    let selectedApplicationDuration: TimeInterval
    let selectedCategoryDuration: TimeInterval
    let mostDistractingHour: DistractingHour?
    let supportsDailyBreakdown: Bool

    var isEmpty: Bool {
        totalScreenTime <= 0
            && totalPickupCount == 0
            && selectedApplicationDuration <= 0
            && selectedCategoryDuration <= 0
    }

    static func empty(generatedAt: Date = .now) -> AttentionSummary {
        AttentionSummary(
            version: schemaVersion,
            generatedAt: generatedAt,
            intervalStart: nil,
            intervalEnd: nil,
            days: [],
            totalScreenTime: 0,
            averageDailyScreenTime: 0,
            totalPickupCount: 0,
            selectedApplicationDuration: 0,
            selectedCategoryDuration: 0,
            mostDistractingHour: nil,
            supportsDailyBreakdown: true
        )
    }
}

struct AttentionSummaryStore {
    static let appGroupIdentifier = "group.com.jaydenlacy.theclimb"
    static let relativePath = "Library/Application Support/DeviceActivityReport/attention-summary.json"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let logger = Logger(
        subsystem: "com.jaydenlacy.theclimb.deviceactivityreport",
        category: "AttentionSummaryStore"
    )

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    @discardableResult
    func save(_ summary: AttentionSummary) -> Bool {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            logger.error("The shared App Group container is unavailable.")
            return false
        }

        let fileURL = containerURL.appendingPathComponent(Self.relativePath, isDirectory: false)
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directoryURL.path
            )

            let data = try encoder.encode(summary)
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            return true
        } catch {
            logger.error("Unable to persist the aggregate attention summary: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
