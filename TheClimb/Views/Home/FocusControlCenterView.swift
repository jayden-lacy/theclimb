import SwiftUI
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

struct FocusControlCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel

    private let runtime = FocusSessionRuntimeService()
    private let adultRuntime = AdultProtectionRuntimeService()
    private let safariService = SafariContentBlockerService()

    @State private var domain = FocusSessionDomainEnvelope()
    @State private var adultProtection = AdultProtectionRuntimeEnvelope.empty()
    @State private var safariProtection = SafariProtectionSnapshot(
        status: .checking,
        lastSuccessfulRuleUpdate: nil,
        configuredDomainCount: 0,
        checkedAt: Date()
    )
    @State private var selectedPurpose: FocusPurpose = .prayer
    @State private var customPurposeName = ""
    @State private var selectedDuration = 25
    @State private var selectedStrictness: FocusStrictness = .intentional
    @State private var selectedAdultMode: AdultProtectionMode = .standard
    @State private var selectionMode: FocusSelectionMode = .blockSelected
    @State private var blocksAdultWebContent = FocusAdultContentFilterStore.isEnabled
    @State private var isStarting = false
    @State private var isUpdatingPermanentProtection = false
    @State private var errorMessage: String?
    @State private var showRhythmEditor = false
    @State private var showRhythmPause = false
    @State private var showBoundaryEditor = false
    @State private var showDurationEditor = false
    @State private var showBlockedDomainEditor = false
    @State private var showWebsiteReview = false
    @State private var showPermanentProtectionDisable = false
    @State private var sessionAwaitingExit: FocusSession?
    @State private var sessionAwaitingBreak: FocusSession?
#if canImport(FamilyControls) && os(iOS)
    @State private var showBlockedPicker = false
    @State private var showEssentialPicker = false
    @State private var blockedSelection = FamilyActivitySelection()
    @State private var essentialSelection = FamilyActivitySelection()
#endif

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    protectionStatus

                    if let activeSession {
                        ActiveGeneralFocusSection(
                            session: activeSession,
                            intentionalBreak: activeIntentionalBreak(for: activeSession),
                            onRequestBreak: {
                                sessionAwaitingBreak = activeSession
                            },
                            onEndBreak: { breakID in
                                endBreak(breakID, in: activeSession)
                            },
                            onRequestExit: {
                                sessionAwaitingExit = activeSession
                            }
                        )
                    } else {
                        quickStartSection
                    }

                    selectionSection
                    permanentProtectionSection
                    rhythmSection
                    boundarySection
                    historySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 48)
            }
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(Color.climbGreen)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await load()
        }
#if canImport(FamilyControls) && os(iOS)
        .familyActivityPicker(
            headerText: "Choose distractions to block during selected-app sessions.",
            footerText: "Selections stay private on this device.",
            isPresented: $showBlockedPicker,
            selection: $blockedSelection
        )
        .familyActivityPicker(
            headerText: "Choose the essential apps that should remain available.",
            footerText: "All other app categories are restricted during Essential Apps sessions.",
            isPresented: $showEssentialPicker,
            selection: $essentialSelection
        )
        .onChange(of: blockedSelection) { _, selection in
            ScreenTimeActivitySelectionStore.saveSelection(selection)
            viewModel.refreshClimbControlState()
        }
        .onChange(of: essentialSelection) { _, selection in
            EssentialAppsActivitySelectionStore.saveSelection(selection)
        }
#endif
        .sheet(isPresented: $showRhythmEditor) {
            FocusRhythmEditorView(
                usesEssentialApps: selectionMode == .allowEssentialApps,
                blocksAdultWebContent: blocksAdultWebContent
            ) { rhythm in
                try runtime.saveRhythm(rhythm)
                try reloadDomain()
            }
        }
        .sheet(isPresented: $showRhythmPause) {
            FocusRhythmPauseView { resumesAt, reason in
                try pauseRhythms(until: resumesAt, reason: reason)
            }
        }
        .sheet(isPresented: $showBoundaryEditor) {
            AppBoundaryEditorView(
                blocksAdultWebContent: blocksAdultWebContent
            ) { boundary in
                try runtime.saveBoundary(boundary)
                try reloadDomain()
            }
        }
        .sheet(isPresented: $showDurationEditor) {
            FocusDurationEditor(selectedMinutes: selectedDuration) { minutes in
                selectedDuration = minutes
            }
        }
        .sheet(isPresented: $showBlockedDomainEditor) {
            PermanentDomainRuleEditorView { domain in
                try addPermanentBlockedDomain(domain)
            }
        }
        .sheet(isPresented: $showPermanentProtectionDisable) {
            PermanentProtectionDisableView(
                mode: adultProtection.configuration?.mode ?? .standard
            ) { reason in
                try requestPermanentProtectionDisable(reason: reason)
            }
        }
        .sheet(isPresented: $showWebsiteReview) {
            PermanentWebsiteReviewView { domain, reason, expiresAt in
                try approveWebsiteReview(
                    domain: domain,
                    reason: reason,
                    expiresAt: expiresAt
                )
            }
        }
        .sheet(item: $sessionAwaitingExit) { session in
            FocusEarlyExitSheet(
                session: session,
                pendingRequest: pendingExitRequest(for: session)
            ) { reason in
                try requestEarlyExit(session, reason: reason)
            }
        }
        .sheet(item: $sessionAwaitingBreak) { session in
            IntentionalBreakSheet(session: session) { duration, reason in
                try startBreak(in: session, duration: duration, reason: reason)
            }
        }
        .alert(
            "Focus needs attention",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var activeSession: FocusSession? {
        domain.activeSessions.first(where: \.isActive)
    }

    private func activeIntentionalBreak(
        for session: FocusSession
    ) -> IntentionalBreak? {
        IntentionalBreakService().activeBreak(
            for: session.sourceID,
            in: domain.intentionalBreaks
        )
    }

    private func pendingExitRequest(
        for session: FocusSession
    ) -> FocusEarlyExitRequest? {
        domain.earlyExitRequests.first {
            $0.sessionID == session.id && $0.state == .pending
        }
    }

    private var protectionStatus: some View {
        HStack(spacing: 14) {
            Image(systemName: protectionStatusIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(protectionStatusColor)
                .frame(width: 38, height: 38)
                .background(
                    protectionStatusColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Screen Time")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)
                Text(protectionStatusTitle)
                    .font(ClimbTypography.sans(16, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
            }

            Spacer(minLength: 0)

            if viewModel.focusState != .authorized && viewModel.focusState != .active {
                Button("Allow") {
                    Task {
                        await viewModel.requestScreenTimeAuthorization()
                    }
                }
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbGreen)
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            FocusSectionTitle(
                eyebrow: "Start now",
                title: "Protect the next faithful step",
                detail: "The timer and restrictions end together."
            )

            Menu {
                ForEach(FocusPurpose.allCases, id: \.self) { purpose in
                    Button {
                        HapticFeedback.selection()
                        selectedPurpose = purpose
                    } label: {
                        Label(
                            purpose.title,
                            systemImage: purpose == selectedPurpose
                                ? "checkmark"
                                : "circle"
                        )
                    }
                }
            } label: {
                FocusChoiceRow(
                    title: "Purpose",
                    value: selectedPurpose.title,
                    systemImage: "scope"
                )
            }

            if selectedPurpose == .custom {
                TextField("Name this focus", text: $customPurposeName)
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(Color.climbMist)
                    .padding(15)
                    .background(
                        Color.climbSurfaceRaised,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([15, 25, 45, 60, 90], id: \.self) { minutes in
                        durationButton(minutes)
                    }
                    Button {
                        showDurationEditor = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.climbTextSecondary)
                            .frame(width: 44, height: 44)
                            .background(
                                Color.climbSurfaceRaised,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Custom duration")
                }
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(FocusStrictness.allCases, id: \.self) { strictness in
                        Button(strictness.title) {
                            selectedStrictness = strictness
                        }
                    }
                } label: {
                    FocusChoiceRow(
                        title: "Mode",
                        value: selectedStrictness.title,
                        systemImage: "lock.shield"
                    )
                }

                Menu {
                    Button("Block selected") {
                        selectionMode = .blockSelected
                    }
                    Button("Essential Apps") {
                        selectionMode = .allowEssentialApps
                    }
                } label: {
                    FocusChoiceRow(
                        title: "Access",
                        value: selectionMode.title,
                        systemImage: "apps.iphone"
                    )
                }
            }

            PrimaryActionButton(
                title: isStarting
                    ? "Starting focus"
                    : "Begin \(selectedDuration)-minute focus",
                systemImage: "play.fill",
                tint: .climbGreen,
                isDisabled: isStarting
            ) {
                startSession()
            }
        }
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            FocusSectionTitle(
                eyebrow: "Protection",
                title: "Choose what stays quiet",
                detail: "Selections are stored by Apple on this device."
            )

            VStack(spacing: 0) {
                FocusSettingsButton(
                    title: "Blocked distractions",
                    detail: blockedSelectionDetail,
                    systemImage: "nosign.app"
                ) {
#if canImport(FamilyControls) && os(iOS)
                    showBlockedPicker = true
#endif
                }

                FocusDivider()

                FocusSettingsButton(
                    title: "Essential Apps",
                    detail: essentialSelectionDetail,
                    systemImage: "checkmark.shield"
                ) {
#if canImport(FamilyControls) && os(iOS)
                    showEssentialPicker = true
#endif
                }

                FocusDivider()

                Toggle(isOn: $blocksAdultWebContent) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Adult website filter")
                            .font(ClimbTypography.sans(15, weight: .semibold))
                            .foregroundStyle(Color.climbMist)
                        Text("Uses Apple’s automatic filter only while these focus policies run.")
                            .font(ClimbTypography.sans(12, weight: .medium))
                            .foregroundStyle(Color.climbMuted)
                            .lineSpacing(2)
                    }
                }
                .tint(Color.climbGreen)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .onChange(of: blocksAdultWebContent) { _, enabled in
                    FocusAdultContentFilterStore.setEnabled(enabled)
                }
            }
            .background(
                Color.climbSurfaceRaised.opacity(0.70),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.climbHairline, lineWidth: 0.7)
            )
        }
    }

    private var rhythmSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                FocusSectionTitle(
                    eyebrow: "Rhythms",
                    title: "Return to focus automatically",
                    detail: "Up to two recurring windows in this build."
                )
                Spacer(minLength: 8)
                Button {
                    showRhythmEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.climbBackground)
                        .frame(width: 36, height: 36)
                        .background(Color.climbMist, in: Circle())
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(domain.rhythms.count >= 2)
                .opacity(domain.rhythms.count >= 2 ? 0.38 : 1)
                .accessibilityLabel("Add Focus Rhythm")
            }

            if let pause = activeRhythmPause {
                HStack(spacing: 12) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.climbGold)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rhythms paused")
                            .font(ClimbTypography.sans(14, weight: .semibold))
                            .foregroundStyle(Color.climbMist)
                        Text("Resume \(pause.resumesAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(ClimbTypography.sans(12, weight: .medium))
                            .foregroundStyle(Color.climbMuted)
                    }
                    Spacer(minLength: 0)
                    Button("Resume") {
                        resumeRhythms()
                    }
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbGold)
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(14)
                .background(
                    Color.climbGold.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            } else if !domain.rhythms.isEmpty {
                Button {
                    showRhythmPause = true
                } label: {
                    Label("Pause rhythms", systemImage: "pause")
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(Color.climbTextSecondary)
                }
                .buttonStyle(ScaleButtonStyle())
            }

            if domain.rhythms.isEmpty {
                Text("No rhythm scheduled")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(domain.rhythms) { rhythm in
                    FocusRhythmRow(rhythm: rhythm) {
                        removeRhythm(rhythm)
                    }
                }
            }
        }
    }

    private var permanentProtectionSection: some View {
        AlwaysOnProtectionSection(
            configuration: adultProtection.configuration,
            pendingDisableRequest: pendingDisableRequest,
            blockedRules: adultProtection.rules.filter {
                $0.action == .block && $0.source == .userAddedBlocked
            },
            safariProtection: safariProtection,
            selectedMode: $selectedAdultMode,
            isUpdating: isUpdatingPermanentProtection,
            onEnable: enablePermanentProtection,
            onAddBlockedDomain: { showBlockedDomainEditor = true },
            onReviewWebsite: { showWebsiteReview = true },
            onRemoveBlockedDomain: removePermanentBlockedDomain,
            onReloadSafari: reloadSafariProtection,
            onRequestDisable: {
                showPermanentProtectionDisable = true
            },
            onCancelDisable: cancelPermanentProtectionDisable,
            onExecuteDisable: executePermanentProtectionDisable
        )
    }

    private var pendingDisableRequest: AdultProtectionDisableRequest? {
        adultProtection.disableRequests
            .filter { $0.status == .pending && $0.expiresAt > Date() }
            .sorted { $0.requestedAt > $1.requestedAt }
            .first
    }

    private var historySection: some View {
        let report = attentionReport
        return VStack(alignment: .leading, spacing: 14) {
            FocusSectionTitle(
                eyebrow: "Last 7 days",
                title: report.recordCount == 0
                    ? "Your protected time starts here"
                    : "\(Int(report.protectedDuration / 60)) protected minutes",
                detail: report.recordCount == 0
                    ? "Completed focus sessions will appear here."
                    : "\(report.completedRecordCount) completed sessions across \(report.activeDayCount) active days."
            )

            if report.recordCount > 0 {
                HStack(spacing: 10) {
                    FocusReportMetric(
                        value: "\(Int(report.completionRate * 100))%",
                        label: "completed"
                    )
                    FocusReportMetric(
                        value: "\(Int(report.averageProtectedDuration / 60))m",
                        label: "average"
                    )
                    FocusReportMetric(
                        value: "\(Int(report.longestProtectedDuration / 60))m",
                        label: "longest"
                    )
                }
            }
        }
    }

    private var boundarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                FocusSectionTitle(
                    eyebrow: "Boundaries",
                    title: "Set a limit before the pull",
                    detail: "Selected distractions lock after their measured daily or weekly allowance."
                )
                Spacer(minLength: 8)
                Button {
                    showBoundaryEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.climbBackground)
                        .frame(width: 36, height: 36)
                        .background(Color.climbMist, in: Circle())
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(domain.boundaries.count >= 3)
                .opacity(domain.boundaries.count >= 3 ? 0.38 : 1)
                .accessibilityLabel("Add app boundary")
            }

            if domain.boundaries.isEmpty {
                Text("No app boundary configured")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(domain.boundaries) { boundary in
                    AppBoundaryRow(boundary: boundary) {
                        removeBoundary(boundary)
                    }
                }
            }
        }
    }

    private var attentionReport: AttentionReport {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end)
            ?? end.addingTimeInterval(-7 * 24 * 60 * 60)
        return AttentionReportService().report(
            from: domain.history.records,
            within: DateInterval(start: start, end: end)
        )
    }

    private var activeRhythmPause: FocusRhythmPause? {
        guard let pause = domain.rhythmPause,
              pause.isActive(at: Date()) else {
            return nil
        }
        return pause
    }

    private func durationButton(_ minutes: Int) -> some View {
        Button {
            HapticFeedback.selection()
            selectedDuration = minutes
        } label: {
            Text("\(minutes)")
                .font(
                    ClimbTypography.sans(15, weight: .semibold)
                        .monospacedDigit()
                )
                .foregroundStyle(
                    selectedDuration == minutes
                        ? Color.climbBackground
                        : Color.climbTextSecondary
                )
                .frame(width: 52, height: 44)
                .background(
                    selectedDuration == minutes
                        ? Color.climbMist
                        : Color.climbSurfaceRaised,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(minutes) minutes")
    }

    private var blockedSelectionDetail: String {
#if canImport(FamilyControls) && os(iOS)
        let count = blockedSelection.shieldableContentCount
        return count == 0 ? "Not chosen" : "\(count) selected"
#else
        return "Unavailable"
#endif
    }

    private var essentialSelectionDetail: String {
#if canImport(FamilyControls) && os(iOS)
        let count = essentialSelection.applicationTokens.count
        return count == 0 ? "Not chosen" : "\(count) allowed"
#else
        return "Unavailable"
#endif
    }

    private var protectionStatusTitle: String {
        switch viewModel.focusState {
        case .active:
            "Protection active"
        case .authorized:
            "Ready"
        case .permissionRequired:
            "Permission needed"
        case .selectionRequired:
            "Choose apps"
        case .denied:
            "Access denied"
        case .simulated:
            "Timer only"
        case .unavailable:
            "Unavailable"
        }
    }

    private var protectionStatusIcon: String {
        switch viewModel.focusState {
        case .active:
            "lock.shield.fill"
        case .authorized:
            "checkmark.shield"
        case .permissionRequired, .selectionRequired:
            "exclamationmark.shield"
        case .denied, .unavailable:
            "xmark.shield"
        case .simulated:
            "timer"
        }
    }

    private var protectionStatusColor: Color {
        switch viewModel.focusState {
        case .active, .authorized:
            .climbGreen
        case .permissionRequired, .selectionRequired, .simulated:
            .climbGold
        case .denied, .unavailable:
            .climbRed
        }
    }

    private func load() async {
        await viewModel.refreshScreenTimeAuthorization()
        safariProtection = await safariService.snapshot()
#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            blockedSelection = ScreenTimeActivitySelectionStore.loadSelection()
            essentialSelection = EssentialAppsActivitySelectionStore.loadSelection()
        }
#endif
        do {
            _ = try runtime.resumeRhythmsIfPauseExpired()
            domain = try runtime.reconcileExpiredSessions()
            try runtime.refreshRhythmPolicies()
            adultProtection = try adultRuntime.reapplyIfNeeded()
            selectedAdultMode = adultProtection.configuration?.mode ?? .standard
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadDomain() throws {
        domain = try runtime.loadState()
    }

    private func startSession() {
        guard !isStarting else { return }
        isStarting = true
        HapticFeedback.impact()
        let request = FocusSessionRequest(
            purpose: selectedPurpose,
            customPurposeName: selectedPurpose == .custom
                ? customPurposeName
                : nil,
            plannedDuration: TimeInterval(selectedDuration * 60),
            strictness: selectedStrictness,
            selectionReference: selectionMode == .blockSelected
                ? FocusSelectionReference(rawValue: ScreenTimeSelectionReference.defaultSelection)
                : nil,
            essentialAppsReference: selectionMode == .allowEssentialApps
                ? EssentialAppsSelectionReference(rawValue: "essential-apps-v1")
                : nil,
            blocksAdultWebContent: blocksAdultWebContent
        )

        Task {
            do {
                _ = try await runtime.start(request)
                try await MainActor.run {
                    try reloadDomain()
                    isStarting = false
                    HapticFeedback.success()
                }
            } catch {
                await MainActor.run {
                    isStarting = false
                    errorMessage = error.localizedDescription
                    HapticFeedback.impact(.medium)
                }
            }
        }
    }

    private func requestEarlyExit(
        _ session: FocusSession,
        reason: String?
    ) throws -> FocusEarlyExitResolution {
        do {
            let resolution = try runtime.requestEarlyExit(
                sessionID: session.id,
                reason: reason
            )
            try reloadDomain()
            if case .ended = resolution {
                sessionAwaitingExit = nil
                HapticFeedback.selection()
            }
            return resolution
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func startBreak(
        in session: FocusSession,
        duration: TimeInterval,
        reason: String?
    ) throws {
        do {
            _ = try runtime.startIntentionalBreak(
                sessionID: session.id,
                duration: duration,
                reason: reason
            )
            try reloadDomain()
            sessionAwaitingBreak = nil
            HapticFeedback.selection()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func endBreak(
        _ breakID: String,
        in session: FocusSession
    ) {
        do {
            _ = try runtime.endIntentionalBreak(
                breakID: breakID,
                sessionID: session.id
            )
            try reloadDomain()
            HapticFeedback.selection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeRhythm(_ rhythm: FocusRhythm) {
        do {
            try runtime.removeRhythm(id: rhythm.id)
            try reloadDomain()
            HapticFeedback.selection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pauseRhythms(
        until resumesAt: Date,
        reason: FocusRhythmPauseReason
    ) throws {
        do {
            domain = try runtime.pauseRhythms(
                until: resumesAt,
                reason: reason
            )
            HapticFeedback.selection()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func resumeRhythms() {
        do {
            domain = try runtime.resumeRhythms()
            HapticFeedback.selection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeBoundary(_ boundary: AppBoundary) {
        do {
            try runtime.removeBoundary(id: boundary.id)
            try reloadDomain()
            HapticFeedback.selection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enablePermanentProtection() {
        guard !isUpdatingPermanentProtection else { return }
        isUpdatingPermanentProtection = true
        HapticFeedback.impact()
        Task {
            do {
                let updated = try await adultRuntime.activate(mode: selectedAdultMode)
                let safari = await safariService.updateRules(from: updated.rules)
                await MainActor.run {
                    adultProtection = updated
                    safariProtection = safari
                    isUpdatingPermanentProtection = false
                    HapticFeedback.success()
                }
            } catch {
                await MainActor.run {
                    isUpdatingPermanentProtection = false
                    errorMessage = error.localizedDescription
                    HapticFeedback.impact(.medium)
                }
            }
        }
    }

    private func requestPermanentProtectionDisable(
        reason: AdultProtectionDisableReason
    ) throws {
        guard !isUpdatingPermanentProtection else { return }
        isUpdatingPermanentProtection = true
        do {
            let request = try adultRuntime.requestDisable(reason: reason)
            let eligibility = try adultRuntime.disableEligibility(requestID: request.id)
            adultProtection = eligibility.canExecute
                ? try adultRuntime.executeDisable(requestID: request.id)
                : try adultRuntime.loadState()
            isUpdatingPermanentProtection = false
            HapticFeedback.selection()
        } catch {
            isUpdatingPermanentProtection = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func cancelPermanentProtectionDisable() {
        guard let request = pendingDisableRequest else { return }
        do {
            adultProtection = try adultRuntime.cancelDisableRequest(requestID: request.id)
            HapticFeedback.selection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func executePermanentProtectionDisable() {
        guard let request = pendingDisableRequest else { return }
        do {
            adultProtection = try adultRuntime.executeDisable(requestID: request.id)
            HapticFeedback.selection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addPermanentBlockedDomain(_ domain: String) throws {
        adultProtection = try adultRuntime.addBlockedDomain(domain)
        Task {
            let updated = await safariService.updateRules(
                from: adultProtection.rules
            )
            await MainActor.run {
                safariProtection = updated
            }
        }
    }

    private func removePermanentBlockedDomain(
        _ rule: AdultProtectionDomainRule
    ) {
        do {
            adultProtection = try adultRuntime.removeBlockedDomain(ruleID: rule.id)
            Task {
                let updated = await safariService.updateRules(
                    from: adultProtection.rules
                )
                await MainActor.run {
                    safariProtection = updated
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func approveWebsiteReview(
        domain: String,
        reason: AdultProtectionAllowReason,
        expiresAt: Date?
    ) throws {
        let request = try adultRuntime.requestWebsiteReview(
            domain: domain,
            reason: reason
        )
        adultProtection = try adultRuntime.approveWebsiteReview(
            requestID: request.id,
            expiresAt: expiresAt
        )
        Task {
            let updated = await safariService.updateRules(
                from: adultProtection.rules
            )
            await MainActor.run {
                safariProtection = updated
            }
        }
    }

    private func reloadSafariProtection() {
        Task {
            let updated = await safariService.updateRules(
                from: adultProtection.rules
            )
            await MainActor.run {
                safariProtection = updated
            }
        }
    }
}

private struct AlwaysOnProtectionSection: View {
    let configuration: AdultProtectionConfiguration?
    let pendingDisableRequest: AdultProtectionDisableRequest?
    let blockedRules: [AdultProtectionDomainRule]
    let safariProtection: SafariProtectionSnapshot
    @Binding var selectedMode: AdultProtectionMode
    let isUpdating: Bool
    let onEnable: () -> Void
    let onAddBlockedDomain: () -> Void
    let onReviewWebsite: () -> Void
    let onRemoveBlockedDomain: (AdultProtectionDomainRule) -> Void
    let onReloadSafari: () -> Void
    let onRequestDisable: () -> Void
    let onCancelDisable: () -> Void
    let onExecuteDisable: () -> Void

    private var isActive: Bool {
        configuration?.isEnabled == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FocusSectionTitle(
                eyebrow: "Always on",
                title: isActive ? "Adult-site protection is active" : "Protect beyond a session",
                detail: "Uses Apple’s automatic adult-website filter through Screen Time. It does not claim device-wide network filtering."
            )

            if isActive {
                activeContent
            } else {
                inactiveContent
            }
        }
        .padding(18)
        .background(
            Color.climbSurfaceRaised.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isActive
                        ? Color.climbGreen.opacity(0.25)
                        : Color.climbHairline,
                    lineWidth: 0.8
                )
        )
    }

    private var inactiveContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Protection mode", selection: $selectedMode) {
                Text("Standard").tag(AdultProtectionMode.standard)
                Text("Strict").tag(AdultProtectionMode.strict)
            }
            .pickerStyle(.segmented)

            Text(
                selectedMode == .strict
                    ? "Strict mode adds a 24-hour wait before protection can be turned off."
                    : "Standard mode can be turned off immediately from this screen."
            )
            .font(ClimbTypography.sans(12, weight: .medium))
            .foregroundStyle(Color.climbMuted)
            .lineSpacing(2)

            PrimaryActionButton(
                title: isUpdating ? "Turning on protection" : "Turn on protection",
                systemImage: "lock.shield.fill",
                tint: .climbGreen,
                isDisabled: isUpdating
            ) {
                onEnable()
            }
        }
    }

    @ViewBuilder
    private var activeContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.climbGreen)
                .frame(width: 42, height: 42)
                .background(Color.climbGreen.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(configuration?.mode.title ?? "Protection")
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text("Apple Screen Time filter requested")
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
            }
            Spacer(minLength: 0)
        }

        SafariProtectionStatusRow(
            snapshot: safariProtection,
            onReload: onReloadSafari
        )

        VStack(spacing: 0) {
            Button {
                onAddBlockedDomain()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.climbGreen)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Block a website")
                            .font(ClimbTypography.sans(14, weight: .semibold))
                            .foregroundStyle(Color.climbMist)
                        Text("Adds the domain and its subdomains locally")
                            .font(ClimbTypography.sans(11, weight: .medium))
                            .foregroundStyle(Color.climbMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())

            Divider()
                .overlay(Color.climbHairline)

            Button {
                onReviewWebsite()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.climbGold)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Review a blocked website")
                            .font(ClimbTypography.sans(14, weight: .semibold))
                            .foregroundStyle(Color.climbMist)
                        Text("Create a private, time-limited exception")
                            .font(ClimbTypography.sans(11, weight: .medium))
                            .foregroundStyle(Color.climbMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())

            ForEach(blockedRules.sorted { $0.domain < $1.domain }) { rule in
                Divider()
                    .overlay(Color.climbHairline)
                HStack(spacing: 10) {
                    Text(rule.domain.rawValue)
                        .font(ClimbTypography.sans(13, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if rule.source == .userAddedBlocked {
                        Button(role: .destructive) {
                            onRemoveBlockedDomain(rule)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.climbMuted)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityLabel("Remove \(rule.domain.rawValue)")
                    } else {
                        Label("Built in", systemImage: "lock.fill")
                            .font(ClimbTypography.sans(10, weight: .semibold))
                            .foregroundStyle(Color.climbSage)
                            .labelStyle(.titleAndIcon)
                    }
                }
                .padding(.vertical, 5)
            }
        }

        if let request = pendingDisableRequest {
            pendingRequestContent(request)
        } else {
            Button(role: .destructive) {
                onRequestDisable()
            } label: {
                Text(
                    configuration?.mode == .strict
                        ? "Start 24-hour turn-off request"
                        : "Turn off protection"
                )
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Color.climbSurface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isUpdating)
        }
    }

    private func pendingRequestContent(
        _ request: AdultProtectionDisableRequest
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let remaining = max(
                    0,
                    request.earliestExecutionAt.timeIntervalSince(context.date)
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        remaining > 0
                            ? "Turn-off request is waiting"
                            : "Protection can now be turned off"
                    )
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                    Text(
                        remaining > 0
                            ? remainingText(remaining)
                            : "The required wait has ended."
                    )
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
                }
            }

            HStack(spacing: 10) {
                Button("Cancel request") {
                    onCancelDisable()
                }
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Color.climbSurface,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .buttonStyle(ScaleButtonStyle())

                if Date() >= request.earliestExecutionAt {
                    Button("Turn off") {
                        onExecuteDisable()
                    }
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .foregroundStyle(Color.climbBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        Color.climbMist,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
        .padding(14)
        .background(
            Color.climbGold.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func remainingText(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int(ceil(interval / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m remaining" : "\(minutes)m remaining"
    }
}

private struct SafariProtectionStatusRow: View {
    let snapshot: SafariProtectionSnapshot
    let onReload: () -> Void
    @State private var showSetup = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 34, height: 34)
                .background(statusColor.opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Safari layer")
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text(statusDetail)
                    .font(ClimbTypography.sans(11, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
            }
            Spacer(minLength: 0)
            Button(snapshot.status == .enabled ? "Reload" : "Setup") {
                if snapshot.status == .enabled {
                    onReload()
                } else {
                    showSetup = true
                }
            }
            .font(ClimbTypography.sans(12, weight: .semibold))
            .foregroundStyle(Color.climbGreen)
            .buttonStyle(ScaleButtonStyle())
        }
        .sheet(isPresented: $showSetup) {
            SafariProtectionSetupView(onReload: {
                showSetup = false
                onReload()
            })
        }
    }

    private var statusIcon: String {
        snapshot.status == .enabled
            ? "safari.fill"
            : "exclamationmark.triangle"
    }

    private var statusColor: Color {
        snapshot.status == .enabled ? .climbGreen : .climbGold
    }

    private var statusDetail: String {
        switch snapshot.status {
        case .checking:
            "Checking extension status"
        case .enabled:
            "\(snapshot.configuredDomainCount) local domains protected in Safari"
        case .disabled:
            "Enable The Climb in Safari extensions"
        case .unavailable:
            "Status must be verified on a physical device"
        case .reloadFailed:
            "Rules could not be reloaded"
        }
    }
}

private struct SafariProtectionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let onReload: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "safari.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.climbGreen)

                FocusSectionTitle(
                    eyebrow: "Safari only",
                    title: "Enable The Climb in Safari",
                    detail: "Open Settings, choose Apps, Safari, Extensions, then turn on The Climb Safari Protection. This layer does not filter other browsers."
                )

                PrimaryActionButton(
                    title: "I enabled it",
                    systemImage: "arrow.clockwise",
                    tint: .climbGreen
                ) {
                    onReload()
                }

                Spacer()
            }
            .padding(20)
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Safari Protection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.climbGreen)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct PermanentWebsiteReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let onApprove: (
        String,
        AdultProtectionAllowReason,
        Date?
    ) throws -> Void

    @State private var domain = ""
    @State private var reason: AdultProtectionAllowReason = .incorrectlyCategorized
    @State private var expirationDays = 30
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                FocusSectionTitle(
                    eyebrow: "False positive",
                    title: "Review one website",
                    detail: "The Climb stores only the normalized domain for this exception, never a browsing history or page URL."
                )

                TextField("example.org", text: $domain)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(Color.climbMist)
                    .padding(15)
                    .background(
                        Color.climbSurfaceRaised,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )

                Picker("Reason", selection: $reason) {
                    ForEach(AdultProtectionAllowReason.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .tint(.climbMist)

                Picker("Exception length", selection: $expirationDays) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)

                Spacer()

                PrimaryActionButton(
                    title: "Allow reviewed website",
                    systemImage: "checkmark.shield",
                    tint: .climbGold,
                    isDisabled: domain.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                ) {
                    do {
                        let expiresAt = Calendar.current.date(
                            byAdding: .day,
                            value: expirationDays,
                            to: Date()
                        )
                        try onApprove(domain, reason, expiresAt)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbRed)
                }
            }
            .padding(20)
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Website Review")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private struct PermanentProtectionDisableView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: AdultProtectionMode
    let onConfirm: (AdultProtectionDisableReason) throws -> Void

    @State private var reason: AdultProtectionDisableReason = .troubleshooting
    @State private var confirmation = ""
    @State private var errorMessage: String?

    private var requiresTypedConfirmation: Bool {
        mode != .standard
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                FocusSectionTitle(
                    eyebrow: "\(mode.title) protection",
                    title: mode == .strict
                        ? "Start the 24-hour turn-off request"
                        : "Turn off adult-site protection?",
                    detail: mode == .strict
                        ? "Protection stays active during the required wait. Your reason is stored locally with the request."
                        : "This removes the always-on Screen Time filter. Active focus and boundary rules are not removed."
                )

                Picker("Reason", selection: $reason) {
                    ForEach(AdultProtectionDisableReason.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .tint(.climbMist)

                if requiresTypedConfirmation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type TURN OFF to continue")
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .foregroundStyle(Color.climbTextSecondary)
                        TextField("TURN OFF", text: $confirmation)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(ClimbTypography.sans(15, weight: .semibold))
                            .foregroundStyle(Color.climbMist)
                            .padding(15)
                            .background(
                                Color.climbSurfaceRaised,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                            )
                    }
                }

                Spacer()

                PrimaryActionButton(
                    title: mode == .strict
                        ? "Start turn-off request"
                        : "Turn off protection",
                    systemImage: "lock.open",
                    tint: .climbGold,
                    isDisabled: requiresTypedConfirmation
                        && confirmation.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).uppercased() != "TURN OFF"
                ) {
                    do {
                        try onConfirm(reason)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                Button("Keep protection on") {
                    dismiss()
                }
                .font(ClimbTypography.sans(14, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .frame(maxWidth: .infinity)

                if let errorMessage {
                    Text(errorMessage)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbRed)
                }
            }
            .padding(20)
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Protection")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private struct PermanentDomainRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) throws -> Void

    @State private var domain = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                FocusSectionTitle(
                    eyebrow: "Local rule",
                    title: "Block a website",
                    detail: "Enter only the domain. The Climb stores the normalized domain on this device, not browsing history."
                )

                TextField("example.org", text: $domain)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .font(ClimbTypography.sans(17, weight: .medium))
                    .foregroundStyle(Color.climbMist)
                    .padding(16)
                    .background(
                        Color.climbSurfaceRaised,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                PrimaryActionButton(
                    title: "Add blocked domain",
                    systemImage: "shield.lefthalf.filled",
                    tint: .climbGreen,
                    isDisabled:
                        domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    do {
                        try onSave(domain)
                        HapticFeedback.success()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                Spacer()
            }
            .padding(20)
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Blocked Website")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.climbTextSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert(
            "Website not added",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct FocusDurationEditor: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (Int) -> Void

    @State private var usesEndTime = false
    @State private var minutes: Int
    @State private var endTime: Date

    init(selectedMinutes: Int, onSave: @escaping (Int) -> Void) {
        self.onSave = onSave
        _minutes = State(initialValue: selectedMinutes)
        _endTime = State(
            initialValue: Date().addingTimeInterval(
                TimeInterval(selectedMinutes * 60)
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                FocusSectionTitle(
                    eyebrow: "Duration",
                    title: "Choose a clear ending",
                    detail: "Focus protection and the timer use the same end time."
                )

                Picker("Duration mode", selection: $usesEndTime) {
                    Text("Minutes").tag(false)
                    Text("Until").tag(true)
                }
                .pickerStyle(.segmented)

                if usesEndTime {
                    DatePicker(
                        "End focus at",
                        selection: $endTime,
                        in: Date().addingTimeInterval(60)...Date()
                            .addingTimeInterval(24 * 60 * 60),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .tint(Color.climbGreen)
                    .padding(16)
                    .background(
                        Color.climbSurfaceRaised,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                } else {
                    HStack {
                        Text("\(minutes) minutes")
                            .font(
                                ClimbTypography.sans(24, weight: .semibold)
                                    .monospacedDigit()
                            )
                            .foregroundStyle(Color.climbMist)
                        Spacer()
                        Stepper(
                            "Minutes",
                            value: $minutes,
                            in: 5...240,
                            step: 5
                        )
                        .labelsHidden()
                    }
                    .padding(16)
                    .background(
                        Color.climbSurfaceRaised,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }

                Spacer()

                PrimaryActionButton(
                    title: "Use \(resolvedMinutes) minutes",
                    systemImage: "checkmark",
                    tint: .climbGreen
                ) {
                    onSave(resolvedMinutes)
                    dismiss()
                }
            }
            .padding(20)
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Focus Duration")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private var resolvedMinutes: Int {
        guard usesEndTime else { return minutes }
        return max(1, Int(ceil(endTime.timeIntervalSinceNow / 60)))
    }
}

private struct ActiveGeneralFocusSection: View {
    let session: FocusSession
    let intentionalBreak: IntentionalBreak?
    let onRequestBreak: () -> Void
    let onEndBreak: (String) -> Void
    let onRequestExit: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let isBreakActive = intentionalBreak?.isActive(at: context.date) == true
            VStack(alignment: .leading, spacing: 18) {
                FocusSectionTitle(
                    eyebrow: session.purpose.title,
                    title: isBreakActive ? "Intentional break" : "Focus is active",
                    detail: isBreakActive
                        ? "Protection resumes automatically when this pause ends."
                        : "Selected restrictions remain in place until this session ends."
                )

                let remaining = max(0, session.plannedEndAt.timeIntervalSince(context.date))
                Text(durationString(remaining))
                    .font(ClimbTypography.sans(48, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.climbMist)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(Int(remaining / 60)) minutes remaining")

                if let intentionalBreak, isBreakActive {
                    HStack {
                        Label(
                            durationString(
                                max(0, intentionalBreak.endsAt.timeIntervalSince(context.date))
                            ),
                            systemImage: "cup.and.heat.waves"
                        )
                        .font(ClimbTypography.sans(13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.climbGold)
                        Spacer()
                        Button("Resume now") {
                            onEndBreak(intentionalBreak.id)
                        }
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    }
                    .padding(14)
                    .background(
                        Color.climbGold.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                } else {
                    if session.strictness == .flexible
                        || session.strictness == .intentional,
                       remaining > 90 {
                        Button {
                            onRequestBreak()
                        } label: {
                            Label("Take an intentional break", systemImage: "pause.fill")
                                .font(ClimbTypography.sans(14, weight: .semibold))
                                .foregroundStyle(Color.climbMist)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(
                                    Color.climbSurfaceRaised,
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }

                    if session.strictness >= .locked {
                        Label(
                            "Locked until \(session.plannedEndAt.formatted(date: .omitted, time: .shortened))",
                            systemImage: "lock.fill"
                        )
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else {
                        Button(role: .destructive) {
                            onRequestExit()
                        } label: {
                            Text(session.strictness == .intentional
                                 ? "Request early exit"
                                 : "End session")
                                .font(ClimbTypography.sans(14, weight: .semibold))
                                .foregroundStyle(Color.climbTextSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(
                                    Color.climbSurfaceRaised,
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
            }
            .padding(20)
            .background(
                (isBreakActive ? Color.climbGold : Color.climbGreen).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        (isBreakActive ? Color.climbGold : Color.climbGreen).opacity(0.24),
                        lineWidth: 0.8
                    )
            )
        }
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval), 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct FocusEarlyExitSheet: View {
    @Environment(\.dismiss) private var dismiss

    let session: FocusSession
    let onRequest: (String?) throws -> FocusEarlyExitResolution

    @State private var reason: String
    @State private var pendingRequest: FocusEarlyExitRequest?
    @State private var errorMessage: String?

    init(
        session: FocusSession,
        pendingRequest: FocusEarlyExitRequest?,
        onRequest: @escaping (String?) throws -> FocusEarlyExitResolution
    ) {
        self.session = session
        self.onRequest = onRequest
        _reason = State(initialValue: pendingRequest?.reason ?? "")
        _pendingRequest = State(initialValue: pendingRequest)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                FocusSectionTitle(
                    eyebrow: session.strictness.title,
                    title: session.strictness == .intentional
                        ? "Pause before you leave"
                        : "End this focus session?",
                    detail: session.strictness == .intentional
                        ? "Name the real reason. A five-second pause keeps the decision deliberate."
                        : "Your protected time will be saved as ended early."
                )

                if session.strictness == .intentional {
                    TextField("Why do you need to leave?", text: $reason, axis: .vertical)
                        .font(ClimbTypography.sans(15, weight: .medium))
                        .foregroundStyle(Color.climbMist)
                        .lineLimit(2...4)
                        .padding(16)
                        .background(
                            Color.climbSurfaceRaised,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.climbHairline, lineWidth: 0.7)
                        )
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remainingDelay = max(
                        0,
                        pendingRequest?.earliestExecutionAt
                            .timeIntervalSince(context.date) ?? 0
                    )
                    PrimaryActionButton(
                        title: pendingRequest == nil
                            ? (session.strictness == .intentional
                               ? "Begin exit pause"
                               : "End session")
                            : (remainingDelay > 0
                               ? "Wait \(Int(ceil(remainingDelay))) seconds"
                               : "End session"),
                        systemImage: "door.left.hand.open",
                        tint: .climbGold,
                        isDisabled: session.strictness == .intentional
                            && (reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || remainingDelay > 0)
                    ) {
                        submit()
                    }
                }

                Button("Keep focusing") {
                    dismiss()
                }
                .font(ClimbTypography.sans(14, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .frame(maxWidth: .infinity)

                if let errorMessage {
                    Text(errorMessage)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Early Exit")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func submit() {
        do {
            switch try onRequest(reason) {
            case .pending(let request):
                pendingRequest = request
                reason = request.reason
                HapticFeedback.selection()
            case .ended:
                HapticFeedback.success()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct IntentionalBreakSheet: View {
    @Environment(\.dismiss) private var dismiss

    let session: FocusSession
    let onStart: (TimeInterval, String?) throws -> Void

    @State private var selectedMinutes = 5
    @State private var reason = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                FocusSectionTitle(
                    eyebrow: "Intentional break",
                    title: "Step away on purpose",
                    detail: "Protection resumes automatically. The focus timer keeps running."
                )

                Picker("Break length", selection: $selectedMinutes) {
                    ForEach([2, 5, 10], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)

                if session.strictness == .intentional {
                    TextField("What is this break for?", text: $reason)
                        .font(ClimbTypography.sans(15, weight: .medium))
                        .foregroundStyle(Color.climbMist)
                        .padding(16)
                        .background(
                            Color.climbSurfaceRaised,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }

                Spacer()

                PrimaryActionButton(
                    title: "Start \(selectedMinutes)-minute break",
                    systemImage: "pause.fill",
                    tint: .climbGold,
                    isDisabled: session.strictness == .intentional
                        && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    do {
                        try onStart(
                            TimeInterval(selectedMinutes * 60),
                            reason
                        )
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbRed)
                }
            }
            .padding(20)
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Take a Break")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

private struct FocusRhythmPauseView: View {
    @Environment(\.dismiss) private var dismiss

    let onPause: (Date, FocusRhythmPauseReason) throws -> Void

    @State private var selectedDurationDays = 1
    @State private var reason: FocusRhythmPauseReason = .travel
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                FocusSectionTitle(
                    eyebrow: "Rhythm pause",
                    title: "Make room for a different week",
                    detail: "Recurring focus windows stop temporarily and return automatically."
                )

                Picker("Pause length", selection: $selectedDurationDays) {
                    Text("1 day").tag(1)
                    Text("3 days").tag(3)
                    Text("1 week").tag(7)
                }
                .pickerStyle(.segmented)

                Picker("Reason", selection: $reason) {
                    ForEach(FocusRhythmPauseReason.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .tint(.climbMist)

                Text("Permanent adult-site protection and active app boundaries stay on.")
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
                    .lineSpacing(2)

                Spacer()

                PrimaryActionButton(
                    title: "Pause rhythms",
                    systemImage: "pause.fill",
                    tint: .climbGold
                ) {
                    do {
                        let resumesAt = Calendar.current.date(
                            byAdding: .day,
                            value: selectedDurationDays,
                            to: Date()
                        ) ?? Date().addingTimeInterval(
                            TimeInterval(selectedDurationDays * 24 * 60 * 60)
                        )
                        try onPause(resumesAt, reason)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbRed)
                }
            }
            .padding(20)
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Pause Rhythms")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

private struct FocusRhythmEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let usesEssentialApps: Bool
    let blocksAdultWebContent: Bool
    let onSave: (FocusRhythm) throws -> Void

    @State private var name = "Morning Scripture"
    @State private var startTime = Calendar.current.date(
        bySettingHour: 7,
        minute: 0,
        second: 0,
        of: Date()
    ) ?? Date()
    @State private var endTime = Calendar.current.date(
        bySettingHour: 8,
        minute: 0,
        second: 0,
        of: Date()
    ) ?? Date()
    @State private var weekdays: Set<Weekday> = [
        .monday, .tuesday, .wednesday, .thursday, .friday
    ]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TextField("Rhythm name", text: $name)
                        .font(ClimbTypography.sans(20, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                        .padding(16)
                        .background(
                            Color.climbSurfaceRaised,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )

                    HStack(spacing: 12) {
                        DatePicker(
                            "Starts",
                            selection: $startTime,
                            displayedComponents: .hourAndMinute
                        )
                        DatePicker(
                            "Ends",
                            selection: $endTime,
                            displayedComponents: .hourAndMinute
                        )
                    }
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(Color.climbTextSecondary)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Days")
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Color.climbMuted)
                            .textCase(.uppercase)

                        HStack(spacing: 6) {
                            ForEach(Weekday.allCases, id: \.self) { weekday in
                                Button {
                                    if weekdays.contains(weekday) {
                                        weekdays.remove(weekday)
                                    } else {
                                        weekdays.insert(weekday)
                                    }
                                } label: {
                                    Text(weekday.shortTitle)
                                        .font(ClimbTypography.sans(12, weight: .semibold))
                                        .foregroundStyle(
                                            weekdays.contains(weekday)
                                                ? Color.climbBackground
                                                : Color.climbTextSecondary
                                        )
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 38)
                                        .background(
                                            weekdays.contains(weekday)
                                                ? Color.climbMist
                                                : Color.climbSurfaceRaised,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                    }

                    Text(
                        usesEssentialApps
                            ? "This rhythm keeps only your Essential Apps available."
                            : "This rhythm blocks your saved distraction selection."
                    )
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(3)

                    PrimaryActionButton(
                        title: "Save Rhythm",
                        systemImage: "checkmark",
                        tint: .climbGreen,
                        isDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || weekdays.isEmpty
                    ) {
                        save()
                    }
                }
                .padding(20)
            }
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("New Rhythm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.climbTextSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert(
            "Rhythm not saved",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            let calendar = Calendar.current
            let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
            let id = UUID().uuidString.lowercased()
            let now = Date()
            let rhythm = FocusRhythm(
                id: id,
                sourceID: .rhythm(id),
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                purpose: .bibleStudy,
                strictness: .intentional,
                weekdays: weekdays,
                startTime: try LocalTime(
                    hour: startComponents.hour ?? 7,
                    minute: startComponents.minute ?? 0
                ),
                endTime: try LocalTime(
                    hour: endComponents.hour ?? 8,
                    minute: endComponents.minute ?? 0
                ),
                timeZoneIdentifier: TimeZone.current.identifier,
                selectionReference: usesEssentialApps
                    ? nil
                    : FocusSelectionReference(
                        rawValue: ScreenTimeSelectionReference.defaultSelection
                    ),
                essentialAppsReference: usesEssentialApps
                    ? EssentialAppsSelectionReference(rawValue: "essential-apps-v1")
                    : nil,
                blocksAdultWebContent: blocksAdultWebContent,
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            )
            try onSave(rhythm)
            HapticFeedback.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AppBoundaryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let blocksAdultWebContent: Bool
    let onSave: (AppBoundary) throws -> Void

    @State private var name = "Social apps"
    @State private var cadence: BoundaryScheduleCadence = .daily
    @State private var allowedMinutes = 45
    @State private var resetTime = Calendar.current.startOfDay(for: Date())
    @State private var weekdays = Set(Weekday.allCases)
    @State private var weekStartsOn = Weekday.monday
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TextField("Boundary name", text: $name)
                        .font(ClimbTypography.sans(20, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                        .padding(16)
                        .background(
                            Color.climbSurfaceRaised,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )

                    Picker("Cadence", selection: $cadence) {
                        Text("Daily").tag(BoundaryScheduleCadence.daily)
                        Text("Weekly").tag(BoundaryScheduleCadence.weekly)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Allowance")
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Color.climbMuted)
                            .textCase(.uppercase)
                        HStack(spacing: 8) {
                            ForEach(allowanceOptions, id: \.self) { minutes in
                                Button {
                                    allowedMinutes = minutes
                                } label: {
                                    Text(minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m")
                                        .font(ClimbTypography.sans(14, weight: .semibold))
                                        .foregroundStyle(
                                            allowedMinutes == minutes
                                                ? Color.climbBackground
                                                : Color.climbTextSecondary
                                        )
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(
                                            allowedMinutes == minutes
                                                ? Color.climbMist
                                                : Color.climbSurfaceRaised,
                                            in: RoundedRectangle(
                                                cornerRadius: 13,
                                                style: .continuous
                                            )
                                        )
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                    }

                    DatePicker(
                        "Resets at",
                        selection: $resetTime,
                        displayedComponents: .hourAndMinute
                    )
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(Color.climbMist)

                    if cadence == .daily {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Active days")
                                .font(ClimbTypography.sans(12, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(Color.climbMuted)
                                .textCase(.uppercase)
                            HStack(spacing: 6) {
                                ForEach(Weekday.allCases, id: \.self) { weekday in
                                    Button {
                                        if weekdays.contains(weekday) {
                                            weekdays.remove(weekday)
                                        } else {
                                            weekdays.insert(weekday)
                                        }
                                    } label: {
                                        Text(weekday.shortTitle)
                                            .font(ClimbTypography.sans(12, weight: .semibold))
                                            .foregroundStyle(
                                                weekdays.contains(weekday)
                                                    ? Color.climbBackground
                                                    : Color.climbTextSecondary
                                            )
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 38)
                                            .background(
                                                weekdays.contains(weekday)
                                                    ? Color.climbMist
                                                    : Color.climbSurfaceRaised,
                                                in: RoundedRectangle(
                                                    cornerRadius: 12,
                                                    style: .continuous
                                                )
                                            )
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                        }
                    } else {
                        Menu {
                            ForEach(Weekday.allCases, id: \.self) { weekday in
                                Button(weekday.longTitle) {
                                    weekStartsOn = weekday
                                }
                            }
                        } label: {
                            FocusChoiceRow(
                                title: "Week resets",
                                value: weekStartsOn.longTitle,
                                systemImage: "calendar"
                            )
                        }
                    }

                    Text("Usage is measured by Apple’s Device Activity framework. The Climb does not receive browsing history or app content.")
                        .font(ClimbTypography.sans(13, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)

                    PrimaryActionButton(
                        title: "Save Boundary",
                        systemImage: "hourglass",
                        tint: .climbGreen,
                        isDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (cadence == .daily && weekdays.isEmpty)
                    ) {
                        save()
                    }
                }
                .padding(20)
            }
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("New Boundary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.climbTextSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert(
            "Boundary not saved",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var allowanceOptions: [Int] {
        cadence == .daily ? [30, 45, 60, 90] : [180, 300, 420, 600]
    }

    private func save() {
        do {
            let calendar = Calendar.current
            let resetComponents = calendar.dateComponents([.hour, .minute], from: resetTime)
            let reset = try LocalTime(
                hour: resetComponents.hour ?? 0,
                minute: resetComponents.minute ?? 0
            )
            let id = UUID().uuidString.lowercased()
            let scheduleID = UUID().uuidString.lowercased()
            let now = Date()
            let boundary = AppBoundary(
                id: id,
                sourceID: .boundary(id),
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                selectionReference: FocusSelectionReference(
                    rawValue: ScreenTimeSelectionReference.defaultSelection
                ),
                essentialAppsReference: nil,
                strictness: .intentional,
                schedules: [
                    AppBoundarySchedule(
                        id: scheduleID,
                        cadence: cadence,
                        allowedDuration: TimeInterval(allowedMinutes * 60),
                        resetTime: reset,
                        activeWeekdays: cadence == .daily ? weekdays : [],
                        weekStartsOn: weekStartsOn,
                        isEnabled: true
                    )
                ],
                warningThresholds: [
                    BoundaryWarningThreshold(
                        id: "ten-minutes",
                        remainingDuration: 10 * 60
                    ),
                    BoundaryWarningThreshold(
                        id: "five-minutes",
                        remainingDuration: 5 * 60
                    )
                ],
                timeZoneIdentifier: TimeZone.current.identifier,
                blocksAdultWebContent: blocksAdultWebContent,
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            )
            try onSave(boundary)
            HapticFeedback.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FocusSectionTitle: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(ClimbTypography.sans(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.climbGreen.opacity(0.84))
                .textCase(.uppercase)
            Text(title)
                .font(ClimbTypography.sans(23, weight: .semibold))
                .foregroundStyle(Color.climbMist)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(ClimbTypography.sans(13, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FocusChoiceRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.climbGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ClimbTypography.sans(10, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)
                Text(value)
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            Color.climbSurfaceRaised,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

private struct FocusSettingsButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.selection()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.climbGreen)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    Text(detail)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct FocusRhythmRow: View {
    let rhythm: FocusRhythm
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(rhythm.name)
                    .font(ClimbTypography.sans(16, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text("\(rhythm.startTime.displayText)–\(rhythm.endTime.displayText) · \(rhythm.weekdays.count) days")
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Delete \(rhythm.name)")
        }
        .padding(.vertical, 8)
    }
}

private struct AppBoundaryRow: View {
    let boundary: AppBoundary
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(boundary.name)
                    .font(ClimbTypography.sans(16, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text(boundarySummary)
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Delete \(boundary.name)")
        }
        .padding(.vertical, 8)
    }

    private var boundarySummary: String {
        guard let schedule = boundary.schedules.first else {
            return "No active schedule"
        }
        let minutes = Int(schedule.allowedDuration / 60)
        let allowance = minutes >= 60 && minutes % 60 == 0
            ? "\(minutes / 60)h"
            : "\(minutes)m"
        return "\(allowance) \(schedule.cadence.title.lowercased()) · resets \(schedule.resetTime.displayText)"
    }
}

private struct FocusReportMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ClimbTypography.sans(19, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            Color.climbSurfaceRaised,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

private struct FocusDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.climbHairline)
            .frame(height: 0.7)
            .padding(.leading, 56)
    }
}

private extension FocusPurpose {
    var title: String {
        switch self {
        case .mission:
            "Mission"
        case .prayer:
            "Prayer"
        case .bibleStudy:
            "Scripture"
        case .worship:
            "Worship"
        case .church:
            "Church"
        case .family:
            "Family"
        case .exercise:
            "Exercise"
        case .deepWork:
            "Deep Work"
        case .school:
            "School"
        case .homework:
            "Homework"
        case .creativeWork:
            "Creative Work"
        case .personalGrowth:
            "Personal Growth"
        case .rest:
            "Rest"
        case .sleep:
            "Sleep"
        case .custom:
            "Custom"
        }
    }
}

private extension FocusStrictness {
    var title: String {
        switch self {
        case .flexible:
            "Flexible"
        case .intentional:
            "Intentional"
        case .locked:
            "Locked"
        case .accountabilityLocked:
            "Partner locked"
        }
    }
}

private extension FocusRhythmPauseReason {
    var title: String {
        switch self {
        case .travel:
            "Travel"
        case .vacation:
            "Vacation"
        case .scheduleChanged:
            "Schedule changed"
        case .rest:
            "Rest"
        case .other:
            "Other"
        }
    }
}

private extension FocusSelectionMode {
    var title: String {
        switch self {
        case .blockSelected:
            "Selected"
        case .allowEssentialApps:
            "Essentials"
        }
    }
}

private extension Weekday {
    var shortTitle: String {
        switch self {
        case .monday:
            "M"
        case .tuesday:
            "T"
        case .wednesday:
            "W"
        case .thursday:
            "T"
        case .friday:
            "F"
        case .saturday:
            "S"
        case .sunday:
            "S"
        }
    }

    var longTitle: String {
        switch self {
        case .monday:
            "Monday"
        case .tuesday:
            "Tuesday"
        case .wednesday:
            "Wednesday"
        case .thursday:
            "Thursday"
        case .friday:
            "Friday"
        case .saturday:
            "Saturday"
        case .sunday:
            "Sunday"
        }
    }
}

private extension LocalTime {
    var displayText: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private extension BoundaryScheduleCadence {
    var title: String {
        switch self {
        case .daily:
            "Daily"
        case .weekly:
            "Weekly"
        }
    }
}

private extension AdultProtectionMode {
    var title: String {
        switch self {
        case .standard:
            "Standard"
        case .strict:
            "Strict"
        case .accountability:
            "Accountability"
        }
    }
}

private extension AdultProtectionDisableReason {
    var title: String {
        switch self {
        case .changeProtectionMode:
            "Change protection mode"
        case .troubleshooting:
            "Troubleshooting"
        case .falsePositiveImpact:
            "A website is blocked incorrectly"
        case .noLongerNeeded:
            "I no longer need protection"
        case .other:
            "Another reason"
        }
    }
}

private extension AdultProtectionAllowReason {
    var title: String {
        switch self {
        case .incorrectlyCategorized:
            "Incorrectly categorized"
        case .education:
            "Education"
        case .work:
            "Work"
        case .health:
            "Health"
        case .ministry:
            "Ministry"
        case .otherLegitimateUse:
            "Other legitimate use"
        }
    }
}
