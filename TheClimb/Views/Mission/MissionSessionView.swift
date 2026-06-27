import SwiftUI
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

struct MissionSessionView: View {
    @ObservedObject var viewModel: AppViewModel
    let mission: Mission

    @Environment(\.dismiss) private var dismiss
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
#if canImport(FamilyControls) && os(iOS)
    @State private var showActivityPicker = false
    @State private var activitySelection = FamilyActivitySelection()
    @State private var shouldStartAfterActivityPicker = false
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
        }
        .onChange(of: activitySelection) { _, newSelection in
            ScreenTimeActivitySelectionStore.saveSelection(newSelection)
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
        ClimbCard(padding: 22, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("MISSION")
                    .font(ClimbTypography.sans(12, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.climbMuted)
                Text(mission.title)
                    .font(ClimbTypography.sans(28, weight: .bold))
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
        ClimbCard(padding: 22, cornerRadius: 24, isProminent: true) {
            SectionTitle(title: "Before You Start", subtitle: "Make the room quiet before the timer begins.")
            Text("Set your phone down, breathe once, and give this mission your full attention.")
                .font(ClimbTypography.sans(15, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
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
                        .font(ClimbTypography.sans(11, weight: .bold))
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
                            .font(ClimbTypography.sans(26, weight: .bold))
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
        ClimbCard(padding: 22, cornerRadius: 24, isProminent: true) {
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
                Task {
                    let didComplete = await viewModel.completeMission(
                        missionID: mission.id,
                        hardestPart: hardestPart,
                        lessonLearned: lessonLearned,
                        effortRating: Int(effortRating),
                        improvementPlan: improvementPlan,
                        mood: mood
                    )
                    if didComplete {
                        phase = .complete
                    }
                    isSubmittingResult = false
                }
            }
        }
    }

    private var failureContent: some View {
        ClimbCard(cornerRadius: 22) {
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
        ClimbCard(cornerRadius: 22) {
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
        ClimbCard(cornerRadius: 24, isProminent: true) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.climbSage)
            Text("Mission Complete")
                .font(ClimbTypography.sans(24, weight: .bold))
                .foregroundStyle(.white)
            Text("Your OVR, streak, journal, and progress history have been updated.")
                .font(ClimbTypography.sans(15))
                .foregroundStyle(Color.climbTextSecondary)
            PrimaryActionButton(title: "Close", systemImage: "xmark") {
                dismiss()
            }
        }
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
        if mission.appBlockingEnabled, !activitySelection.hasShieldableContent {
            shouldStartAfterActivityPicker = true
            Task {
                if viewModel.focusState != .authorized, viewModel.focusState != .active {
                    await viewModel.requestScreenTimeAuthorization()
                }
                await MainActor.run {
                    showActivityPicker = true
                }
            }
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
                    .font(ClimbTypography.sans(22, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: Circle())

                Text(time)
                    .font(ClimbTypography.sans(54, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text("stay present")
                    .font(ClimbTypography.sans(11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)
            }
        }
    }
}
