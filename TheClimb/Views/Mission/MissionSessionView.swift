import Combine
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

struct MissionSessionView: View {
    @ObservedObject var viewModel: AppViewModel
    let mission: Mission

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: MissionPhase
    @State private var remainingSeconds: Int
    @State private var focusEndsAt: Date?
    @State private var hardestPart = ""
    @State private var lessonLearned = ""
    @State private var effortRating = 3.0
    @State private var improvementPlan = ""
    @State private var mood: MoodRating = .steady
    @State private var failureReason = ""
    @State private var isSubmittingResult = false
    @State private var completedStreak: Int?
    @State private var completedOVR: Int?
    @State private var completedNewBest = false
#if canImport(FamilyControls) && os(iOS)
    @State private var showActivityPicker = false
    @State private var activitySelection = FamilyActivitySelection()
    @State private var shouldStartAfterActivityPicker = false
    @State private var focusTemplates: [FocusTemplateSummary] = []
    @State private var activeTemplateID: String?
#endif

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(viewModel: AppViewModel, mission: Mission) {
        self.viewModel = viewModel
        self.mission = mission
        let storedEndDate = ActiveFocusMissionTimerStore.endDate(for: mission.id)
        let initialRemainingSeconds = storedEndDate.map(Self.remainingSeconds(until:)) ?? mission.durationMinutes * 60
        _remainingSeconds = State(initialValue: initialRemainingSeconds)
        _focusEndsAt = State(initialValue: storedEndDate)

        let initialPhase: MissionPhase
        switch mission.status {
        case .completed, .recovered:
            initialPhase = .complete
        case .active:
            initialPhase = initialRemainingSeconds <= 0 ? .reflection : .running
        case .failed:
            initialPhase = .fallback
        case .pending:
            initialPhase = .ready
        }
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        NavigationStack {
            Group {
                if phase == .running {
                    runningFocusContent
                        .transition(.climbScreen)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                            content
                                .id(phase)
                                .transition(.climbScreen)
                        }
                        .padding(20)
                    }
                    .transition(.climbScreen)
                }
            }
            .background(ClimbScreenBackground())
            .navigationTitle(phase == .running ? "Focus" : "Mission")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .animation(ClimbMotion.standard, value: phase)
        .onReceive(timer) { _ in
            guard phase == .running else { return }
            updateRemainingTime()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, phase == .running {
                updateRemainingTime()
            }
        }
#if canImport(FamilyControls) && os(iOS)
        .familyActivityPicker(
            headerText: "Choose the apps, categories, or websites The Climb should block during this mission.",
            footerText: "These choices stay on this device and will be reused for future focus missions.",
            isPresented: $showActivityPicker,
            selection: $activitySelection
        )
        .onAppear {
            activitySelection = ScreenTimeActivitySelectionStore.loadSelection()
            focusTemplates = ScreenTimeActivitySelectionStore.loadTemplateSummaries()
            activeTemplateID = nil
            Task {
                await viewModel.refreshScreenTimeAuthorization()
            }
        }
        .onChange(of: activitySelection) { _, newSelection in
            ScreenTimeActivitySelectionStore.saveSelection(newSelection)
            focusTemplates = ScreenTimeActivitySelectionStore.loadTemplateSummaries()
        }
        .onChange(of: showActivityPicker) { _, isPresented in
            guard !isPresented, shouldStartAfterActivityPicker else { return }
            shouldStartAfterActivityPicker = false
            guard activitySelection.hasShieldableContent else { return }
            startFocusTimer()
        }
#endif
    }

    private var header: some View {
        ClimbQuietPanel(padding: 22, cornerRadius: 22, isProminent: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Mission")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.climbTextSecondary)
                    .textCase(.uppercase)
                Text(mission.title)
                    .font(ClimbTypography.sans(28, weight: .semibold))
                    .foregroundStyle(.white)
                Text(mission.summary)
                    .font(ClimbTypography.sans(15))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(3)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .ready:
            readyContent
        case .running:
            EmptyView()
        case .reflection:
            reflectionContent
        case .failurePrompt:
            failureContent
        case .fallback:
            fallbackContent
        case .complete:
            completeContent
        }
    }

    private var readyContent: some View {
        ClimbQuietPanel(padding: 22, cornerRadius: 22, isProminent: true) {
            SectionTitle(title: "Before You Start", subtitle: "Make the room quiet before the timer begins.")
            Text("Set your phone down, breathe once, and give this mission your full attention.")
                .font(ClimbTypography.sans(15, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
#if canImport(FamilyControls) && os(iOS)
            if mission.appBlockingEnabled {
                FocusPreflightPanel(
                    authorizationState: viewModel.focusState,
                    selectedItemCount: activitySelection.shieldableContentCount,
                    templates: focusTemplates,
                    activeTemplateID: activeTemplateID,
                    onRequestPermission: {
                        if viewModel.focusState == .denied,
                           let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            openURL(settingsURL)
                        } else {
                            Task {
                                await viewModel.requestScreenTimeAuthorization()
                            }
                        }
                    },
                    onChooseApps: {
                        showActivityPicker = true
                    },
                    onApplyTemplate: { template in
                        if let selection = ScreenTimeActivitySelectionStore.applyTemplate(id: template.id) {
                            activeTemplateID = template.id
                            activitySelection = selection
                            HapticFeedback.selection()
                        }
                    }
                )
            } else {
                FocusPreflightDisabledPanel()
            }
#endif
            DailyContentFeedbackStrip(
                title: "Mission fit",
                selected: viewModel.contentFeedback(for: mission.id, kind: .mission)
            ) { rating in
                viewModel.submitContentFeedback(
                    kind: .mission,
                    contentID: mission.id,
                    title: mission.title,
                    rating: rating
                )
            }

            PrimaryActionButton(title: beginFocusButtonTitle, systemImage: "play.fill") {
                beginFocusFlow()
            }
        }
    }

    private var runningFocusContent: some View {
        ZStack {
            ClimbScreenBackground()
            VStack(spacing: 24) {
                HStack {
                    StatusBadge(text: focusStateLabel, color: focusStateColor)
                    Spacer()
                    Text("FOCUS WINDOW")
                        .font(ClimbTypography.sans(11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Color.climbMuted)
                }
                .padding(.top, 18)
                .padding(.horizontal, 22)

                Spacer(minLength: 18)

                VStack(spacing: 22) {
                    FocusTimerRing(
                        progress: focusProgress,
                        time: timeString,
                        icon: focusIcon,
                        tint: focusStateColor
                    )

                    VStack(spacing: 10) {
                        Text(mission.title)
                            .font(ClimbTypography.sans(26, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 22)

                        Text(focusText)
                            .font(ClimbTypography.sans(15, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 34)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    PrimaryActionButton(title: "Complete Mission", systemImage: "checkmark.circle.fill") {
                        phase = .reflection
                        Task {
                            await viewModel.stopMissionFocus()
                        }
                    }

                    Button {
                        phase = .failurePrompt
                        Task {
                            await viewModel.stopMissionFocus()
                        }
                    } label: {
                        Text("End Early")
                            .font(ClimbTypography.sans(14, weight: .semibold))
                            .foregroundStyle(Color.climbMuted)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var reflectionContent: some View {
        ClimbQuietPanel(padding: 22, cornerRadius: 22, accent: .climbWarm, isProminent: true) {
            Text("What did this mission reveal?")
                .font(ClimbTypography.serif(27))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            TextField("What was hardest?", text: $hardestPart, axis: .vertical)
                .lineLimit(2...4)
                .formFieldStyle()
            TextField("What did you learn?", text: $lessonLearned, axis: .vertical)
                .lineLimit(2...4)
                .formFieldStyle()
            VStack(alignment: .leading, spacing: 8) {
                Text("Effort: \(Int(effortRating))/5")
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                Slider(value: $effortRating, in: 1...5, step: 1)
                    .tint(.climbSage)
            }

            TextField("Improvement plan", text: $improvementPlan, axis: .vertical)
                .lineLimit(2...4)
                .formFieldStyle()

            PrimaryActionButton(
                title: isSubmittingResult ? "Saving Reflection" : "Submit Reflection",
                systemImage: "square.and.pencil",
                isDisabled: !reflectionIsValid || isSubmittingResult
            ) {
                guard !isSubmittingResult else { return }
                isSubmittingResult = true
                let previousBest = viewModel.profile?.longestStreak ?? 0
                Task { @MainActor in
                    let didComplete = await viewModel.completeMission(
                        missionID: mission.id,
                        hardestPart: hardestPart,
                        lessonLearned: lessonLearned,
                        effortRating: Int(effortRating),
                        improvementPlan: improvementPlan,
                        mood: mood
                    )
                    if didComplete {
                        let newStreak = viewModel.profile?.currentStreak ?? 0
                        completedStreak = newStreak
                        completedOVR = viewModel.profile?.ovrScore
                        completedNewBest = newStreak > previousBest
                        HapticFeedback.success()
                        phase = .complete
                    }
                    isSubmittingResult = false
                }
            }
        }
    }

    private var failureContent: some View {
        ClimbQuietPanel(cornerRadius: 22, accent: .climbRed) {
            SectionTitle(
                title: "Log the Miss",
                subtitle: "Be honest, then take the recovery step. One missed mission should not become a missed day."
            )
            TextField("Why did this mission fail?", text: $failureReason, axis: .vertical)
                .lineLimit(2...5)
                .formFieldStyle()
            PrimaryActionButton(
                title: isSubmittingResult ? "Saving Failure" : "Log Failure",
                systemImage: "arrow.counterclockwise.circle",
                tint: .climbRed,
                isDisabled: failureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingResult
            ) {
                guard !isSubmittingResult else { return }
                isSubmittingResult = true
                Task {
                    let didLogFailure = await viewModel.failMission(missionID: mission.id, reason: failureReason)
                    if didLogFailure {
                        phase = .fallback
                    }
                    isSubmittingResult = false
                }
            }
        }
    }

    private var fallbackContent: some View {
        ClimbQuietPanel(cornerRadius: 22, accent: .climbGold) {
            SectionTitle(title: mission.fallbackTitle)
            Text(mission.fallbackSummary)
                .font(ClimbTypography.sans(15))
                .foregroundStyle(Color.climbTextSecondary)
            PrimaryActionButton(
                title: isSubmittingResult ? "Saving Recovery" : "Complete Recovery",
                systemImage: "checkmark.seal",
                isDisabled: isSubmittingResult
            ) {
                guard !isSubmittingResult else { return }
                isSubmittingResult = true
                Task {
                    let didCompleteRecovery = await viewModel.completeFallback(missionID: mission.id)
                    if didCompleteRecovery {
                        dismiss()
                    }
                    isSubmittingResult = false
                }
            }
        }
    }

    private var completeContent: some View {
        let streak = completedStreak ?? viewModel.profile?.currentStreak ?? 0
        let ovr = completedOVR ?? viewModel.profile?.ovrScore ?? 0

        return ClimbQuietPanel(cornerRadius: 24, isProminent: true) {
            StreakCelebrationView(streak: streak, isNewBest: completedNewBest)

            Text("Mission Complete")
                .font(ClimbTypography.sans(27, weight: .semibold))
                .foregroundStyle(.white)

            Text(completionMessage(streak: streak))
                .font(ClimbTypography.sans(15, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 10) {
                CelebrationMetric(title: "Streak", value: "\(streak)", color: .climbGold)
                CelebrationMetric(title: "OVR", value: "\(ovr)", color: .climbSage)
                CelebrationMetric(title: "Journal", value: "Saved", color: .climbBlue)
            }
            .padding(.top, 4)

            PrimaryActionButton(title: "Close", systemImage: "xmark") {
                dismiss()
            }
            .padding(.top, 4)
        }
    }

    private func completionMessage(streak: Int) -> String {
        if completedNewBest {
            return "New best streak. Today counted because you finished the mission and reflected before moving on."
        }
        if streak <= 1 {
            return "Day 1 is locked in. Come back tomorrow and protect the next small promise."
        }
        return "\(streak) days in a row. Your streak grew because the mission and reflection are both complete."
    }

    private var reflectionIsValid: Bool {
        !hardestPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lessonLearned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !improvementPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func updateRemainingTime() {
        guard let focusEndsAt else {
            remainingSeconds = max(remainingSeconds - 1, 0)
            if remainingSeconds == 0 {
                phase = .reflection
                Task {
                    await viewModel.stopMissionFocus()
                }
            }
            return
        }

        remainingSeconds = Self.remainingSeconds(until: focusEndsAt)
        guard remainingSeconds == 0 else { return }
        phase = .reflection
        Task {
            await viewModel.stopMissionFocus()
        }
    }

    private static func remainingSeconds(until endDate: Date) -> Int {
        max(0, Int(ceil(endDate.timeIntervalSinceNow)))
    }

    private func beginFocusFlow() {
#if canImport(FamilyControls) && os(iOS)
        activitySelection = ScreenTimeActivitySelectionStore.loadSelection()
        if mission.appBlockingEnabled, viewModel.focusState != .authorized, viewModel.focusState != .active {
            Task {
                await viewModel.requestScreenTimeAuthorization()
                await MainActor.run {
                    if viewModel.focusState == .authorized || viewModel.focusState == .active {
                        if activitySelection.hasShieldableContent {
                            startFocusTimer()
                        } else {
                            shouldStartAfterActivityPicker = true
                            showActivityPicker = true
                        }
                    }
                }
            }
            return
        }

        if mission.appBlockingEnabled, !activitySelection.hasShieldableContent {
            shouldStartAfterActivityPicker = true
            showActivityPicker = true
            return
        }
#endif
        startFocusTimer()
    }

    private func startFocusTimer() {
        let existingEndDate = ActiveFocusMissionTimerStore.endDate(for: mission.id)
        let endDate = existingEndDate.flatMap { $0 > Date() ? $0 : nil }
            ?? Date().addingTimeInterval(TimeInterval(max(mission.durationMinutes, 1) * 60))
        focusEndsAt = endDate
        remainingSeconds = Self.remainingSeconds(until: endDate)
        phase = .running
        Task {
            await viewModel.startMission(mission, endsAt: endDate)
        }
    }

    private var beginFocusButtonTitle: String {
#if canImport(FamilyControls) && os(iOS)
        if mission.appBlockingEnabled, !ScreenTimeActivitySelectionStore.loadSelection().hasShieldableContent {
            return "Choose Apps & Begin"
        }
#endif
        return "Begin Focus"
    }

    private var timeString: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var focusProgress: Double {
        let totalSeconds = max(mission.durationMinutes * 60, 1)
        return 1 - (Double(remainingSeconds) / Double(totalSeconds))
    }

    private var focusStateLabel: String {
        switch viewModel.focusState {
        case .active:
            "Distractions blocked"
        case .authorized:
            "Access ready"
        case .permissionRequired:
            "Needs permission"
        case .selectionRequired:
            "Choose apps"
        case .denied:
            "Permission denied"
        case .simulated:
            "Focus active"
        case .unavailable:
            "Preparing"
        }
    }

    private var focusStateColor: Color {
        switch viewModel.focusState {
        case .active, .authorized, .simulated:
            .climbSage
        case .permissionRequired, .selectionRequired, .unavailable:
            .climbGold
        case .denied:
            .climbRed
        }
    }

    private var focusText: String {
        switch viewModel.focusState {
        case .active:
            "Selected distractions are blocked."
        case .authorized:
            "Screen Time access is ready."
        case .permissionRequired:
            "Screen Time permission is needed to block apps."
        case .selectionRequired:
            "Choose apps to block, then restart focus."
        case .denied:
            "Screen Time permission was denied."
        case .simulated:
            "Simulated focus is active."
        case .unavailable:
            "Focus mode is preparing."
        }
    }

    private var focusIcon: String {
        switch viewModel.focusState {
        case .active:
            "lock.shield"
        case .authorized:
            "checkmark.shield"
        case .permissionRequired:
            "shield.lefthalf.filled"
        case .selectionRequired:
            "square.grid.2x2"
        case .denied:
            "exclamationmark.shield"
        case .simulated:
            "moon"
        case .unavailable:
            "hourglass"
        }
    }
}

private enum MissionPhase: Hashable {
    case ready
    case running
    case reflection
    case failurePrompt
    case fallback
    case complete
}

#if canImport(FamilyControls) && os(iOS)
private struct FocusPreflightPanel: View {
    let authorizationState: FocusModeState
    let selectedItemCount: Int
    let templates: [FocusTemplateSummary]
    let activeTemplateID: String?
    let onRequestPermission: () -> Void
    let onChooseApps: () -> Void
    let onApplyTemplate: (FocusTemplateSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocking preflight")
                        .font(ClimbTypography.sans(18, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    Text(preflightSubtitle)
                        .font(ClimbTypography.sans(13, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                StatusBadge(text: readyForBlocking ? "Ready" : "Setup", color: readyForBlocking ? .climbGreen : .climbGold)
            }

            VStack(spacing: 10) {
                FocusPreflightRow(
                    systemImage: authorizationIcon,
                    title: "Screen Time access",
                    detail: authorizationDetail,
                    color: authorizationColor,
                    actionTitle: authorizationActionTitle,
                    action: onRequestPermission
                )

                FocusPreflightRow(
                    systemImage: selectedItemCount > 0 ? "app.badge.checkmark" : "square.grid.2x2",
                    title: "Apps selected",
                    detail: selectedItemCount > 0 ? "\(selectedItemCount) distractions selected" : "Choose apps, categories, or websites",
                    color: selectedItemCount > 0 ? .climbGreen : .climbGold,
                    actionTitle: selectedItemCount > 0 ? "Edit" : "Choose",
                    action: onChooseApps
                )
            }

            if !templates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Saved templates")
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.climbMuted)
                        .textCase(.uppercase)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(templates) { template in
                                FocusTemplateChip(
                                    template: template,
                                    isActive: template.id == activeTemplateID
                                ) {
                                    onApplyTemplate(template)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(15)
        .background(Color.climbBackgroundLifted.opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.065), lineWidth: 0.7)
        )
        .animation(ClimbMotion.standard, value: selectedItemCount)
        .animation(ClimbMotion.standard, value: activeTemplateID)
        .animation(ClimbMotion.standard, value: authorizationState)
    }

    private var readyForBlocking: Bool {
        (authorizationState == .authorized || authorizationState == .active) && selectedItemCount > 0
    }

    private var preflightSubtitle: String {
        readyForBlocking ? "Your shield is prepared before the timer begins." : "Handle setup once so the mission starts cleanly."
    }

    private var authorizationIcon: String {
        switch authorizationState {
        case .active, .authorized:
            "checkmark.shield.fill"
        case .denied:
            "exclamationmark.shield.fill"
        case .permissionRequired:
            "shield.lefthalf.filled"
        case .selectionRequired:
            "square.grid.2x2"
        case .simulated:
            "moon.fill"
        case .unavailable:
            "hourglass"
        }
    }

    private var authorizationDetail: String {
        switch authorizationState {
        case .active:
            "Blocking is active"
        case .authorized:
            "Permission approved"
        case .denied:
            "Open Settings to allow access"
        case .permissionRequired:
            "Permission needed before blocking"
        case .selectionRequired:
            "Access ready, selection needed"
        case .simulated:
            "Timer will run without blocking"
        case .unavailable:
            "Checking availability"
        }
    }

    private var authorizationColor: Color {
        switch authorizationState {
        case .active, .authorized:
            .climbGreen
        case .denied:
            .climbRed
        case .permissionRequired, .selectionRequired, .simulated, .unavailable:
            .climbGold
        }
    }

    private var authorizationActionTitle: String? {
        switch authorizationState {
        case .permissionRequired, .denied, .unavailable:
            authorizationState == .denied ? "Settings" : "Allow"
        case .active, .authorized, .selectionRequired, .simulated:
            nil
        }
    }
}

private struct FocusPreflightDisabledPanel: View {
    var body: some View {
        FocusPreflightRow(
            systemImage: "target",
            title: "Manual focus",
            detail: "App blocking is off for this mission",
            color: .climbGold,
            actionTitle: nil,
            action: {}
        )
        .padding(15)
        .background(Color.climbBackgroundLifted.opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.065), lineWidth: 0.7)
        )
    }
}

private struct FocusPreflightRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let color: Color
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text(detail)
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            if let actionTitle {
                Button(actionTitle) {
                    HapticFeedback.impact(.light)
                    action()
                }
                .buttonStyle(.plain)
                .font(ClimbTypography.sans(12, weight: .semibold))
                .foregroundStyle(Color.climbInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(color, in: Capsule())
            }
        }
        .padding(12)
        .background(Color.climbSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 0.7)
        )
    }
}

private struct FocusTemplateChip: View {
    let template: FocusTemplateSummary
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: template.systemImage)
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(isActive ? Color.climbInk : Color.climbGreen)
                    .frame(width: 30, height: 30)
                    .background(
                        isActive ? Color.white.opacity(0.28) : Color.climbGreen.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(isActive ? Color.climbInk : Color.climbMist)
                    Text("\(template.shieldableContentCount) blocked")
                        .font(ClimbTypography.sans(11, weight: .semibold))
                        .foregroundStyle(isActive ? Color.climbInk.opacity(0.65) : Color.climbTextSecondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(
                isActive ? Color.climbGreen : Color.climbSurface.opacity(0.76),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(isActive ? Color.white.opacity(0.20) : Color.white.opacity(0.065), lineWidth: 0.7)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
#endif

private struct StreakCelebrationView: View {
    let streak: Int
    let isNewBest: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringProgress = 0.08
    @State private var contentScale = 0.92
    @State private var glowIsVisible = false
    @State private var sparksVisible = false
    @State private var sparksExpanded = false

    var body: some View {
        ZStack {
            CelebrationSparks(isVisible: sparksVisible, isExpanded: sparksExpanded)

            Circle()
                .fill(Color.climbSurfaceRaised.opacity(0.92))
                .frame(width: 186, height: 186)
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: Color.climbGreen.opacity(glowIsVisible ? 0.30 : 0.12), radius: glowIsVisible ? 30 : 14, x: 0, y: 0)
                .shadow(color: .black.opacity(0.42), radius: 24, x: 0, y: 16)

            Circle()
                .stroke(Color.white.opacity(0.075), lineWidth: 11)
                .frame(width: 150, height: 150)

            Circle()
                .trim(from: 0, to: min(max(ringProgress, 0), 1))
                .stroke(
                    LinearGradient(
                        colors: [Color.climbGreen, Color.climbSage, Color.climbGold.opacity(0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.climbGreen.opacity(0.34), radius: 18, x: 0, y: 0)

            VStack(spacing: 5) {
                Image(systemName: isNewBest ? "flame.fill" : "checkmark.seal.fill")
                    .font(ClimbTypography.sans(24, weight: .semibold))
                    .foregroundStyle(isNewBest ? Color.climbGold : Color.climbGreen)
                    .symbolEffect(.bounce, value: ringProgress)

                Text("\(streak)")
                    .font(ClimbTypography.sans(58, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text(streak == 1 ? "day streak" : "day streak")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)
            }
            .scaleEffect(contentScale)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 214)
        .onAppear(perform: animateIn)
    }

    private func animateIn() {
        guard !reduceMotion else {
            ringProgress = 1
            contentScale = 1
            glowIsVisible = true
            return
        }

        withAnimation(ClimbMotion.slow) {
            ringProgress = 1
            contentScale = 1
            glowIsVisible = true
        }

        withAnimation(.easeOut(duration: 0.12).delay(0.08)) {
            sparksVisible = true
        }

        withAnimation(.easeOut(duration: 0.82).delay(0.10)) {
            sparksExpanded = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.84) {
            withAnimation(.easeOut(duration: 0.22)) {
                sparksVisible = false
            }
        }
    }
}

private struct CelebrationSparks: View {
    let isVisible: Bool
    let isExpanded: Bool

    private let count = 18

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 3) ? Color.climbGold : Color.climbGreen)
                    .frame(width: 4, height: 12)
                    .rotationEffect(.degrees(Double(index) * 21))
                    .offset(sparkOffset(for: index))
                    .opacity(isVisible ? (isExpanded ? 0 : 0.88) : 0)
            }
        }
        .frame(width: 220, height: 220)
        .allowsHitTesting(false)
    }

    private func sparkOffset(for index: Int) -> CGSize {
        let angle = (Double(index) / Double(count)) * Double.pi * 2
        let radius = isExpanded ? CGFloat(96 + (index % 4) * 8) : CGFloat(58)
        return CGSize(width: CGFloat(cos(angle)) * radius, height: CGFloat(sin(angle)) * radius)
    }
}

private struct CelebrationMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            Text(title)
                .font(ClimbTypography.sans(11, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 0.8)
        )
    }
}

private struct FocusTimerRing: View {
    let progress: Double
    let time: String
    let icon: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.climbSurfaceGlass)
                .frame(width: 248, height: 248)
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.42), radius: 34, x: 0, y: 22)

            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 12)
                .frame(width: 214, height: 214)

            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 214, height: 214)
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.30), radius: 18, x: 0, y: 0)
                .animation(ClimbMotion.standard, value: progress)

            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(ClimbTypography.sans(22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: Circle())

                Text(time)
                    .font(ClimbTypography.sans(54, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text("stay present")
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)
            }
        }
    }
}
