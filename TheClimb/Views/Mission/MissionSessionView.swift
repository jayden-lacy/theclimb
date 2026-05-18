import SwiftUI

struct MissionSessionView: View {
    @ObservedObject var viewModel: AppViewModel
    let mission: Mission

    @Environment(\.dismiss) private var dismiss
    @State private var phase: MissionPhase
    @State private var remainingSeconds: Int
    @State private var hardestPart = ""
    @State private var lessonLearned = ""
    @State private var effortRating = 3.0
    @State private var improvementPlan = ""
    @State private var mood: MoodRating = .steady
    @State private var failureReason = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(viewModel: AppViewModel, mission: Mission) {
        self.viewModel = viewModel
        self.mission = mission
        _remainingSeconds = State(initialValue: mission.durationMinutes * 60)
        _phase = State(initialValue: mission.status == .completed ? .complete : .ready)
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
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                phase = .reflection
            }
        }
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
        case .failed:
            failureContent
        case .fallback:
            fallbackContent
        case .complete:
            completeContent
        }
    }

    private var readyContent: some View {
        ClimbCard(padding: 22, cornerRadius: 30, isProminent: true) {
            SectionTitle(title: "Before You Start", subtitle: "Make the room quiet before the timer begins.")
            VStack(spacing: 10) {
                ForEach(mission.extraChallenges, id: \.self) { challenge in
                    Label(challenge, systemImage: "checkmark.circle")
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(Color.climbBackgroundLifted.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            PrimaryActionButton(title: "Begin Focus", systemImage: "play.fill") {
                phase = .running
                Task {
                    await viewModel.startMission(mission)
                }
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
                    }

                    Button {
                        phase = .failed
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
        ClimbCard(padding: 22, cornerRadius: 30, isProminent: true) {
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
                    .tint(.climbGreen)
            }

            TextField("Improvement plan", text: $improvementPlan, axis: .vertical)
                .lineLimit(2...4)
                .formFieldStyle()

            PrimaryActionButton(
                title: "Submit Reflection",
                systemImage: "square.and.pencil",
                isDisabled: !reflectionIsValid
            ) {
                Task {
                    await viewModel.completeMission(
                        missionID: mission.id,
                        hardestPart: hardestPart,
                        lessonLearned: lessonLearned,
                        effortRating: Int(effortRating),
                        improvementPlan: improvementPlan,
                        mood: mood
                    )
                    phase = .complete
                }
            }
        }
    }

    private var failureContent: some View {
        ClimbCard(cornerRadius: 30) {
            SectionTitle(title: "Recovery")
            TextField("Why did this mission fail?", text: $failureReason, axis: .vertical)
                .lineLimit(2...5)
                .formFieldStyle()
            PrimaryActionButton(
                title: "Log Failure",
                systemImage: "arrow.counterclockwise.circle",
                tint: .climbRed,
                isDisabled: failureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                Task {
                    await viewModel.failMission(missionID: mission.id, reason: failureReason)
                    phase = .fallback
                }
            }
        }
    }

    private var fallbackContent: some View {
        ClimbCard(cornerRadius: 30) {
            SectionTitle(title: mission.fallbackTitle)
            Text(mission.fallbackSummary)
                .font(ClimbTypography.sans(15))
                .foregroundStyle(Color.climbTextSecondary)
            PrimaryActionButton(title: "Complete Recovery", systemImage: "checkmark.seal") {
                Task {
                    await viewModel.completeFallback(missionID: mission.id)
                    dismiss()
                }
            }
        }
    }

    private var completeContent: some View {
        ClimbCard(cornerRadius: 30, isProminent: true) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.climbGreen)
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
            .climbGreen
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
            "Choose apps to block in Profile to enable shielding."
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
    case failed
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
