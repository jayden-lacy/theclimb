import Foundation
#if canImport(SafariServices) && os(iOS)
import SafariServices
#endif

enum SafariProtectionRuntimeStatus: String, Codable, Equatable {
    case checking
    case enabled
    case disabled
    case unavailable
    case reloadFailed

    var isHealthy: Bool {
        self == .enabled
    }
}

struct SafariProtectionSnapshot: Codable, Equatable {
    var status: SafariProtectionRuntimeStatus
    var lastSuccessfulRuleUpdate: Date?
    var configuredDomainCount: Int
    var checkedAt: Date
}

struct SafariContentBlockerDomainRule: Codable, Hashable {
    var domain: String
    var action: AdultProtectionRuleAction
    var matchScope: AdultProtectionDomainMatchScope
}

enum SafariContentBlockerSharedStore {
    static let extensionIdentifier = "com.jaydenlacy.theclimb.contentblocker"
    static let domainRulesKey = "the-climb.safari-content-blocker.domains.v1"
    static let structuredRulesKey = "the-climb.safari-content-blocker.rules.v2"
    static let structuredRulesRelativePath =
        "Library/Application Support/SafariProtection/rules-v2.json"
    static let lastSuccessfulUpdateKey =
        "the-climb.safari-content-blocker.last-update.v1"
    static let lastStatusKey = "the-climb.safari-content-blocker.status.v1"
    static let lastStatusCheckKey =
        "the-climb.safari-content-blocker.status-checked-at.v1"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupScreenTimePolicyStore.appGroupID)
    }

    static func configuredDomains() -> [String] {
        configuredRules()
            .filter { $0.action == .block }
            .map(\.domain)
    }

    static func configuredRules() -> [SafariContentBlockerDomainRule] {
        if let data = protectedRulesData(),
           let rules = try? JSONDecoder().decode(
                [SafariContentBlockerDomainRule].self,
                from: data
           ) {
            return rules
        }

        if let data = defaults?.data(forKey: structuredRulesKey),
           let rules = try? JSONDecoder().decode(
                [SafariContentBlockerDomainRule].self,
                from: data
           ) {
            saveConfiguredRules(rules)
            return rules
        }

        let legacyRules = (defaults?.stringArray(forKey: domainRulesKey) ?? [])
            .map {
                SafariContentBlockerDomainRule(
                    domain: $0,
                    action: .block,
                    matchScope: .domainAndSubdomains
                )
            }
        if !legacyRules.isEmpty {
            saveConfiguredRules(legacyRules)
        }
        return legacyRules
    }

    static func saveConfiguredRules(_ rules: [SafariContentBlockerDomainRule]) {
        let unique = Array(Set(rules)).sorted {
            if $0.action != $1.action {
                return $0.action == .block
            }
            if $0.domain != $1.domain {
                return $0.domain < $1.domain
            }
            return $0.matchScope.rawValue < $1.matchScope.rawValue
        }
        guard let data = try? JSONEncoder().encode(unique) else { return }
        guard let fileURL = protectedRulesURL() else { return }

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [
                    .protectionKey:
                        FileProtectionType.completeUntilFirstUserAuthentication
                ],
                ofItemAtPath: directoryURL.path
            )
            try data.write(
                to: fileURL,
                options: [
                    .atomic,
                    .completeFileProtectionUntilFirstUserAuthentication
                ]
            )
            defaults?.removeObject(forKey: structuredRulesKey)
            defaults?.removeObject(forKey: domainRulesKey)
        } catch {
            return
        }
    }

    static func recordSuccessfulUpdate(at date: Date) {
        defaults?.set(
            date.timeIntervalSince1970,
            forKey: lastSuccessfulUpdateKey
        )
    }

    static func lastSuccessfulUpdate() -> Date? {
        guard let defaults,
              defaults.object(forKey: lastSuccessfulUpdateKey) != nil else {
            return nil
        }
        return Date(
            timeIntervalSince1970: defaults.double(
                forKey: lastSuccessfulUpdateKey
            )
        )
    }

    static func recordStatus(
        _ status: SafariProtectionRuntimeStatus,
        at date: Date = Date()
    ) {
        defaults?.set(status.rawValue, forKey: lastStatusKey)
        defaults?.set(date.timeIntervalSince1970, forKey: lastStatusCheckKey)
    }

    static func lastRecordedStatus() -> (
        status: SafariProtectionRuntimeStatus,
        checkedAt: Date
    )? {
        guard let raw = defaults?.string(forKey: lastStatusKey),
              let status = SafariProtectionRuntimeStatus(rawValue: raw),
              defaults?.object(forKey: lastStatusCheckKey) != nil,
              let defaults else {
            return nil
        }
        return (
            status,
            Date(
                timeIntervalSince1970: defaults.double(
                    forKey: lastStatusCheckKey
                )
            )
        )
    }

    private static func protectedRulesURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier:
                AppGroupScreenTimePolicyStore.appGroupID
        )?.appendingPathComponent(
            structuredRulesRelativePath,
            isDirectory: false
        )
    }

    private static func protectedRulesData() -> Data? {
        guard let fileURL = protectedRulesURL() else { return nil }
        return try? Data(contentsOf: fileURL)
    }
}

struct SafariContentBlockerService: Sendable {
    func snapshot() async -> SafariProtectionSnapshot {
        let status = await currentStatus()
        SafariContentBlockerSharedStore.recordStatus(status)
        return SafariProtectionSnapshot(
            status: status,
            lastSuccessfulRuleUpdate:
                SafariContentBlockerSharedStore.lastSuccessfulUpdate(),
            configuredDomainCount:
                SafariContentBlockerSharedStore.configuredDomains().count,
            checkedAt: Date()
        )
    }

    func updateRules(
        from rules: [AdultProtectionDomainRule]
    ) async -> SafariProtectionSnapshot {
        let date = Date()
        let activeRules = rules
            .filter { $0.isActive(at: date) }
            .map {
                SafariContentBlockerDomainRule(
                    domain: $0.domain.rawValue,
                    action: $0.action,
                    matchScope: $0.matchScope
                )
            }
        SafariContentBlockerSharedStore.saveConfiguredRules(activeRules)
        let status = await reload()
        SafariContentBlockerSharedStore.recordStatus(status, at: date)
        if status == .enabled {
            SafariContentBlockerSharedStore.recordSuccessfulUpdate(at: date)
        }
        return await snapshot()
    }

    func reload() async -> SafariProtectionRuntimeStatus {
#if canImport(SafariServices) && os(iOS)
        return await withCheckedContinuation { continuation in
            SFContentBlockerManager.reloadContentBlocker(
                withIdentifier:
                    SafariContentBlockerSharedStore.extensionIdentifier
            ) { error in
                guard error == nil else {
                    continuation.resume(returning: .reloadFailed)
                    return
                }
                Task {
                    continuation.resume(returning: await self.currentStatus())
                }
            }
        }
#else
        return .unavailable
#endif
    }

    private func currentStatus() async -> SafariProtectionRuntimeStatus {
#if canImport(SafariServices) && os(iOS)
        return await withCheckedContinuation { continuation in
            SFContentBlockerManager.getStateOfContentBlocker(
                withIdentifier:
                    SafariContentBlockerSharedStore.extensionIdentifier
            ) { state, error in
                guard error == nil, let state else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                continuation.resume(
                    returning: state.isEnabled ? .enabled : .disabled
                )
            }
        }
#else
        return .unavailable
#endif
    }
}
