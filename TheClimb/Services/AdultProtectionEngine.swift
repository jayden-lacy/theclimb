import Foundation

// MARK: - Protection configuration

enum AdultProtectionMode: String, Codable, CaseIterable {
    case standard
    case strict
    case accountability
}

struct AdultProtectionModePolicy: Codable, Equatable {
    var mode: AdultProtectionMode
    var minimumDisableDelay: TimeInterval
    var allowRequestsRequireAccountabilityApproval: Bool
    var disableRequestsRequireAccountabilityApproval: Bool

    static func recommended(for mode: AdultProtectionMode) -> AdultProtectionModePolicy {
        switch mode {
        case .standard:
            return AdultProtectionModePolicy(
                mode: mode,
                minimumDisableDelay: 0,
                allowRequestsRequireAccountabilityApproval: false,
                disableRequestsRequireAccountabilityApproval: false
            )
        case .strict:
            return AdultProtectionModePolicy(
                mode: mode,
                minimumDisableDelay: 24 * 60 * 60,
                allowRequestsRequireAccountabilityApproval: false,
                disableRequestsRequireAccountabilityApproval: false
            )
        case .accountability:
            return AdultProtectionModePolicy(
                mode: mode,
                minimumDisableDelay: 24 * 60 * 60,
                allowRequestsRequireAccountabilityApproval: true,
                disableRequestsRequireAccountabilityApproval: true
            )
        }
    }
}

struct AdultProtectionConfiguration: Identifiable, Codable, Equatable {
    var id: String
    var mode: AdultProtectionMode
    var isEnabled: Bool
    var requestsAppleAutomaticAdultWebContentFilter: Bool
    var selectionReference: String?
    var ruleSetIdentifier: String?
    var ruleSetVersion: Int?
    var activatedAt: Date?
    var updatedAt: Date

    init(
        id: String = "adult-protection",
        mode: AdultProtectionMode,
        isEnabled: Bool,
        requestsAppleAutomaticAdultWebContentFilter: Bool,
        selectionReference: String?,
        ruleSetIdentifier: String?,
        ruleSetVersion: Int?,
        activatedAt: Date?,
        updatedAt: Date
    ) {
        self.id = id
        self.mode = mode
        self.isEnabled = isEnabled
        self.requestsAppleAutomaticAdultWebContentFilter =
            requestsAppleAutomaticAdultWebContentFilter
        self.selectionReference = selectionReference
        self.ruleSetIdentifier = ruleSetIdentifier
        self.ruleSetVersion = ruleSetVersion
        self.activatedAt = activatedAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Domain normalization

enum AdultProtectionDomainNormalizationError: String, Error, Codable, Equatable {
    case emptyInput
    case malformedInput
    case credentialsNotAllowed
    case wildcardNotAllowed
    case unsupportedInternationalDomain
    case domainTooLong
    case invalidLabel
}

protocol AdultProtectionDomainNormalizing {
    func normalize(_ input: String) throws -> AdultProtectionDomain
}

struct AdultProtectionDomainNormalizer: AdultProtectionDomainNormalizing {
    func normalize(_ input: String) throws -> AdultProtectionDomain {
        try AdultProtectionDomain(validating: input)
    }
}

struct AdultProtectionDomain: RawRepresentable, Codable, Hashable, Comparable {
    let rawValue: String

    init?(rawValue: String) {
        guard let domain = try? AdultProtectionDomain(validating: rawValue) else {
            return nil
        }
        self = domain
    }

    init(validating input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AdultProtectionDomainNormalizationError.emptyInput
        }
        guard !trimmed.contains("*") else {
            throw AdultProtectionDomainNormalizationError.wildcardNotAllowed
        }

        let candidate: String
        if trimmed.hasPrefix("//") {
            candidate = "https:" + trimmed
        } else if trimmed.range(of: "://") == nil {
            candidate = "https://" + trimmed
        } else {
            candidate = trimmed
        }

        guard let components = URLComponents(string: candidate) else {
            throw AdultProtectionDomainNormalizationError.malformedInput
        }
        guard components.user == nil, components.password == nil else {
            throw AdultProtectionDomainNormalizationError.credentialsNotAllowed
        }
        guard let canonicalURL = components.url,
              let parsedHost = canonicalURL.host,
              !parsedHost.isEmpty else {
            throw AdultProtectionDomainNormalizationError.malformedInput
        }

        var host = parsedHost.lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else {
            throw AdultProtectionDomainNormalizationError.malformedInput
        }
        guard host.utf8.count <= 253 else {
            throw AdultProtectionDomainNormalizationError.domainTooLong
        }
        guard host.unicodeScalars.allSatisfy({ $0.value < 128 }) else {
            // Apple Foundation canonicalizes supported IDNs to their ASCII form.
            // Rejecting what it cannot canonicalize prevents visually equivalent
            // Unicode hosts from creating different rule identities.
            throw AdultProtectionDomainNormalizationError.unsupportedInternationalDomain
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy(Self.isValidLabel) else {
            throw AdultProtectionDomainNormalizationError.invalidLabel
        }

        rawValue = host
    }

    private static func isValidLabel(_ label: Substring) -> Bool {
        guard !label.isEmpty, label.utf8.count <= 63 else {
            return false
        }
        guard label.first != "-", label.last != "-" else {
            return false
        }
        return label.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (value >= 97 && value <= 122)
                || (value >= 48 && value <= 57)
                || value == 45
        }
    }

    var labelCount: Int {
        rawValue.split(separator: ".").count
    }

    func isEqualToOrSubdomain(of domain: AdultProtectionDomain) -> Bool {
        rawValue == domain.rawValue || rawValue.hasSuffix("." + domain.rawValue)
    }

    static func < (lhs: AdultProtectionDomain, rhs: AdultProtectionDomain) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let encodedValue = try container.decode(String.self)
        try self.init(validating: encodedValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Domain rules and precedence

enum AdultProtectionRuleAction: String, Codable, CaseIterable {
    case allow
    case block
}

enum AdultProtectionDomainMatchScope: String, Codable, CaseIterable {
    case exact
    case domainAndSubdomains
}

enum AdultProtectionRuleSource: String, Codable, CaseIterable {
    case bundled
    case signedRemote
    case userAddedBlocked
    case guardianAddedBlocked
    case locallyApprovedAllow
    case accountabilityApprovedAllow

    fileprivate var precedence: Int {
        switch self {
        case .bundled:
            return 100
        case .signedRemote:
            return 200
        case .userAddedBlocked:
            return 250
        case .guardianAddedBlocked:
            return 275
        case .locallyApprovedAllow:
            return 300
        case .accountabilityApprovedAllow:
            return 400
        }
    }
}

struct AdultProtectionDomainRule: Identifiable, Codable, Hashable {
    var id: String
    var domain: AdultProtectionDomain
    var action: AdultProtectionRuleAction
    var matchScope: AdultProtectionDomainMatchScope
    var source: AdultProtectionRuleSource
    var effectiveFrom: Date?
    var expiresAt: Date?

    func isActive(at date: Date) -> Bool {
        if let effectiveFrom = effectiveFrom, date < effectiveFrom {
            return false
        }
        if let expiresAt = expiresAt, date >= expiresAt {
            return false
        }
        return true
    }

    fileprivate func matches(_ candidate: AdultProtectionDomain) -> Bool {
        switch matchScope {
        case .exact:
            return candidate == domain
        case .domainAndSubdomains:
            return candidate.isEqualToOrSubdomain(of: domain)
        }
    }
}

enum AdultProtectionRuleDisposition: String, Codable, Equatable {
    case allow
    case block
    case noMatchingRule
}

struct AdultProtectionRuleDecision: Codable, Equatable {
    var disposition: AdultProtectionRuleDisposition
    var matchedRuleID: String?
    var matchedRuleSource: AdultProtectionRuleSource?
    var evaluatedAt: Date

    static func noMatch(at date: Date) -> AdultProtectionRuleDecision {
        AdultProtectionRuleDecision(
            disposition: .noMatchingRule,
            matchedRuleID: nil,
            matchedRuleSource: nil,
            evaluatedAt: date
        )
    }
}

protocol AdultProtectionRuleEvaluating {
    func evaluate(
        domainInput: String,
        rules: [AdultProtectionDomainRule],
        at date: Date
    ) throws -> AdultProtectionRuleDecision
}

struct AdultProtectionRuleEngine: AdultProtectionRuleEvaluating {
    private let normalizer: AdultProtectionDomainNormalizing

    init(normalizer: AdultProtectionDomainNormalizing = AdultProtectionDomainNormalizer()) {
        self.normalizer = normalizer
    }

    func evaluate(
        domainInput: String,
        rules: [AdultProtectionDomainRule],
        at date: Date = Date()
    ) throws -> AdultProtectionRuleDecision {
        let candidate = try normalizer.normalize(domainInput)
        let matches = rules
            .filter { $0.isActive(at: date) && $0.matches(candidate) }
            .sorted(by: Self.hasHigherPrecedence)

        guard let winner = matches.first else {
            return .noMatch(at: date)
        }
        return AdultProtectionRuleDecision(
            disposition: winner.action == .allow ? .allow : .block,
            matchedRuleID: winner.id,
            matchedRuleSource: winner.source,
            evaluatedAt: date
        )
    }

    private static func hasHigherPrecedence(
        _ lhs: AdultProtectionDomainRule,
        _ rhs: AdultProtectionDomainRule
    ) -> Bool {
        if lhs.domain.labelCount != rhs.domain.labelCount {
            return lhs.domain.labelCount > rhs.domain.labelCount
        }
        if lhs.source.precedence != rhs.source.precedence {
            return lhs.source.precedence > rhs.source.precedence
        }
        if lhs.matchScope != rhs.matchScope {
            return lhs.matchScope == .exact
        }
        if lhs.action != rhs.action {
            // An explicit allow is the final tie-breaker for the same host,
            // scope, and trust source.
            return lhs.action == .allow
        }
        return lhs.id < rhs.id
    }
}

// MARK: - Accountability approvals

enum AdultProtectionApprovalSubject: String, Codable, CaseIterable {
    case falsePositiveAllowRequest
    case disableRequest
}

enum AdultProtectionAccountabilityApprovalStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case denied
    case revoked
    case expired
}

enum AdultProtectionAccountabilityDecision: String, Codable {
    case approve
    case deny
}

struct AdultProtectionAccountabilityApproval: Identifiable, Codable, Equatable {
    var id: String
    var subject: AdultProtectionApprovalSubject
    var subjectID: String
    var status: AdultProtectionAccountabilityApprovalStatus
    var requestedAt: Date
    var expiresAt: Date
    var decidedAt: Date?
    var validUntil: Date?
    var approverReference: String?

    func effectiveStatus(at date: Date) -> AdultProtectionAccountabilityApprovalStatus {
        if status == .pending && date >= expiresAt {
            return .expired
        }
        if status == .approved,
           let validUntil = validUntil,
           date >= validUntil {
            return .expired
        }
        return status
    }

    func approves(
        subject expectedSubject: AdultProtectionApprovalSubject,
        subjectID expectedSubjectID: String,
        at date: Date
    ) -> Bool {
        subject == expectedSubject
            && subjectID == expectedSubjectID
            && effectiveStatus(at: date) == .approved
    }
}

enum AdultProtectionAccountabilityApprovalError: String, Error, Codable {
    case requestIsNotPending
    case requestExpired
    case missingApproverReference
    case invalidValidityWindow
}

struct AdultProtectionAccountabilityApprovalService {
    func decide(
        _ approval: AdultProtectionAccountabilityApproval,
        decision: AdultProtectionAccountabilityDecision,
        approverReference: String,
        validUntil: Date?,
        at date: Date = Date()
    ) throws -> AdultProtectionAccountabilityApproval {
        guard approval.status == .pending else {
            throw AdultProtectionAccountabilityApprovalError.requestIsNotPending
        }
        guard date < approval.expiresAt else {
            throw AdultProtectionAccountabilityApprovalError.requestExpired
        }

        let normalizedApproverReference = approverReference.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedApproverReference.isEmpty else {
            throw AdultProtectionAccountabilityApprovalError.missingApproverReference
        }
        if decision == .approve,
           let validUntil = validUntil,
           validUntil <= date {
            throw AdultProtectionAccountabilityApprovalError.invalidValidityWindow
        }

        var updated = approval
        updated.status = decision == .approve ? .approved : .denied
        updated.decidedAt = date
        updated.validUntil = decision == .approve ? validUntil : nil
        updated.approverReference = normalizedApproverReference
        return updated
    }

    func revoke(
        _ approval: AdultProtectionAccountabilityApproval,
        at date: Date = Date()
    ) -> AdultProtectionAccountabilityApproval {
        var updated = approval
        if approval.effectiveStatus(at: date) == .approved {
            updated.status = .revoked
            updated.decidedAt = date
        }
        return updated
    }
}

// MARK: - False-positive allow requests

enum AdultProtectionAllowReason: String, Codable, CaseIterable {
    case incorrectlyCategorized
    case education
    case work
    case health
    case ministry
    case otherLegitimateUse
}

enum AdultProtectionAllowRequestStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case denied
    case cancelled
    case expired
}

struct AdultProtectionAllowRequest: Identifiable, Codable, Equatable {
    var id: String
    var domain: AdultProtectionDomain
    var requestedScope: AdultProtectionDomainMatchScope
    var reason: AdultProtectionAllowReason
    var modeAtRequest: AdultProtectionMode
    var status: AdultProtectionAllowRequestStatus
    var requestedAt: Date
    var expiresAt: Date
    var reviewedAt: Date?
    var accountabilityApprovalID: String?

    func effectiveStatus(at date: Date) -> AdultProtectionAllowRequestStatus {
        if status == .pending && date >= expiresAt {
            return .expired
        }
        return status
    }
}

enum AdultProtectionAllowReviewDecision: String, Codable {
    case approve
    case deny
}

enum AdultProtectionAllowRequestError: String, Error, Codable {
    case requestIsNotPending
    case requestExpired
    case accountabilityApprovalRequired
    case accountabilityApprovalInvalid
    case invalidRuleExpiration
}

struct AdultProtectionAllowReviewResult: Codable, Equatable {
    var request: AdultProtectionAllowRequest
    var approvedRule: AdultProtectionDomainRule?
}

struct AdultProtectionAllowRequestService {
    func review(
        _ request: AdultProtectionAllowRequest,
        decision: AdultProtectionAllowReviewDecision,
        accountabilityApproval: AdultProtectionAccountabilityApproval?,
        ruleExpiresAt: Date?,
        at date: Date = Date()
    ) throws -> AdultProtectionAllowReviewResult {
        guard request.status == .pending else {
            throw AdultProtectionAllowRequestError.requestIsNotPending
        }
        guard date < request.expiresAt else {
            throw AdultProtectionAllowRequestError.requestExpired
        }
        if let ruleExpiresAt = ruleExpiresAt, ruleExpiresAt <= date {
            throw AdultProtectionAllowRequestError.invalidRuleExpiration
        }

        let policy = AdultProtectionModePolicy.recommended(for: request.modeAtRequest)
        var approvalID: String?
        if decision == .approve && policy.allowRequestsRequireAccountabilityApproval {
            guard let approval = accountabilityApproval else {
                throw AdultProtectionAllowRequestError.accountabilityApprovalRequired
            }
            guard approval.approves(
                subject: .falsePositiveAllowRequest,
                subjectID: request.id,
                at: date
            ) else {
                throw AdultProtectionAllowRequestError.accountabilityApprovalInvalid
            }
            approvalID = approval.id
        }

        var reviewedRequest = request
        reviewedRequest.status = decision == .approve ? .approved : .denied
        reviewedRequest.reviewedAt = date
        reviewedRequest.accountabilityApprovalID = approvalID

        guard decision == .approve else {
            return AdultProtectionAllowReviewResult(
                request: reviewedRequest,
                approvedRule: nil
            )
        }

        let source: AdultProtectionRuleSource =
            policy.allowRequestsRequireAccountabilityApproval
            ? .accountabilityApprovedAllow
            : .locallyApprovedAllow
        let rule = AdultProtectionDomainRule(
            id: "allow-request:" + request.id,
            domain: request.domain,
            action: .allow,
            matchScope: request.requestedScope,
            source: source,
            effectiveFrom: date,
            expiresAt: ruleExpiresAt
        )
        return AdultProtectionAllowReviewResult(
            request: reviewedRequest,
            approvedRule: rule
        )
    }

    func cancel(
        _ request: AdultProtectionAllowRequest,
        at date: Date = Date()
    ) -> AdultProtectionAllowRequest {
        var updated = request
        if request.effectiveStatus(at: date) == .pending {
            updated.status = .cancelled
            updated.reviewedAt = date
        }
        return updated
    }
}

// MARK: - Delayed disable requests

enum AdultProtectionDisableReason: String, Codable, CaseIterable {
    case changeProtectionMode
    case troubleshooting
    case falsePositiveImpact
    case noLongerNeeded
    case other
}

enum AdultProtectionDisableRequestStatus: String, Codable, CaseIterable {
    case pending
    case cancelled
    case executed
    case denied
    case expired
}

struct AdultProtectionDisableRequest: Identifiable, Codable, Equatable {
    var id: String
    var configurationID: String
    var modeAtRequest: AdultProtectionMode
    var reason: AdultProtectionDisableReason
    var status: AdultProtectionDisableRequestStatus
    var requestedAt: Date
    var earliestExecutionAt: Date
    var expiresAt: Date
    var accountabilityApprovalID: String?
    var resolvedAt: Date?
}

enum AdultProtectionDisableEligibilityState: String, Codable, Equatable {
    case waitingForDelay
    case awaitingAccountabilityApproval
    case eligible
    case cancelled
    case executed
    case denied
    case expired
}

struct AdultProtectionDisableEligibility: Codable, Equatable {
    var state: AdultProtectionDisableEligibilityState
    var canExecute: Bool
    var remainingDelay: TimeInterval
    var evaluatedAt: Date
}

enum AdultProtectionDisableRequestError: String, Error, Codable {
    case notEligible
}

struct AdultProtectionDisableRequestService {
    var requestLifetimeAfterDelay: TimeInterval = 7 * 24 * 60 * 60

    func makeRequest(
        id: String,
        configuration: AdultProtectionConfiguration,
        reason: AdultProtectionDisableReason,
        at date: Date = Date()
    ) -> AdultProtectionDisableRequest {
        let policy = AdultProtectionModePolicy.recommended(for: configuration.mode)
        let earliestExecutionAt = date.addingTimeInterval(
            max(0, policy.minimumDisableDelay)
        )
        return AdultProtectionDisableRequest(
            id: id,
            configurationID: configuration.id,
            modeAtRequest: configuration.mode,
            reason: reason,
            status: .pending,
            requestedAt: date,
            earliestExecutionAt: earliestExecutionAt,
            expiresAt: earliestExecutionAt.addingTimeInterval(
                max(0, requestLifetimeAfterDelay)
            ),
            accountabilityApprovalID: nil,
            resolvedAt: nil
        )
    }

    func evaluate(
        _ request: AdultProtectionDisableRequest,
        accountabilityApproval: AdultProtectionAccountabilityApproval?,
        at date: Date = Date()
    ) -> AdultProtectionDisableEligibility {
        switch request.status {
        case .cancelled:
            return result(.cancelled, canExecute: false, remaining: 0, at: date)
        case .executed:
            return result(.executed, canExecute: false, remaining: 0, at: date)
        case .denied:
            return result(.denied, canExecute: false, remaining: 0, at: date)
        case .expired:
            return result(.expired, canExecute: false, remaining: 0, at: date)
        case .pending:
            break
        }

        if date >= request.expiresAt {
            return result(.expired, canExecute: false, remaining: 0, at: date)
        }
        if date < request.earliestExecutionAt {
            return result(
                .waitingForDelay,
                canExecute: false,
                remaining: request.earliestExecutionAt.timeIntervalSince(date),
                at: date
            )
        }

        let policy = AdultProtectionModePolicy.recommended(for: request.modeAtRequest)
        if policy.disableRequestsRequireAccountabilityApproval {
            guard let approval = accountabilityApproval,
                  approval.approves(
                    subject: .disableRequest,
                    subjectID: request.id,
                    at: date
                  ) else {
                return result(
                    .awaitingAccountabilityApproval,
                    canExecute: false,
                    remaining: 0,
                    at: date
                )
            }
        }

        return result(.eligible, canExecute: true, remaining: 0, at: date)
    }

    func markExecuted(
        _ request: AdultProtectionDisableRequest,
        accountabilityApproval: AdultProtectionAccountabilityApproval?,
        at date: Date = Date()
    ) throws -> AdultProtectionDisableRequest {
        let eligibility = evaluate(
            request,
            accountabilityApproval: accountabilityApproval,
            at: date
        )
        guard eligibility.canExecute else {
            throw AdultProtectionDisableRequestError.notEligible
        }

        var updated = request
        updated.status = .executed
        updated.resolvedAt = date
        let policy = AdultProtectionModePolicy.recommended(for: request.modeAtRequest)
        updated.accountabilityApprovalID =
            policy.disableRequestsRequireAccountabilityApproval
            ? accountabilityApproval?.id
            : nil
        return updated
    }

    func cancel(
        _ request: AdultProtectionDisableRequest,
        at date: Date = Date()
    ) -> AdultProtectionDisableRequest {
        var updated = request
        if request.status == .pending {
            updated.status = .cancelled
            updated.resolvedAt = date
        }
        return updated
    }

    private func result(
        _ state: AdultProtectionDisableEligibilityState,
        canExecute: Bool,
        remaining: TimeInterval,
        at date: Date
    ) -> AdultProtectionDisableEligibility {
        AdultProtectionDisableEligibility(
            state: state,
            canExecute: canExecute,
            remainingDelay: max(0, remaining),
            evaluatedAt: date
        )
    }
}

// MARK: - Signed rule envelopes

enum AdultProtectionSignatureAlgorithm: String, Codable, CaseIterable {
    case ed25519
    case p256SHA256
    case rsaPSSSHA256
}

struct AdultProtectionSignedRuleMetadata: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var ruleSetIdentifier: String
    var ruleSetVersion: Int
    var issuedAt: Date
    var notBefore: Date
    var expiresAt: Date
    var keyIdentifier: String
    var signatureAlgorithm: AdultProtectionSignatureAlgorithm
    var payloadContentType: String
    var payloadDigest: Data
    var ruleCount: Int
}

struct AdultProtectionSignedRuleEnvelope: Codable, Equatable {
    var metadata: AdultProtectionSignedRuleMetadata
    var payload: Data
    var signature: Data
}

struct AdultProtectionRulePayload: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var ruleSetIdentifier: String
    var ruleSetVersion: Int
    var rules: [AdultProtectionDomainRule]
}

protocol AdultProtectionRuleEnvelopeSignatureVerifying {
    /// Implementations must authenticate both metadata and payload. Public-key
    /// material is supplied by the implementation or its dependency container.
    func verify(_ envelope: AdultProtectionSignedRuleEnvelope) throws -> Bool
}

enum AdultProtectionRuleEnvelopeValidationFailure: String, Codable, CaseIterable {
    case unsupportedEnvelopeSchema
    case invalidMetadata
    case notYetValid
    case expired
    case rollbackRejected
    case payloadTooLarge
    case missingSignature
    case missingPayloadDigest
    case signatureVerificationUnavailable
    case signatureRejected
    case payloadDecodingFailed
    case unsupportedPayloadSchema
    case payloadMetadataMismatch
    case ruleCountMismatch
    case duplicateRuleIdentifier
    case duplicateRuleDefinition
    case invalidRuleSource
}

enum AdultProtectionRuleEnvelopeValidationStatus: String, Codable {
    case accepted
    case rejected
}

struct AdultProtectionRuleEnvelopeValidationContext: Codable, Equatable {
    var minimumAcceptedRuleSetVersion: Int?
    var maximumPayloadBytes: Int

    static let production = AdultProtectionRuleEnvelopeValidationContext(
        minimumAcceptedRuleSetVersion: nil,
        maximumPayloadBytes: 5 * 1_024 * 1_024
    )
}

struct AdultProtectionRuleEnvelopeValidationResult: Codable, Equatable {
    var status: AdultProtectionRuleEnvelopeValidationStatus
    var failures: [AdultProtectionRuleEnvelopeValidationFailure]
    var acceptedPayload: AdultProtectionRulePayload?
    var validatedAt: Date

    var isAccepted: Bool {
        status == .accepted && failures.isEmpty && acceptedPayload != nil
    }
}

struct AdultProtectionRuleEnvelopeValidator {
    private let verifier: AdultProtectionRuleEnvelopeSignatureVerifying
    private let decoder: JSONDecoder

    init(
        verifier: AdultProtectionRuleEnvelopeSignatureVerifying,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.verifier = verifier
        self.decoder = decoder
    }

    func validate(
        _ envelope: AdultProtectionSignedRuleEnvelope,
        context: AdultProtectionRuleEnvelopeValidationContext = .production,
        at date: Date = Date()
    ) -> AdultProtectionRuleEnvelopeValidationResult {
        var failures = metadataFailures(
            for: envelope,
            context: context,
            at: date
        )
        guard failures.isEmpty else {
            return rejected(failures, at: date)
        }

        do {
            guard try verifier.verify(envelope) else {
                return rejected([.signatureRejected], at: date)
            }
        } catch {
            return rejected([.signatureVerificationUnavailable], at: date)
        }

        let payload: AdultProtectionRulePayload
        do {
            payload = try decoder.decode(
                AdultProtectionRulePayload.self,
                from: envelope.payload
            )
        } catch {
            return rejected([.payloadDecodingFailed], at: date)
        }

        if payload.schemaVersion != AdultProtectionRulePayload.currentSchemaVersion {
            failures.append(.unsupportedPayloadSchema)
        }
        if payload.ruleSetIdentifier != envelope.metadata.ruleSetIdentifier
            || payload.ruleSetVersion != envelope.metadata.ruleSetVersion {
            failures.append(.payloadMetadataMismatch)
        }
        if payload.rules.count != envelope.metadata.ruleCount {
            failures.append(.ruleCountMismatch)
        }
        if Set(payload.rules.map(\.id)).count != payload.rules.count {
            failures.append(.duplicateRuleIdentifier)
        }
        let definitions = payload.rules.map {
            $0.domain.rawValue
                + "|" + $0.matchScope.rawValue
                + "|" + $0.action.rawValue
                + "|" + $0.source.rawValue
        }
        if Set(definitions).count != definitions.count {
            failures.append(.duplicateRuleDefinition)
        }
        if payload.rules.contains(where: { $0.source != .signedRemote }) {
            failures.append(.invalidRuleSource)
        }

        guard failures.isEmpty else {
            return rejected(failures, at: date)
        }
        return AdultProtectionRuleEnvelopeValidationResult(
            status: .accepted,
            failures: [],
            acceptedPayload: payload,
            validatedAt: date
        )
    }

    private func metadataFailures(
        for envelope: AdultProtectionSignedRuleEnvelope,
        context: AdultProtectionRuleEnvelopeValidationContext,
        at date: Date
    ) -> [AdultProtectionRuleEnvelopeValidationFailure] {
        let metadata = envelope.metadata
        var failures: [AdultProtectionRuleEnvelopeValidationFailure] = []

        if metadata.schemaVersion != AdultProtectionSignedRuleMetadata.currentSchemaVersion {
            failures.append(.unsupportedEnvelopeSchema)
        }
        if metadata.ruleSetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || metadata.keyIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || metadata.payloadContentType != "application/json"
            || metadata.ruleSetVersion < 0
            || metadata.ruleCount < 0
            || metadata.issuedAt > metadata.notBefore
            || metadata.notBefore >= metadata.expiresAt {
            failures.append(.invalidMetadata)
        }
        if date < metadata.notBefore {
            failures.append(.notYetValid)
        }
        if date >= metadata.expiresAt {
            failures.append(.expired)
        }
        if let minimumVersion = context.minimumAcceptedRuleSetVersion,
           metadata.ruleSetVersion < minimumVersion {
            failures.append(.rollbackRejected)
        }
        if context.maximumPayloadBytes <= 0
            || envelope.payload.count > context.maximumPayloadBytes {
            failures.append(.payloadTooLarge)
        }
        if envelope.signature.isEmpty {
            failures.append(.missingSignature)
        }
        if metadata.payloadDigest.isEmpty {
            failures.append(.missingPayloadDigest)
        }
        return failures
    }

    private func rejected(
        _ failures: [AdultProtectionRuleEnvelopeValidationFailure],
        at date: Date
    ) -> AdultProtectionRuleEnvelopeValidationResult {
        AdultProtectionRuleEnvelopeValidationResult(
            status: .rejected,
            failures: Array(Set(failures)).sorted { $0.rawValue < $1.rawValue },
            acceptedPayload: nil,
            validatedAt: date
        )
    }
}

// MARK: - Capability truth

enum AdultProtectionCapabilityLayer: String, Codable, CaseIterable {
    case screenTime
    case safariContentBlocker
    case networkFilter
}

enum AdultProtectionCapabilityImplementationState: String, Codable {
    case includedInCurrentBuild
    case notIncludedInCurrentBuild
    case unsupportedOnDevice
}

enum AdultProtectionCapabilityRuntimeState: String, Codable {
    case unavailable
    case authorizationRequired
    case ready
    case active
}

enum AdultProtectionCoverageScope: String, Codable, CaseIterable {
    case selectedApplications
    case selectedApplicationCategories
    case selectedWebDomains
    case appleAutomaticAdultWebContentDuringActivePolicy
    case safariPageContent
    case deviceNetworkTraffic
}

struct AdultProtectionCapabilityTruth: Codable, Equatable {
    var layer: AdultProtectionCapabilityLayer
    var implementationState: AdultProtectionCapabilityImplementationState
    var runtimeState: AdultProtectionCapabilityRuntimeState
    var coverageScopes: [AdultProtectionCoverageScope]
    var title: String
    var factualDetail: String

    var canCurrentlyEnforce: Bool {
        implementationState == .includedInCurrentBuild
            && (runtimeState == .ready || runtimeState == .active)
    }
}

struct AdultProtectionCapabilitySnapshot: Codable, Equatable {
    var generatedAt: Date
    var capabilities: [AdultProtectionCapabilityTruth]

    func capability(
        for layer: AdultProtectionCapabilityLayer
    ) -> AdultProtectionCapabilityTruth? {
        capabilities.first { $0.layer == layer }
    }
}

protocol AdultProtectionCapabilityTruthProviding {
    func currentSnapshot(
        screenTimeAuthorization: ScreenTimeAuthorizationState,
        screenTimePolicyActive: Bool,
        at date: Date
    ) -> AdultProtectionCapabilitySnapshot
}

struct CurrentBuildAdultProtectionCapabilityProvider:
    AdultProtectionCapabilityTruthProviding {
    var safariRuntimeState: AdultProtectionCapabilityRuntimeState =
        .authorizationRequired

    func currentSnapshot(
        screenTimeAuthorization: ScreenTimeAuthorizationState,
        screenTimePolicyActive: Bool,
        at date: Date = Date()
    ) -> AdultProtectionCapabilitySnapshot {
        let screenTimeRuntime: AdultProtectionCapabilityRuntimeState
        switch screenTimeAuthorization {
        case .approved, .approvedWithDataAccess:
            screenTimeRuntime = screenTimePolicyActive ? .active : .ready
        case .notDetermined, .denied:
            screenTimeRuntime = .authorizationRequired
        case .unsupported:
            screenTimeRuntime = .unavailable
        }

        return AdultProtectionCapabilitySnapshot(
            generatedAt: date,
            capabilities: [
                AdultProtectionCapabilityTruth(
                    layer: .screenTime,
                    implementationState: screenTimeAuthorization == .unsupported
                        ? .unsupportedOnDevice
                        : .includedInCurrentBuild,
                    runtimeState: screenTimeRuntime,
                    coverageScopes: [
                        .selectedApplications,
                        .selectedApplicationCategories,
                        .selectedWebDomains,
                        .appleAutomaticAdultWebContentDuringActivePolicy
                    ],
                    title: "Screen Time protection",
                    factualDetail: "Can apply Apple's Screen Time controls to selected apps, categories, and web domains while an active policy is enforced."
                ),
                AdultProtectionCapabilityTruth(
                    layer: .safariContentBlocker,
                    implementationState: .includedInCurrentBuild,
                    runtimeState: safariRuntimeState,
                    coverageScopes: [.safariPageContent],
                    title: "Safari page protection",
                    factualDetail: "The included Safari content blocker can enforce locally configured domain rules in Safari when the user enables the extension."
                ),
                AdultProtectionCapabilityTruth(
                    layer: .networkFilter,
                    implementationState: .notIncludedInCurrentBuild,
                    runtimeState: .unavailable,
                    coverageScopes: [],
                    title: "Network protection unavailable",
                    factualDetail: "No network filtering extension is included in this build."
                )
            ]
        )
    }
}

// MARK: - Privacy-safe event aggregates

enum AdultProtectionEventKind: String, Codable, CaseIterable {
    case blockedAttempt
    case allowedByException
    case disableRequested
    case accountabilityApprovalRequested
    case protectionHealthChanged
    case ruleEnvelopeRejected
    case protectionInactive
}

enum AdultProtectionEventSurface: String, Codable, CaseIterable {
    case policyEngine
    case screenTime
    case safari
    case network
}

struct AdultProtectionPrivacySafeEvent: Codable, Equatable {
    var occurredAt: Date
    var kind: AdultProtectionEventKind
    var mode: AdultProtectionMode
    var surface: AdultProtectionEventSurface
    var duration: TimeInterval

    init(
        occurredAt: Date,
        kind: AdultProtectionEventKind,
        mode: AdultProtectionMode,
        surface: AdultProtectionEventSurface,
        duration: TimeInterval = 0
    ) {
        self.occurredAt = occurredAt
        self.kind = kind
        self.mode = mode
        self.surface = surface
        self.duration = duration
    }
}

struct AdultProtectionEventAggregateKey: Codable, Hashable {
    var dayStartUTC: Date
    var mode: AdultProtectionMode
    var surface: AdultProtectionEventSurface
}

struct AdultProtectionEventAggregate: Codable, Equatable {
    var key: AdultProtectionEventAggregateKey
    var blockedAttemptCount: Int
    var allowedByExceptionCount: Int
    var disableRequestCount: Int
    var accountabilityApprovalRequestCount: Int
    var protectionHealthChangeCount: Int
    var rejectedRuleEnvelopeCount: Int
    var protectionInactiveDuration: TimeInterval
}

protocol AdultProtectionEventAggregating {
    func aggregate(
        _ events: [AdultProtectionPrivacySafeEvent]
    ) -> [AdultProtectionEventAggregate]
}

struct AdultProtectionEventAggregator: AdultProtectionEventAggregating {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    func aggregate(
        _ events: [AdultProtectionPrivacySafeEvent]
    ) -> [AdultProtectionEventAggregate] {
        var aggregates: [AdultProtectionEventAggregateKey: AdultProtectionEventAggregate] = [:]

        for event in events {
            let key = AdultProtectionEventAggregateKey(
                dayStartUTC: utcCalendar.startOfDay(for: event.occurredAt),
                mode: event.mode,
                surface: event.surface
            )
            var aggregate = aggregates[key] ?? AdultProtectionEventAggregate(
                key: key,
                blockedAttemptCount: 0,
                allowedByExceptionCount: 0,
                disableRequestCount: 0,
                accountabilityApprovalRequestCount: 0,
                protectionHealthChangeCount: 0,
                rejectedRuleEnvelopeCount: 0,
                protectionInactiveDuration: 0
            )

            switch event.kind {
            case .blockedAttempt:
                aggregate.blockedAttemptCount = incrementing(aggregate.blockedAttemptCount)
            case .allowedByException:
                aggregate.allowedByExceptionCount = incrementing(
                    aggregate.allowedByExceptionCount
                )
            case .disableRequested:
                aggregate.disableRequestCount = incrementing(aggregate.disableRequestCount)
            case .accountabilityApprovalRequested:
                aggregate.accountabilityApprovalRequestCount = incrementing(
                    aggregate.accountabilityApprovalRequestCount
                )
            case .protectionHealthChanged:
                aggregate.protectionHealthChangeCount = incrementing(
                    aggregate.protectionHealthChangeCount
                )
            case .ruleEnvelopeRejected:
                aggregate.rejectedRuleEnvelopeCount = incrementing(
                    aggregate.rejectedRuleEnvelopeCount
                )
            case .protectionInactive:
                let eventDuration = event.duration.isFinite
                    ? min(max(0, event.duration), 24 * 60 * 60)
                    : 0
                aggregate.protectionInactiveDuration = min(
                    24 * 60 * 60,
                    aggregate.protectionInactiveDuration + eventDuration
                )
            }
            aggregates[key] = aggregate
        }

        return aggregates.values.sorted {
            if $0.key.dayStartUTC != $1.key.dayStartUTC {
                return $0.key.dayStartUTC < $1.key.dayStartUTC
            }
            if $0.key.mode.rawValue != $1.key.mode.rawValue {
                return $0.key.mode.rawValue < $1.key.mode.rawValue
            }
            return $0.key.surface.rawValue < $1.key.surface.rawValue
        }
    }

    private func incrementing(_ value: Int) -> Int {
        value == Int.max ? Int.max : value + 1
    }
}

// MARK: - Screen Time policy interoperability

struct AdultProtectionScreenTimePolicyAdapter {
    /// Produces desired policy state for ScreenTimePolicyEngine. Applying the
    /// returned value to Apple's APIs remains the enforcement layer's job.
    func makeDesiredPolicy(
        from configuration: AdultProtectionConfiguration
    ) -> ProtectionPolicy {
        let source: ProtectionSourceKind = configuration.mode == .accountability
            ? .accountability
            : .permanentProtection
        let strictness: ProtectionStrictness
        switch configuration.mode {
        case .standard:
            strictness = .intentional
        case .strict:
            strictness = .locked
        case .accountability:
            strictness = .accountabilityLocked
        }

        return ProtectionPolicy(
            id: "adult-protection:" + configuration.id,
            source: source,
            strictness: strictness,
            selectionReference: configuration.selectionReference,
            blocksAdultWebContent:
                configuration.requestsAppleAutomaticAdultWebContentFilter,
            isEnabled: configuration.isEnabled,
            startsAt: configuration.activatedAt,
            endsAt: nil,
            temporaryExceptionForPolicyID: nil,
            createdAt: configuration.activatedAt ?? configuration.updatedAt,
            updatedAt: configuration.updatedAt
        )
    }
}
