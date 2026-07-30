import Foundation
import SafariServices

final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    private static let appGroupID = "group.com.jaydenlacy.theclimb"
    private static let domainRulesKey =
        "the-climb.safari-content-blocker.domains.v1"
    private static let structuredRulesKey =
        "the-climb.safari-content-blocker.rules.v2"
    private static let structuredRulesRelativePath =
        "Library/Application Support/SafariProtection/rules-v2.json"

    private enum StoredAction: String, Codable {
        case allow
        case block
    }

    private enum StoredMatchScope: String, Codable {
        case exact
        case domainAndSubdomains
    }

    private struct StoredDomainRule: Codable, Hashable {
        var domain: String
        var action: StoredAction
        var matchScope: StoredMatchScope
    }

    func beginRequest(with context: NSExtensionContext) {
        do {
            let rulesURL = try makeRuleFile()
            let item = NSExtensionItem()
            item.attachments = [NSItemProvider(contentsOf: rulesURL)].compactMap { $0 }
            context.completeRequest(returningItems: [item])
        } catch {
            context.cancelRequest(withError: error)
        }
    }

    private func makeRuleFile() throws -> URL {
        let rules: [[String: Any]] = normalizedRules().map { rule in
            [
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": [
                        rule.matchScope == .domainAndSubdomains
                            ? "*" + rule.domain
                            : rule.domain
                    ]
                ],
                "action": [
                    "type": rule.action == .block
                        ? "block"
                        : "ignore-previous-rules"
                ]
            ]
        }

        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) ?? FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent(
            "the-climb-safari-rules.json",
            isDirectory: false
        )
        let data = try JSONSerialization.data(
            withJSONObject: rules,
            options: [.sortedKeys]
        )
        try data.write(
            to: url,
            options: [
                .atomic,
                .completeFileProtectionUntilFirstUserAuthentication
            ]
        )
        return url
    }

    private func normalizedRules() -> [StoredDomainRule] {
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        let decoded: [StoredDomainRule]
        if let data = protectedRulesData(),
           let rules = try? JSONDecoder().decode([StoredDomainRule].self, from: data) {
            decoded = rules
        } else if let data = defaults?.data(forKey: Self.structuredRulesKey),
           let rules = try? JSONDecoder().decode([StoredDomainRule].self, from: data) {
            decoded = rules
        } else {
            decoded = (defaults?.stringArray(forKey: Self.domainRulesKey) ?? []).map {
                StoredDomainRule(
                    domain: $0,
                    action: .block,
                    matchScope: .domainAndSubdomains
                )
            }
        }

        return Array(
            Set(
                decoded.compactMap { rule in
                    let domain = rule.domain
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    guard !domain.isEmpty,
                          domain.unicodeScalars.allSatisfy(\.isASCII),
                          domain.allSatisfy({
                              $0.isLetter || $0.isNumber || $0 == "." || $0 == "-"
                          }) else {
                        return nil
                    }
                    return StoredDomainRule(
                        domain: domain,
                        action: rule.action,
                        matchScope: rule.matchScope
                    )
                }
            )
        )
        .sorted {
            if $0.action != $1.action {
                return $0.action == .block
            }
            if $0.domain != $1.domain {
                return $0.domain < $1.domain
            }
            return $0.matchScope.rawValue < $1.matchScope.rawValue
        }
    }

    private func protectedRulesData() -> Data? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) else {
            return nil
        }
        let fileURL = containerURL.appendingPathComponent(
            Self.structuredRulesRelativePath,
            isDirectory: false
        )
        return try? Data(contentsOf: fileURL)
    }
}
