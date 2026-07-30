import SwiftUI
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

struct ScreenTimeUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel

    let experienceVersion: Int
    let onFinished: () -> Void

    @State private var progress: ScreenTimeUpgradeProgress
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showFocusSetup = false
#if canImport(FamilyControls) && os(iOS)
    @State private var showActivityPicker = false
    @State private var activitySelection = FamilyActivitySelection()
#endif

    private let store = AppGroupScreenTimeUpgradeStateStore()
    private let progressService = ScreenTimeUpgradeProgressService()

    init(
        viewModel: AppViewModel,
        progress: ScreenTimeUpgradeProgress,
        experienceVersion: Int,
        onFinished: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.experienceVersion = experienceVersion
        self.onFinished = onFinished
        _progress = State(initialValue: progress)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        stepContent
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 42)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)

                actionArea
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            .background(Color.climbBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Later") {
                        deferUpgrade()
                    }
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(Color.climbTextSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task {
            markPresented()
#if canImport(FamilyControls) && os(iOS)
            if #available(iOS 16.0, *) {
                activitySelection = ScreenTimeActivitySelectionStore.loadSelection()
            }
#endif
        }
#if canImport(FamilyControls) && os(iOS)
        .familyActivityPicker(
            headerText: "Choose apps, categories, and websites that pull you away.",
            footerText: "Apple keeps these selections private on this device.",
            isPresented: $showActivityPicker,
            selection: $activitySelection
        )
        .onChange(of: activitySelection) { _, selection in
            ScreenTimeActivitySelectionStore.saveSelection(selection)
        }
#endif
        .sheet(isPresented: $showFocusSetup) {
            FocusControlCenterView(viewModel: viewModel)
        }
        .alert(
            "Setup needs attention",
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

    private var currentStep: ScreenTimeSetupStep {
        progress.nextStep() ?? .finish
    }

    private var definition: ScreenTimeUpgradeFlowDefinition {
        .definition(for: progress.flowKind)
    }

    private var currentStepIndex: Int {
        definition.steps.firstIndex(of: currentStep) ?? 0
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let fraction = Double(currentStepIndex + 1)
                / Double(max(definition.steps.count, 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(Color.climbGreen)
                    .frame(width: proxy.size.width * fraction)
                    .animation(ClimbMotion.standard, value: fraction)
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Setup progress")
        .accessibilityValue(
            "Step \(currentStepIndex + 1) of \(definition.steps.count)"
        )
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .upgradeIntroduction:
            UpgradeHero(
                symbol: "hourglass",
                eyebrow: "The Climb is growing",
                title: "Faithful attention,\nprotected.",
                detail: "Your missions, streaks, journal, community, and progress remain. The Climb now helps protect the time those commitments require."
            )
            upgradePrinciples
        case .capabilityExplanation:
            UpgradeHero(
                symbol: "shield.lefthalf.filled",
                eyebrow: "Built with Apple Screen Time",
                title: "Less friction.\nMore follow-through.",
                detail: "Focus sessions, recurring rhythms, app boundaries, and adult-site protection work together without exposing which apps you choose."
            )
            privacyRows
        case .screenTimeAuthorization:
            UpgradeHero(
                symbol: "checkmark.shield",
                eyebrow: "Permission",
                title: "Allow Screen Time access",
                detail: "Apple requires one system permission before The Climb can apply real restrictions."
            )
            permissionStatus
        case .distractionSelection:
            UpgradeHero(
                symbol: "apps.iphone",
                eyebrow: "Distractions",
                title: "Choose what should go quiet",
                detail: "Select the apps, categories, or websites you want available only when you decide."
            )
            selectionSummary
        case .firstFocusRhythmOffer:
            UpgradeHero(
                symbol: "calendar.badge.clock",
                eyebrow: "Optional rhythm",
                title: "Protect a recurring window",
                detail: "Schedule prayer, Scripture, school, work, rest, or sleep. You can create up to two rhythms now."
            )
        case .permanentProtectionOffer:
            UpgradeHero(
                symbol: "lock.shield",
                eyebrow: "Optional protection",
                title: "Keep adult sites restricted",
                detail: "Standard mode stays on beyond focus sessions and can be disabled immediately. Strict mode is available later with a 24-hour delay."
            )
        case .finish:
            UpgradeHero(
                symbol: "checkmark.circle.fill",
                eyebrow: "Ready",
                title: "Protect the next faithful step",
                detail: "The new Focus center is ready. Your existing account data has not been reset or replaced."
            )
        case .screenTimeGoal,
             .focusPurposes,
             .adultProtectionPreference,
             .accountabilityPreference,
             .preferredFocusSchedule:
            UpgradeHero(
                symbol: "slider.horizontal.3",
                eyebrow: "Setup",
                title: currentStep.title,
                detail: currentStep.detail
            )
        }
    }

    private var actionArea: some View {
        VStack(spacing: 10) {
            PrimaryActionButton(
                title: primaryActionTitle,
                systemImage: primaryActionSymbol,
                tint: .climbGreen,
                isDisabled: isWorking
            ) {
                performPrimaryAction()
            }

            if definition.canSkip(currentStep) {
                Button("Skip for now") {
                    recordCurrentStep(.skipped)
                }
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            } else if currentStep == .distractionSelection {
                Button("Choose later in Focus") {
                    recordCurrentStep(.deferred)
                }
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
        }
        .padding(.top, 14)
        .background(.ultraThinMaterial.opacity(0.72))
    }

    private var upgradePrinciples: some View {
        VStack(spacing: 0) {
            UpgradeValueRow(
                symbol: "timer",
                title: "Protected focus",
                detail: "Immediate sessions with clear purposes and honest exits."
            )
            Divider().overlay(Color.climbDivider)
            UpgradeValueRow(
                symbol: "repeat",
                title: "Daily rhythms",
                detail: "Restrictions that return at the times you choose."
            )
            Divider().overlay(Color.climbDivider)
            UpgradeValueRow(
                symbol: "cross",
                title: "Faith stays central",
                detail: "Prayer, Scripture, missions, and reflection remain connected."
            )
        }
    }

    private var privacyRows: some View {
        VStack(spacing: 0) {
            UpgradeValueRow(
                symbol: "hand.raised",
                title: "Selections stay private",
                detail: "The Climb stores Apple-issued tokens, not a readable list of your apps."
            )
            Divider().overlay(Color.climbDivider)
            UpgradeValueRow(
                symbol: "iphone",
                title: "Enforced on device",
                detail: "ManagedSettings applies restrictions without sending browsing history to Firebase."
            )
        }
    }

    private var permissionStatus: some View {
        HStack(spacing: 13) {
            Image(
                systemName: viewModel.focusState == .authorized
                    ? "checkmark.circle.fill"
                    : "circle.dashed"
            )
            .foregroundStyle(
                viewModel.focusState == .authorized
                    ? Color.climbGreen
                    : Color.climbGold
            )
            Text(
                viewModel.focusState == .authorized
                    ? "Screen Time access is allowed"
                    : "Permission has not been granted yet"
            )
            .font(ClimbTypography.sans(14, weight: .semibold))
            .foregroundStyle(Color.climbTextSecondary)
        }
        .padding(.vertical, 8)
    }

    private var selectionSummary: some View {
        Button {
#if canImport(FamilyControls) && os(iOS)
            showActivityPicker = true
#endif
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.climbGreen)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose distractions")
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    Text(selectionDetail)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
            }
            .padding(16)
            .background(
                Color.climbSurfaceRaised,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var selectionDetail: String {
#if canImport(FamilyControls) && os(iOS)
        let count = activitySelection.shieldableContentCount
        return count == 0 ? "Nothing selected yet" : "\(count) selected"
#else
        return "Unavailable on this device"
#endif
    }

    private var primaryActionTitle: String {
        switch currentStep {
        case .upgradeIntroduction, .capabilityExplanation:
            "Continue"
        case .screenTimeAuthorization:
            viewModel.focusState == .authorized ? "Continue" : "Allow Screen Time"
        case .distractionSelection:
            "Save selection"
        case .firstFocusRhythmOffer:
            "Open rhythm setup"
        case .permanentProtectionOffer:
            "Enable Standard protection"
        case .finish:
            "Enter The Climb"
        default:
            "Continue"
        }
    }

    private var primaryActionSymbol: String {
        switch currentStep {
        case .screenTimeAuthorization:
            "checkmark.shield"
        case .distractionSelection:
            "checkmark"
        case .firstFocusRhythmOffer:
            "calendar.badge.plus"
        case .permanentProtectionOffer:
            "lock.shield"
        case .finish:
            "arrow.right"
        default:
            "arrow.right"
        }
    }

    private func performPrimaryAction() {
        switch currentStep {
        case .screenTimeAuthorization:
            authorizeScreenTime()
        case .distractionSelection:
#if canImport(FamilyControls) && os(iOS)
            guard activitySelection.hasShieldableContent
                    || FocusAdultContentFilterStore.isEnabled else {
                showActivityPicker = true
                return
            }
#endif
            recordCurrentStep(.completed)
        case .firstFocusRhythmOffer:
            recordCurrentStep(.completed)
            showFocusSetup = true
        case .permanentProtectionOffer:
            enableStandardProtection()
        case .finish:
            recordCurrentStep(.completed)
        default:
            recordCurrentStep(.completed)
        }
    }

    private func authorizeScreenTime() {
        guard viewModel.focusState != .authorized else {
            recordCurrentStep(.completed)
            return
        }
        isWorking = true
        Task {
            await viewModel.requestScreenTimeAuthorization()
            await MainActor.run {
                isWorking = false
                if viewModel.focusState == .authorized {
                    recordCurrentStep(.completed)
                } else {
                    errorMessage = "Screen Time access was not granted. You can try again or return later."
                }
            }
        }
    }

    private func enableStandardProtection() {
        isWorking = true
        Task {
            do {
                let envelope = try await AdultProtectionRuntimeService().activate(
                    mode: .standard
                )
                _ = await SafariContentBlockerService().updateRules(
                    from: envelope.rules
                )
                await MainActor.run {
                    isWorking = false
                    recordCurrentStep(.completed)
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func markPresented() {
        do {
            guard var state = try store.load() else { return }
            state = try progressService.markPresented(
                state: state,
                experienceVersion: experienceVersion
            )
            try store.save(state)
            if let updated = state.progress(for: experienceVersion) {
                progress = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordCurrentStep(_ outcome: ScreenTimeSetupStepOutcome) {
        do {
            guard var state = try store.load() else { return }
            state = try progressService.record(
                step: currentStep,
                outcome: outcome,
                state: state,
                experienceVersion: experienceVersion
            )
            try store.save(state)
            guard let updated = state.progress(for: experienceVersion) else {
                return
            }
            progress = updated
            HapticFeedback.selection()
            if updated.status == .completed {
                HapticFeedback.success()
                onFinished()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deferUpgrade() {
        do {
            guard var state = try store.load() else {
                dismiss()
                return
            }
            state = try progressService.deferPresentation(
                state: state,
                experienceVersion: experienceVersion,
                until: Date().addingTimeInterval(3 * 24 * 60 * 60)
            )
            try store.save(state)
            onFinished()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UpgradeHero: View {
    let symbol: String
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Color.climbGreen)
                .frame(width: 52, height: 52)
                .background(Color.climbGreen.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(Color.climbGreen)
                Text(title)
                    .font(ClimbTypography.sans(34, weight: .bold))
                    .foregroundStyle(Color.climbMist)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct UpgradeValueRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.climbGreen)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text(detail)
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
    }
}

private extension ScreenTimeSetupStep {
    var title: String {
        switch self {
        case .screenTimeGoal: "Choose your attention goal"
        case .focusPurposes: "Choose focus purposes"
        case .adultProtectionPreference: "Set adult-site protection"
        case .accountabilityPreference: "Choose accountability"
        case .preferredFocusSchedule: "Choose a preferred schedule"
        default: "Finish setup"
        }
    }

    var detail: String {
        switch self {
        case .screenTimeGoal:
            "Name the change you want Screen Time protection to support."
        case .focusPurposes:
            "Choose the faithful work you want focus sessions to protect."
        case .adultProtectionPreference:
            "Decide whether adult-site protection should remain active beyond sessions."
        case .accountabilityPreference:
            "Choose whether a trusted partner should support protection changes."
        case .preferredFocusSchedule:
            "Set a recurring time when focus should return automatically."
        default:
            "Complete the remaining Screen Time setup."
        }
    }
}
