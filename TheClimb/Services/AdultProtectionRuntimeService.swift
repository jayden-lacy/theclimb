import Foundation
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
import ManagedSettings
#endif

struct AdultProtectionRuntimeEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var configuration: AdultProtectionConfiguration?
    var rules: [AdultProtectionDomainRule]
    var allowRequests: [AdultProtectionAllowRequest]
    var disableRequests: [AdultProtectionDisableRequest]
    var events: [AdultProtectionPrivacySafeEvent]
    var updatedAt: Date

    static func empty(at date: Date = Date()) -> AdultProtectionRuntimeEnvelope {
        AdultProtectionRuntimeEnvelope(
            schemaVersion: currentSchemaVersion,
            configuration: nil,
            rules: [],
            allowRequests: [],
            disableRequests: [],
            events: [],
            updatedAt: date
        )
    }
}

enum AdultProtectionRuntimeStoreError: Error, Equatable {
    case appGroupUnavailable
    case encodingFailed
    case decodingFailed
    case unsupportedSchema(Int)
}

protocol AdultProtectionRuntimeStoring {
    func load() throws -> AdultProtectionRuntimeEnvelope
    func save(_ envelope: AdultProtectionRuntimeEnvelope) throws
}

final class AppGroupAdultProtectionRuntimeStore: AdultProtectionRuntimeStoring {
    static let envelopeKey = "the-climb.adult-protection-runtime.v1"
    static let relativePath =
        "Library/Application Support/AdultProtection/runtime-v1.json"

    private let defaults: UserDefaults?
    private let fileURL: URL?
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        defaults = UserDefaults(
            suiteName: AppGroupScreenTimePolicyStore.appGroupID
        )
        fileURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier:
                AppGroupScreenTimePolicyStore.appGroupID
        )?.appendingPathComponent(Self.relativePath, isDirectory: false)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    /// Isolated defaults remain injectable for deterministic unit tests.
    init(defaults: UserDefaults?, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        fileURL = nil
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    /// A file URL is injectable so legacy migration and protected-file behavior
    /// can be validated without depending on a signed App Group container.
    init(
        defaults: UserDefaults?,
        fileURL: URL?,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    func load() throws -> AdultProtectionRuntimeEnvelope {
        if let fileURL, fileManager.fileExists(atPath: fileURL.path) {
            guard let data = try? Data(contentsOf: fileURL) else {
                throw AdultProtectionRuntimeStoreError.decodingFailed
            }
            return try decodedEnvelope(from: data)
        }

        guard let legacyData = defaults?.data(forKey: Self.envelopeKey) else {
            return .empty()
        }

        let envelope = try decodedEnvelope(from: legacyData)
        if fileURL != nil {
            try save(envelope)
        }
        return envelope
    }

    func save(_ envelope: AdultProtectionRuntimeEnvelope) throws {
        guard let data = try? encoder.encode(envelope) else {
            throw AdultProtectionRuntimeStoreError.encodingFailed
        }

        if let fileURL {
            do {
                let directoryURL = fileURL.deletingLastPathComponent()
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
                try fileManager.setAttributes(
                    [
                        .protectionKey:
                            FileProtectionType
                                .completeUntilFirstUserAuthentication
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
                defaults?.removeObject(forKey: Self.envelopeKey)
                return
            } catch {
                throw AdultProtectionRuntimeStoreError.encodingFailed
            }
        }

        guard let defaults else {
            throw AdultProtectionRuntimeStoreError.appGroupUnavailable
        }
        defaults.set(data, forKey: Self.envelopeKey)
    }

    private func decodedEnvelope(
        from data: Data
    ) throws -> AdultProtectionRuntimeEnvelope {
        guard let envelope = try? decoder.decode(
            AdultProtectionRuntimeEnvelope.self,
            from: data
        ) else {
            throw AdultProtectionRuntimeStoreError.decodingFailed
        }
        guard envelope.schemaVersion
            <= AdultProtectionRuntimeEnvelope.currentSchemaVersion else {
            throw AdultProtectionRuntimeStoreError.unsupportedSchema(
                envelope.schemaVersion
            )
        }
        return envelope
    }
}

enum AdultProtectionRuntimeError: LocalizedError, Equatable {
    case authorizationRequired
    case authorizationDenied
    case unsupported
    case protectionNotActive
    case pendingDisableRequestExists
    case disableRequestNotFound
    case disableRequestNotReady(TimeInterval)
    case accountabilityUnavailable
    case allowRequestNotFound
    case invalidDomain
    case persistenceFailed

    var errorDescription: String? {
        return switch self {
        case .authorizationRequired:
            "Allow Screen Time access before turning on permanent protection."
        case .authorizationDenied:
            "Screen Time access is denied. You can change this in Settings."
        case .unsupported:
            "Permanent Screen Time protection is not available on this device."
        case .protectionNotActive:
            "Permanent protection is not currently active."
        case .pendingDisableRequestExists:
            "A request to turn off protection is already pending."
        case .disableRequestNotFound:
            "The request to turn off protection could not be found."
        case .disableRequestNotReady(let remaining):
            Self.disableReadyMessage(remaining: remaining)
        case .accountabilityUnavailable:
            "Accountability approval is not available in this build."
        case .allowRequestNotFound:
            "The website review request could not be found."
        case .invalidDomain:
            "Enter a valid website domain, such as example.org."
        case .persistenceFailed:
            "The protection settings could not be saved."
        }
    }

    private static func disableReadyMessage(remaining: TimeInterval) -> String {
        let hours = max(1, Int(ceil(remaining / 3_600)))
        return "Strict protection can be turned off in about \(hours) hours."
    }
}

final class AdultProtectionRuntimeService {
    static let managedStoreName = "TheClimbPermanentProtection"

    private let authorizationProvider: ScreenTimeAuthorizationProviding
    private let runtimeStore: AdultProtectionRuntimeStoring
    private let policyCoordinator: ScreenTimePolicyCoordinator
    private let disableService: AdultProtectionDisableRequestService
    private let allowService: AdultProtectionAllowRequestService
    private let now: () -> Date

    init(
        authorizationProvider: ScreenTimeAuthorizationProviding =
            AppleScreenTimeAuthorizationProvider(),
        runtimeStore: AdultProtectionRuntimeStoring =
            AppGroupAdultProtectionRuntimeStore(),
        policyCoordinator: ScreenTimePolicyCoordinator = ScreenTimePolicyCoordinator(),
        disableService: AdultProtectionDisableRequestService =
            AdultProtectionDisableRequestService(),
        allowService: AdultProtectionAllowRequestService =
            AdultProtectionAllowRequestService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.authorizationProvider = authorizationProvider
        self.runtimeStore = runtimeStore
        self.policyCoordinator = policyCoordinator
        self.disableService = disableService
        self.allowService = allowService
        self.now = now
    }

    func loadState() throws -> AdultProtectionRuntimeEnvelope {
        try runtimeStore.load()
    }

    @discardableResult
    func activate(
        mode: AdultProtectionMode
    ) async throws -> AdultProtectionRuntimeEnvelope {
        guard mode != .accountability else {
            throw AdultProtectionRuntimeError.accountabilityUnavailable
        }
        let authorization = await authorizationProvider.requestAuthorization()
        try validateAuthorization(authorization)

        let date = now()
        var envelope = try loadState()
        let configuration = AdultProtectionConfiguration(
            mode: mode,
            isEnabled: true,
            requestsAppleAutomaticAdultWebContentFilter: true,
            selectionReference: nil,
            ruleSetIdentifier: nil,
            ruleSetVersion: nil,
            activatedAt: envelope.configuration?.activatedAt ?? date,
            updatedAt: date
        )
        envelope.configuration = configuration
        envelope.updatedAt = date
        try save(envelope)

        applyScreenTimeProtection(configuration: configuration, rules: envelope.rules)
        policyCoordinator.upsert(
            AdultProtectionScreenTimePolicyAdapter().makeDesiredPolicy(
                from: configuration
            )
        )
        ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat(at: date)
        return envelope
    }

    @discardableResult
    func reapplyIfNeeded() throws -> AdultProtectionRuntimeEnvelope {
        let envelope = try loadState()
        guard let configuration = envelope.configuration,
              configuration.isEnabled else {
            clearScreenTimeProtection()
            return envelope
        }
        try validateAuthorization(authorizationProvider.currentStatus())
        applyScreenTimeProtection(configuration: configuration, rules: envelope.rules)
        policyCoordinator.upsert(
            AdultProtectionScreenTimePolicyAdapter().makeDesiredPolicy(
                from: configuration
            )
        )
        ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat(at: now())
        return envelope
    }

    @discardableResult
    func requestDisable(
        reason: AdultProtectionDisableReason
    ) throws -> AdultProtectionDisableRequest {
        var envelope = try loadState()
        guard let configuration = envelope.configuration,
              configuration.isEnabled else {
            throw AdultProtectionRuntimeError.protectionNotActive
        }
        let date = now()
        guard !envelope.disableRequests.contains(where: {
            $0.configurationID == configuration.id
                && $0.effectiveStatus(at: date) == .pending
        }) else {
            throw AdultProtectionRuntimeError.pendingDisableRequestExists
        }

        let request = disableService.makeRequest(
            id: UUID().uuidString,
            configuration: configuration,
            reason: reason,
            at: date
        )
        envelope.disableRequests.append(request)
        appendEvent(
            .init(
                occurredAt: date,
                kind: .disableRequested,
                mode: configuration.mode,
                surface: .policyEngine
            ),
            to: &envelope
        )
        envelope.updatedAt = date
        try save(envelope)
        return request
    }

    func disableEligibility(
        requestID: String
    ) throws -> AdultProtectionDisableEligibility {
        let envelope = try loadState()
        guard let request = envelope.disableRequests.first(where: { $0.id == requestID })
        else {
            throw AdultProtectionRuntimeError.disableRequestNotFound
        }
        return disableService.evaluate(
            request,
            accountabilityApproval: nil,
            at: now()
        )
    }

    @discardableResult
    func executeDisable(
        requestID: String
    ) throws -> AdultProtectionRuntimeEnvelope {
        var envelope = try loadState()
        guard let index = envelope.disableRequests.firstIndex(where: {
            $0.id == requestID
        }) else {
            throw AdultProtectionRuntimeError.disableRequestNotFound
        }
        let request = envelope.disableRequests[index]
        guard request.modeAtRequest != .accountability else {
            throw AdultProtectionRuntimeError.accountabilityUnavailable
        }
        let eligibility = disableService.evaluate(
            request,
            accountabilityApproval: nil,
            at: now()
        )
        guard eligibility.canExecute else {
            throw AdultProtectionRuntimeError.disableRequestNotReady(
                eligibility.remainingDelay
            )
        }

        envelope.disableRequests[index] = try disableService.markExecuted(
            request,
            accountabilityApproval: nil,
            at: now()
        )
        if var configuration = envelope.configuration {
            configuration.isEnabled = false
            configuration.updatedAt = now()
            envelope.configuration = configuration
            policyCoordinator.removePolicy(
                id: AdultProtectionScreenTimePolicyAdapter()
                    .makeDesiredPolicy(from: configuration).id
            )
        }
        envelope.updatedAt = now()
        try save(envelope)
        clearScreenTimeProtection()
        ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat(at: now())
        return envelope
    }

    @discardableResult
    func cancelDisableRequest(
        requestID: String
    ) throws -> AdultProtectionRuntimeEnvelope {
        var envelope = try loadState()
        guard let index = envelope.disableRequests.firstIndex(where: {
            $0.id == requestID
        }) else {
            throw AdultProtectionRuntimeError.disableRequestNotFound
        }
        envelope.disableRequests[index] = disableService.cancel(
            envelope.disableRequests[index],
            at: now()
        )
        envelope.updatedAt = now()
        try save(envelope)
        return envelope
    }

    @discardableResult
    func requestWebsiteReview(
        domain input: String,
        reason: AdultProtectionAllowReason
    ) throws -> AdultProtectionAllowRequest {
        var envelope = try loadState()
        guard let configuration = envelope.configuration,
              configuration.isEnabled else {
            throw AdultProtectionRuntimeError.protectionNotActive
        }
        guard configuration.mode != .accountability else {
            throw AdultProtectionRuntimeError.accountabilityUnavailable
        }
        let domain: AdultProtectionDomain
        do {
            domain = try AdultProtectionDomainNormalizer().normalize(input)
        } catch {
            throw AdultProtectionRuntimeError.invalidDomain
        }
        let date = now()
        let request = AdultProtectionAllowRequest(
            id: UUID().uuidString,
            domain: domain,
            requestedScope: .domainAndSubdomains,
            reason: reason,
            modeAtRequest: configuration.mode,
            status: .pending,
            requestedAt: date,
            expiresAt: date.addingTimeInterval(24 * 60 * 60),
            reviewedAt: nil,
            accountabilityApprovalID: nil
        )
        envelope.allowRequests.append(request)
        envelope.updatedAt = date
        try save(envelope)
        return request
    }

    @discardableResult
    func addBlockedDomain(
        _ input: String
    ) throws -> AdultProtectionRuntimeEnvelope {
        var envelope = try loadState()
        guard let configuration = envelope.configuration,
              configuration.isEnabled else {
            throw AdultProtectionRuntimeError.protectionNotActive
        }
        let domain: AdultProtectionDomain
        do {
            domain = try AdultProtectionDomainNormalizer().normalize(input)
        } catch {
            throw AdultProtectionRuntimeError.invalidDomain
        }
        let date = now()
        let rule = AdultProtectionDomainRule(
            id: "user-block:" + domain.rawValue,
            domain: domain,
            action: .block,
            matchScope: .domainAndSubdomains,
            source: .userAddedBlocked,
            effectiveFrom: date,
            expiresAt: nil
        )
        envelope.rules.removeAll { $0.id == rule.id }
        envelope.rules.append(rule)
        envelope.updatedAt = date
        try save(envelope)
        applyScreenTimeProtection(configuration: configuration, rules: envelope.rules)
        ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat(at: date)
        return envelope
    }

    @discardableResult
    func removeBlockedDomain(
        ruleID: String
    ) throws -> AdultProtectionRuntimeEnvelope {
        var envelope = try loadState()
        envelope.rules.removeAll {
            $0.id == ruleID && $0.source == .userAddedBlocked
        }
        envelope.updatedAt = now()
        try save(envelope)
        if let configuration = envelope.configuration, configuration.isEnabled {
            applyScreenTimeProtection(
                configuration: configuration,
                rules: envelope.rules
            )
            ScreenTimeProtectionHealthStore.recordEnforcementHeartbeat(at: now())
        }
        return envelope
    }

    @discardableResult
    func approveWebsiteReview(
        requestID: String,
        expiresAt: Date? = nil
    ) throws -> AdultProtectionRuntimeEnvelope {
        var envelope = try loadState()
        guard let index = envelope.allowRequests.firstIndex(where: {
            $0.id == requestID
        }) else {
            throw AdultProtectionRuntimeError.allowRequestNotFound
        }
        let result = try allowService.review(
            envelope.allowRequests[index],
            decision: .approve,
            accountabilityApproval: nil,
            ruleExpiresAt: expiresAt,
            at: now()
        )
        envelope.allowRequests[index] = result.request
        if let rule = result.approvedRule {
            envelope.rules.removeAll { $0.id == rule.id }
            envelope.rules.append(rule)
        }
        envelope.updatedAt = now()
        try save(envelope)

        if let configuration = envelope.configuration, configuration.isEnabled {
            applyScreenTimeProtection(
                configuration: configuration,
                rules: envelope.rules
            )
            appendAllowedEvent(configuration: configuration, envelope: &envelope)
            try save(envelope)
        }
        return envelope
    }

    func healthReport() -> ProtectionHealthReport {
        ScreenTimeProtectionHealthReader().report(
            authorization: authorizationProvider.currentStatus(),
            at: now()
        )
    }

    private func validateAuthorization(
        _ authorization: ScreenTimeAuthorizationState
    ) throws {
        switch authorization {
        case .approved, .approvedWithDataAccess:
            return
        case .notDetermined:
            throw AdultProtectionRuntimeError.authorizationRequired
        case .denied:
            throw AdultProtectionRuntimeError.authorizationDenied
        case .unsupported:
            throw AdultProtectionRuntimeError.unsupported
        }
    }

    private func save(_ envelope: AdultProtectionRuntimeEnvelope) throws {
        do {
            try runtimeStore.save(envelope)
        } catch {
            throw AdultProtectionRuntimeError.persistenceFailed
        }
    }

    private func appendEvent(
        _ event: AdultProtectionPrivacySafeEvent,
        to envelope: inout AdultProtectionRuntimeEnvelope
    ) {
        envelope.events.append(event)
        let retentionStart = now().addingTimeInterval(-90 * 24 * 60 * 60)
        envelope.events.removeAll { $0.occurredAt < retentionStart }
    }

    private func appendAllowedEvent(
        configuration: AdultProtectionConfiguration,
        envelope: inout AdultProtectionRuntimeEnvelope
    ) {
        appendEvent(
            .init(
                occurredAt: now(),
                kind: .allowedByException,
                mode: configuration.mode,
                surface: .screenTime
            ),
            to: &envelope
        )
    }

    private func applyScreenTimeProtection(
        configuration: AdultProtectionConfiguration,
        rules: [AdultProtectionDomainRule]
    ) {
#if canImport(FamilyControls) && os(iOS)
        guard #available(iOS 16.0, *),
              configuration.requestsAppleAutomaticAdultWebContentFilter else {
            return
        }
        let date = now()
        let allowedDomains = Set(
            rules
                .filter {
                    $0.action == .allow
                        && $0.isActive(at: date)
                }
                .map { WebDomain(domain: $0.domain.rawValue) }
        )
        let blockedDomains = Set(
            rules
                .filter {
                    $0.action == .block
                        && $0.isActive(at: date)
                }
                .map { WebDomain(domain: $0.domain.rawValue) }
        )
        let store = ManagedSettingsStore(
            named: ManagedSettingsStore.Name(Self.managedStoreName)
        )
        store.webContent.blockedByFilter = .auto(
            blockedDomains,
            except: allowedDomains
        )
#endif
    }

    private func clearScreenTimeProtection() {
#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            ManagedSettingsStore(
                named: ManagedSettingsStore.Name(Self.managedStoreName)
            ).clearAllSettings()
        }
#endif
    }
}

struct ScreenTimeRuntimeBootstrapper {
    private let focusRuntime: FocusSessionRuntimeService
    private let adultRuntime: AdultProtectionRuntimeService
    private let safariService: SafariContentBlockerService

    init(
        focusRuntime: FocusSessionRuntimeService = FocusSessionRuntimeService(),
        adultRuntime: AdultProtectionRuntimeService = AdultProtectionRuntimeService(),
        safariService: SafariContentBlockerService = SafariContentBlockerService()
    ) {
        self.focusRuntime = focusRuntime
        self.adultRuntime = adultRuntime
        self.safariService = safariService
    }

    func reconcile() async {
        _ = try? focusRuntime.reconcileExpiredSessions()
        _ = try? focusRuntime.resumeRhythmsIfPauseExpired()
        try? focusRuntime.refreshRhythmPolicies()
        guard let adultEnvelope = try? adultRuntime.reapplyIfNeeded(),
              adultEnvelope.configuration?.isEnabled == true else {
            return
        }
        _ = await safariService.updateRules(from: adultEnvelope.rules)
    }
}

private extension AdultProtectionDisableRequest {
    func effectiveStatus(at date: Date) -> AdultProtectionDisableRequestStatus {
        guard status == .pending, date >= expiresAt else { return status }
        return .expired
    }
}
