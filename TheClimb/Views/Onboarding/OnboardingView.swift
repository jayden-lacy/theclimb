import SwiftUI

private enum OnboardingAuthProvider {
    case apple
    case google
}

private enum OnboardingAccountMode {
    case create
    case login
}

private enum OnboardingAccountEntry {
    case providers
    case email
}

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: AppViewModel

    @State private var step: OnboardingStep = .opening
    @State private var selectedGoals: Set<String> = []
    @State private var obstacle: OnboardingObstacle?
    @State private var spiritualStartingPoint: SpiritualStartingPoint?
    @State private var ageChoice: AgeChoice?
    @State private var dailyCommitmentMinutes = 10
    @State private var preferredTimeWindow: DailyClimbWindow = .evening
    @State private var reminderTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var whyStarted = ""
    @State private var customWhyStarted = ""
    @State private var firstStepCompletedAt: Date?
    @State private var timerSecondsRemaining = 60
    @State private var missionAttemptState: OnboardingMissionAttemptState = .idle
    @State private var missionAttemptID = 0
    @State private var preparationLineIndex = 0
    @State private var markDrawProgress: CGFloat = 0

    @State private var accountMode: OnboardingAccountMode = .create
    @State private var accountEntry: OnboardingAccountEntry = .providers
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var authenticatedUser: FirebaseSignedInUser?
    @State private var authenticatedProvider: OnboardingAuthProvider?
    @State private var isSubmitting = false

    private let goals = OnboardingGoal.options

    var body: some View {
        ZStack {
            ClimbScreenBackground()
            OnboardingPathBackdrop(progress: step.pathProgress)

            VStack(spacing: 0) {
                if step.showsProgressHeader {
                    OnboardingProgressHeader(
                        progress: step.pathProgress,
                        canGoBack: canGoBack,
                        onBack: goBack
                    )
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                }

                GeometryReader { proxy in
                    ScrollView(showsIndicators: false) {
                        content
                            .id(step)
                            .transition(.climbScreen)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(
                                minHeight: step == .opening ? max(proxy.size.height - 16, 0) : nil,
                                alignment: .center
                            )
                            .padding(.horizontal, 22)
                            .padding(.top, step == .opening ? 0 : 24)
                            .padding(.bottom, contentBottomPadding)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let action = pinnedAction {
                OnboardingBottomAction(action: action)
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : ClimbMotion.standard, value: step)
        .task(id: stepTaskID) {
            await runStepTask(for: step)
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onAppear {
            guard !reduceMotion else {
                markDrawProgress = 1
                return
            }
            withAnimation(.easeOut(duration: 1.4)) {
                markDrawProgress = 1
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .opening:
            openingStep
        case .goals:
            goalsStep
        case .obstacle:
            obstacleStep
        case .spiritualStartingPoint:
            spiritualStartingPointStep
        case .age:
            ageStep
        case .commitment:
            commitmentStep
        case .schedule:
            scheduleStep
        case .building:
            buildingStep
        case .pathReveal:
            pathRevealStep
        case .missionIntro:
            missionIntroStep
        case .missionTimer:
            missionTimerStep
        case .reason:
            reasonStep
        case .milestone:
            milestoneStep
        case .notification:
            notificationStep
        case .account:
            accountStep
        }
    }

    private var openingStep: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 28)

            VStack(spacing: 28) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 154, height: 154)
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .stroke(Color.climbSurfaceLine.opacity(0.90), lineWidth: 0.8)
                    }
                    .shadow(color: Color.climbBlue.opacity(0.14), radius: 28)
                    .opacity(markDrawProgress)
                    .scaleEffect(0.96 + (0.04 * markDrawProgress))
                    .accessibilityHidden(true)

                VStack(spacing: 14) {
                    Text("THE CLIMB")
                        .font(ClimbTypography.sans(34, weight: .semibold))
                        .foregroundStyle(Color.climbMist)

                    VStack(spacing: 5) {
                        Text("Faith isn’t built in one moment.")
                        Text("It’s built one step at a time.")
                    }
                    .font(ClimbTypography.serif(23))
                    .foregroundStyle(Color.climbWarm.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                }
            }

            Spacer(minLength: 24)

            VStack(spacing: 14) {
                PrimaryActionButton(title: "Begin the climb", systemImage: "arrow.up.right") {
                    setStep(.goals)
                }

                Button("I already have an account") {
                    HapticFeedback.selection()
                    accountMode = .login
                    accountEntry = .providers
                    setStep(.account)
                }
                .buttonStyle(.plain)
                .font(ClimbTypography.sans(14, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading(
                title: "What do you want to change most right now?",
                subtitle: "We’ll build your climb around it. Choose up to three."
            )

            VStack(spacing: 10) {
                ForEach(goals) { goal in
                    OnboardingChoiceRow(
                        title: goal.title,
                        systemImage: goal.systemImage,
                        isSelected: selectedGoals.contains(goal.title)
                    ) {
                        toggleGoal(goal.title)
                    }
                }
            }
        }
    }

    private var obstacleStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading(
                title: "What’s been getting in the way?",
                subtitle: "Be honest. This stays between you and your climb."
            )

            VStack(spacing: 10) {
                ForEach(OnboardingObstacle.options) { option in
                    OnboardingChoiceRow(
                        title: option.title,
                        systemImage: option.systemImage,
                        isSelected: obstacle == option
                    ) {
                        obstacle = option
                    }
                }
            }
        }
    }

    private var spiritualStartingPointStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading(
                title: "Where would you say you are with God right now?",
                subtitle: "This sets the pace. It is not a score of your faith."
            )

            SpiritualMountainSelector(selection: $spiritualStartingPoint)
        }
    }

    private var ageStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading(
                title: "What season of life are you in?",
                subtitle: "Lessons mature with you. The Climb is for ages 13 and older."
            )

            VStack(spacing: 10) {
                ForEach(AgeChoice.options) { choice in
                    OnboardingChoiceRow(
                        title: choice.title,
                        detail: choice.detail,
                        systemImage: choice.systemImage,
                        isSelected: ageChoice == choice
                    ) {
                        ageChoice = choice
                    }
                }
            }
        }
    }

    private var commitmentStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading(
                title: "How much time can you give God every day—even on a bad day?",
                subtitle: "Choose the commitment you can keep when motivation is low."
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(DailyCommitment.options) { option in
                    CommitmentChoice(
                        option: option,
                        isSelected: dailyCommitmentMinutes == option.minutes
                    ) {
                        dailyCommitmentMinutes = option.minutes
                    }
                }
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading(
                title: "When will you make time for God?",
                subtitle: "Choose the moment you can protect most consistently."
            )

            VStack(spacing: 10) {
                ForEach(DailyClimbWindow.allCases) { window in
                    OnboardingChoiceRow(
                        title: window.title,
                        systemImage: scheduleIcon(for: window),
                        isSelected: preferredTimeWindow == window
                    ) {
                        preferredTimeWindow = window
                        if window != .custom {
                            setReminderHour(window.defaultHour)
                        }
                    }
                }
            }

            DatePicker("Daily Climb time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(Color.climbMist)
                .tint(.climbGreen)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.climbSurfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.climbHairline, lineWidth: 0.8)
                )

            Text("\(reminderText) becomes your daily Climb time.")
                .font(ClimbTypography.serif(20))
                .foregroundStyle(Color.climbWarm)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }

    private var buildingStep: some View {
        VStack(spacing: 34) {
            Spacer(minLength: 70)

            BuildingPathMark(progress: min(1, CGFloat(preparationLineIndex + 1) / CGFloat(preparationLines.count)))
                .frame(width: 170, height: 210)
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text("Building your climb...")
                    .font(ClimbTypography.sans(26, weight: .semibold))
                    .foregroundStyle(Color.climbMist)

                Text(preparationLines[min(preparationLineIndex, preparationLines.count - 1)])
                    .id(preparationLineIndex)
                    .font(ClimbTypography.serif(21))
                    .foregroundStyle(Color.climbWarm.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .transition(.opacity)
                    .frame(minHeight: 58)
            }

            Spacer(minLength: 70)
        }
        .frame(maxWidth: .infinity)
    }

    private var pathRevealStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR FIRST 7 DAYS")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbSage)

                Text("Your path is ready.")
                    .font(ClimbTypography.serif(34))
                    .foregroundStyle(Color.climbMist)

                Text("A clear first week, built around the change you chose.")
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }

            FirstWeekPathView(checkpoints: firstWeekPath)

            Text("Your missions, Scripture, prayers, and reflections will adapt as you progress.")
                .font(ClimbTypography.sans(14, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(4)
        }
    }

    private var missionIntroStep: some View {
        VStack(alignment: .leading, spacing: 26) {
            OnboardingEyebrow(text: "DAY 1 · SHOW UP")

            VStack(alignment: .leading, spacing: 12) {
                Text("Before you improve your relationship with God, you have to make room for Him.")
                    .font(ClimbTypography.serif(30))
                    .foregroundStyle(Color.climbMist)
                    .lineSpacing(5)

                Text("Your first step")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbSage)
                    .padding(.top, 8)

                Text("Put your phone down for 60 seconds.")
                    .font(ClimbTypography.sans(22, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("PRAY")
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
                Text("“God, I’m here. Help me become willing to obey You, even when I don’t feel like it.”")
                    .font(ClimbTypography.serif(22))
                    .foregroundStyle(Color.climbWarm)
                    .lineSpacing(5)
            }
            .padding(.vertical, 18)
            .overlay(alignment: .top) { Divider().overlay(Color.climbDivider) }
            .overlay(alignment: .bottom) { Divider().overlay(Color.climbDivider) }

            ScriptureMoment(scripture: firstScripture)

            Button("Do this later") {
                HapticFeedback.selection()
                setStep(.reason)
            }
            .buttonStyle(.plain)
            .font(ClimbTypography.sans(13, weight: .semibold))
            .foregroundStyle(Color.climbMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var missionTimerStep: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 24)

            OnboardingEyebrow(text: missionTimerEyebrow)

            ZStack {
                Circle()
                    .stroke(missionAttemptFailed ? Color.climbRed.opacity(0.16) : Color.climbDivider, lineWidth: 7)

                Circle()
                    .trim(from: 0, to: timerProgress)
                    .stroke(missionTimerTint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: missionTimerTint.opacity(0.18), radius: 16)

                if missionAttemptFailed {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.right")
                            .font(ClimbTypography.sans(46, weight: .medium))
                            .foregroundStyle(Color.climbRed)
                        Text("FOCUS BROKEN")
                            .font(ClimbTypography.sans(11, weight: .semibold))
                            .foregroundStyle(Color.climbRed.opacity(0.9))
                    }
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else if !missionAttemptCompleted {
                    VStack(spacing: 4) {
                        Text("\(timerSecondsRemaining)")
                            .font(ClimbTypography.sans(58, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.climbMist)
                            .contentTransition(.numericText())
                        Text("SECONDS")
                            .font(ClimbTypography.sans(11, weight: .semibold))
                            .foregroundStyle(Color.climbMuted)
                    }
                } else {
                    Image(systemName: "checkmark")
                        .font(ClimbTypography.sans(48, weight: .semibold))
                        .foregroundStyle(Color.climbSage)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
            .frame(width: 238, height: 238)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(missionTimerAccessibilityLabel)

            Text(missionTimerMessage)
                .font(ClimbTypography.serif(22))
                .foregroundStyle(missionAttemptFailed ? Color.climbMist : Color.climbWarm.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 310)

            if missionAttemptCompleted {
                PrimaryActionButton(title: "Keep climbing", systemImage: "arrow.up.right") {
                    setStep(.reason)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if missionAttemptFailed {
                VStack(spacing: 10) {
                    PrimaryActionButton(title: "Try the 60 seconds again", systemImage: "arrow.counterclockwise") {
                        retryOnboardingMission()
                    }

                    Button("Continue without completing") {
                        HapticFeedback.selection()
                        setStep(.reason)
                    }
                    .buttonStyle(.plain)
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
                    .padding(.vertical, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private var reasonStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading(
                title: "Before you keep climbing...",
                subtitle: "Why does this matter to you? We’ll bring this back when showing up gets hard."
            )

            VStack(spacing: 10) {
                ForEach(reasonOptions, id: \.self) { reason in
                    OnboardingChoiceRow(
                        title: reason,
                        systemImage: "quote.opening",
                        isSelected: whyStarted == reason
                    ) {
                        whyStarted = reason
                        customWhyStarted = ""
                    }
                }

                OnboardingChoiceRow(
                    title: "Write my own",
                    systemImage: "pencil.line",
                    isSelected: whyStarted == customReasonMarker
                ) {
                    whyStarted = customReasonMarker
                }
            }

            if whyStarted == customReasonMarker {
                TextField("Why I’m starting...", text: $customWhyStarted, axis: .vertical)
                    .lineLimit(3...5)
                    .formFieldStyle()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var milestoneStep: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 30)

            OnboardingEyebrow(text: "THE FIRST MILESTONE")

            VStack(spacing: 10) {
                Text(firstStepCompletedAt == nil ? "Your first step is waiting." : "You took the first step.")
                    .font(ClimbTypography.serif(34))
                    .foregroundStyle(Color.climbMist)
                    .multilineTextAlignment(.center)

                Text("Don’t worry about 30 days yet.")
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }

            ThreeDayMilestoneView(firstDayComplete: firstStepCompletedAt != nil)

            VStack(spacing: 6) {
                Text("Let’s make it to Day 3.")
                    .font(ClimbTypography.sans(24, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text("Then we’ll extend the path to 7, 14, and 30.")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }

            Spacer(minLength: 50)
        }
        .frame(maxWidth: .infinity)
    }

    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingHeading(
                title: "Protect your Climb",
                subtitle: "You chose \(reminderText) as your time with God."
            )

            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(ClimbTypography.sans(26, weight: .semibold))
                    .foregroundStyle(Color.climbSage)
                    .accessibilityHidden(true)

                Text("Want The Climb to remind you when it’s time?")
                    .font(ClimbTypography.serif(26))
                    .foregroundStyle(Color.climbWarm)
                    .lineSpacing(4)
            }
            .padding(.vertical, 12)

            VStack(spacing: 12) {
                PrimaryActionButton(
                    title: "Remind me at \(reminderText)",
                    systemImage: "bell.fill"
                ) {
                    requestNotificationsAndContinue()
                }

                Button("Not now") {
                    HapticFeedback.selection()
                    setStep(.account)
                }
                .buttonStyle(.plain)
                .font(ClimbTypography.sans(14, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeading(
                title: accountMode == .login ? "Welcome back" : "Save your progress",
                subtitle: accountMode == .login ? "Sign in to return to your climb." : "You’ve already started. Save this path across your devices."
            )

            if accountMode == .create {
                HStack(spacing: 0) {
                    AccountProgressStat(value: firstStepCompletedAt == nil ? "0" : "1", label: "mission")
                    AccountProgressStat(value: resolvedWhyStarted.isEmpty ? "0" : "1", label: "commitment")
                    AccountProgressStat(value: firstStepCompletedAt == nil ? "0" : "1", label: "day climbing")
                }
                .padding(.vertical, 16)
                .overlay(alignment: .top) { Divider().overlay(Color.climbDivider) }
                .overlay(alignment: .bottom) { Divider().overlay(Color.climbDivider) }
            }

            if accountEntry == .providers {
                VStack(spacing: 12) {
                    SecondaryActionButton(title: providerTitle(.apple), systemImage: "apple.logo") {
                        signInWithApple()
                    }
                    .disabled(isSubmitting)

                    SecondaryActionButton(title: providerTitle(.google), systemImage: "g.circle") {
                        signInWithGoogle()
                    }
                    .disabled(isSubmitting)

                    SecondaryActionButton(
                        title: accountMode == .login ? "Sign in with Email" : "Continue with Email",
                        systemImage: "envelope"
                    ) {
                        accountEntry = .email
                    }
                    .disabled(isSubmitting)
                }
            } else {
                VStack(spacing: 12) {
                    if accountMode == .create {
                        TextField("Name", text: $displayName)
                            .textContentType(.name)
                            .formFieldStyle()
                    }

                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .formFieldStyle()

                    SecureField("Password", text: $password)
                        .textContentType(accountMode == .create ? .newPassword : .password)
                        .formFieldStyle()

                    AccountValidationNotice(message: accountValidationMessage, isReady: isEmailAccountReady)
                }
            }

            if !viewModel.isReonboardingExistingAccount {
                Button(accountMode == .create ? "Already have an account? Log in" : "New here? Build my climb") {
                    HapticFeedback.selection()
                    accountMode = accountMode == .create ? .login : .create
                    accountEntry = .providers
                    authenticatedUser = nil
                    authenticatedProvider = nil
                    password = ""
                }
                .buttonStyle(.plain)
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbSage)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 8) {
                Text("By continuing, you agree to our Terms and Privacy Policy.")
                    .foregroundStyle(Color.climbMuted)

                HStack(spacing: 16) {
                    Button("Terms") { openURL(LegalDocument.termsOfService.onlineURL) }
                    Button("Privacy") { openURL(LegalDocument.privacyPolicy.onlineURL) }
                }
                .foregroundStyle(Color.climbTextSecondary)
            }
            .font(ClimbTypography.sans(11, weight: .medium))
            .frame(maxWidth: .infinity)
        }
    }

    private var pinnedAction: OnboardingAction? {
        switch step {
        case .opening, .building, .missionTimer, .notification, .account:
            if step == .account, accountEntry == .email {
                return OnboardingAction(
                    title: isSubmitting ? "Saving..." : (accountMode == .login ? "Log in" : "Save my climb"),
                    systemImage: accountMode == .login ? "arrow.right" : "checkmark",
                    isDisabled: !isEmailAccountReady || isSubmitting,
                    action: submitEmailAccount
                )
            }
            return nil
        case .goals:
            return continueAction(disabled: selectedGoals.isEmpty)
        case .obstacle:
            return continueAction(disabled: obstacle == nil)
        case .spiritualStartingPoint:
            return continueAction(disabled: spiritualStartingPoint == nil)
        case .age:
            return continueAction(disabled: ageChoice == nil)
        case .commitment:
            return continueAction()
        case .schedule:
            return OnboardingAction(title: "Set my time", systemImage: "clock", action: advance)
        case .pathReveal:
            return OnboardingAction(title: "Start Day 1", systemImage: "arrow.up.right", action: advance)
        case .missionIntro:
            return OnboardingAction(
                title: missionAttemptCompleted ? "Return to completion" : "I’m ready",
                systemImage: missionAttemptCompleted ? "checkmark" : "play.fill",
                action: advance
            )
        case .reason:
            return continueAction(disabled: resolvedWhyStarted.isEmpty)
        case .milestone:
            return OnboardingAction(title: "Start my 3-day climb", systemImage: "flag.fill", action: advance)
        }
    }

    private func continueAction(disabled: Bool = false) -> OnboardingAction {
        OnboardingAction(title: "Continue", systemImage: "arrow.right", isDisabled: disabled, action: advance)
    }

    private var canGoBack: Bool {
        guard !isSubmitting, step != .opening, step != .building else { return false }
        if step == .missionTimer {
            return missionAttemptCompleted || missionAttemptFailed
        }
        return true
    }

    private var contentBottomPadding: CGFloat {
        pinnedAction == nil ? 36 : 126
    }

    private var selectedGoalList: [String] {
        goals.map(\.title).filter(selectedGoals.contains)
    }

    private var resolvedStruggle: Struggle {
        obstacle?.struggle ?? .discipline
    }

    private var firstWeekPath: [FirstWeekCheckpoint] {
        OnboardingPersonalization.firstWeekPath(goals: selectedGoalList, struggle: resolvedStruggle)
    }

    private var reminderText: String {
        reminderTime.formatted(date: .omitted, time: .shortened)
    }

    private var preparationLines: [String] {
        let primaryGoal = selectedGoalList.first ?? "a faithful daily rhythm"
        return [
            "Focusing on \(primaryGoal.lowercased())",
            "Helping you face \((obstacle?.title ?? "inconsistency").lowercased())",
            "Built around \(dailyCommitmentMinutes) minutes \(preferredTimeWindow.title.lowercased())",
            "Starting at a pace you can sustain"
        ]
    }

    private var reasonOptions: [String] {
        var options = [
            "I want a real relationship with God.",
            "I’m tired of repeating the same habits."
        ]

        if selectedGoalList.contains(where: { $0.localizedCaseInsensitiveContains("disciplin") }) {
            options.append("I want to become disciplined.")
        } else if selectedGoalList.contains(where: { $0.localizedCaseInsensitiveContains("prayer") }) {
            options.append("I want prayer to become part of who I am.")
        } else if selectedGoalList.contains(where: { $0.localizedCaseInsensitiveContains("Scripture") }) {
            options.append("I want God’s Word to shape my decisions.")
        } else {
            options.append("I want to become faithful with my attention.")
        }

        options.append("I want God to change who I’m becoming.")
        return options
    }

    private let customReasonMarker = "__custom__"

    private var resolvedWhyStarted: String {
        if whyStarted == customReasonMarker {
            return customWhyStarted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return whyStarted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var firstScripture: OnboardingScripture {
        if selectedGoalList.contains(where: { $0.localizedCaseInsensitiveContains("prayer") }) {
            return OnboardingScripture(reference: "1 Thessalonians 5:17 (WEB)", text: "Pray without ceasing.")
        }
        if selectedGoalList.contains(where: { $0.localizedCaseInsensitiveContains("Scripture") }) {
            return OnboardingScripture(reference: "Psalm 119:105 (WEB)", text: "Your word is a lamp to my feet, and a light for my path.")
        }
        if resolvedStruggle == .purity {
            return OnboardingScripture(reference: "2 Timothy 1:7 (WEB)", text: "For God didn’t give us a spirit of fear, but of power, love, and self-control.")
        }
        if selectedGoalList.contains(where: { $0.localizedCaseInsensitiveContains("peace") }) {
            return OnboardingScripture(reference: "Isaiah 26:3 (WEB)", text: "You will keep whoever’s mind is steadfast in perfect peace, because he trusts in you.")
        }
        return OnboardingScripture(reference: "James 4:8 (WEB)", text: "Draw near to God, and he will draw near to you.")
    }

    private var timerProgress: Double {
        missionAttemptCompleted ? 1 : Double(60 - timerSecondsRemaining) / 60
    }

    private var missionAttemptCompleted: Bool {
        firstStepCompletedAt != nil || missionAttemptState == .completed
    }

    private var missionAttemptFailed: Bool {
        missionAttemptState == .failed
    }

    private var missionTimerEyebrow: String {
        if missionAttemptFailed { return "MISSION INTERRUPTED" }
        return missionAttemptCompleted ? "DAY 1 STARTED" : "BE STILL"
    }

    private var missionTimerMessage: String {
        if missionAttemptFailed {
            return "You left before the minute was finished. Come back, begin again, and keep the commitment."
        }
        if missionAttemptCompleted {
            return "You made room for God before asking the app to do anything for you."
        }
        return "Stay here. Let the noise settle."
    }

    private var missionTimerAccessibilityLabel: String {
        if missionAttemptFailed {
            return "Mission interrupted with \(timerSecondsRemaining) seconds remaining"
        }
        return missionAttemptCompleted ? "Day 1 started" : "\(timerSecondsRemaining) seconds remaining"
    }

    private var missionTimerTint: Color {
        missionAttemptFailed ? .climbRed : .climbSage
    }

    private var stepTaskID: OnboardingStepTaskID {
        OnboardingStepTaskID(step: step, missionAttemptID: missionAttemptID)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isEmailValid: Bool {
        let parts = normalizedEmail.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let local = parts.first,
              let domain = parts.last,
              !local.isEmpty,
              domain.contains("."),
              !domain.hasPrefix("."),
              !domain.hasSuffix(".") else {
            return false
        }
        return !normalizedEmail.contains(" ") && !normalizedEmail.contains("..")
    }

    private var isEmailAccountReady: Bool {
        isEmailValid && password.count >= 6 && (accountMode == .login || !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var accountValidationMessage: String {
        if normalizedEmail.isEmpty && password.isEmpty {
            return "Enter a valid email and a password with at least 6 characters."
        }
        if accountMode == .create && displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter your name before saving your climb."
        }
        if !isEmailValid {
            return "Enter a valid email address before continuing."
        }
        if password.count < 6 {
            return "Password must be at least 6 characters."
        }
        return accountMode == .login ? "Ready to log in." : "Ready to save your climb."
    }

    private func toggleGoal(_ title: String) {
        if selectedGoals.contains(title) {
            selectedGoals.remove(title)
        } else if selectedGoals.count < 3 {
            selectedGoals.insert(title)
        } else {
            HapticFeedback.impact(.medium)
        }
    }

    private func setReminderHour(_ hour: Int) {
        reminderTime = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: reminderTime) ?? reminderTime
    }

    private func scheduleIcon(for window: DailyClimbWindow) -> String {
        switch window {
        case .morning: "sunrise"
        case .afterSchoolOrWork: "backpack"
        case .evening: "sunset"
        case .beforeBed: "moon.stars"
        case .custom: "clock"
        }
    }

    private func advance() {
        switch step {
        case .schedule:
            setStep(.building)
        case .missionIntro:
            if missionAttemptCompleted {
                setStep(.missionTimer)
            } else {
                startOnboardingMission()
            }
        default:
            setStep(step.next)
        }
    }

    private func goBack() {
        guard canGoBack else { return }
        if step == .account && accountMode == .login {
            setStep(.opening)
            return
        }
        setStep(step.previous)
    }

    private func setStep(_ newStep: OnboardingStep) {
        if reduceMotion {
            step = newStep
        } else {
            withAnimation(ClimbMotion.focus) {
                step = newStep
            }
        }
    }

    private func startOnboardingMission() {
        timerSecondsRemaining = 60
        firstStepCompletedAt = nil
        missionAttemptState = .running
        missionAttemptID += 1
        setStep(.missionTimer)
    }

    private func retryOnboardingMission() {
        HapticFeedback.impact(.medium)
        if reduceMotion {
            startOnboardingMission()
        } else {
            withAnimation(ClimbMotion.focus) {
                startOnboardingMission()
            }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            guard step == .missionTimer,
                  missionAttemptState == .running,
                  firstStepCompletedAt == nil,
                  timerSecondsRemaining > 0 else { return }
            missionAttemptState = .interrupted
        case .active:
            guard step == .missionTimer, missionAttemptState == .interrupted else { return }
            HapticFeedback.impact(.medium)
            if reduceMotion {
                missionAttemptState = .failed
            } else {
                withAnimation(ClimbMotion.focus) {
                    missionAttemptState = .failed
                }
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    private func runStepTask(for currentStep: OnboardingStep) async {
        switch currentStep {
        case .building:
            preparationLineIndex = 0
            for index in preparationLines.indices.dropFirst() {
                try? await Task.sleep(for: .milliseconds(560))
                guard !Task.isCancelled, step == .building else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    preparationLineIndex = index
                }
            }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, step == .building else { return }
            setStep(.pathReveal)
        case .missionTimer:
            guard missionAttemptState == .running else { return }
            while timerSecondsRemaining > 0, missionAttemptState == .running {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled,
                      step == .missionTimer,
                      missionAttemptState == .running else { return }
                timerSecondsRemaining -= 1
            }
            guard firstStepCompletedAt == nil, missionAttemptState == .running else { return }
            if reduceMotion {
                missionAttemptState = .completed
            } else {
                withAnimation(ClimbMotion.focus) {
                    missionAttemptState = .completed
                }
            }
            firstStepCompletedAt = Date()
            HapticFeedback.success()
        default:
            return
        }
    }

    private func requestNotificationsAndContinue() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            await viewModel.requestNotificationAuthorization()
            isSubmitting = false
            setStep(.account)
        }
    }

    private func submitEmailAccount() {
        guard isEmailAccountReady, !isSubmitting else { return }
        if accountMode == .login {
            isSubmitting = true
            Task { @MainActor in
                defer { isSubmitting = false }
                await viewModel.signInWithEmailForOnboarding(email: email, password: password)
            }
        } else {
            Task { await finalizeOnboarding() }
        }
    }

    private func signInWithGoogle() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            guard let user = await viewModel.signInWithGoogleForOnboarding() else { return }
            if accountMode == .login {
                await viewModel.loadSignedInAccountForOnboarding()
            } else if await viewModel.shouldContinueNewProfileAfterSocialSignIn() {
                authenticatedUser = user
                authenticatedProvider = .google
                displayName = user.displayName
                email = user.email
                await finalizeOnboarding(manageSubmittingState: false)
            }
        }
    }

    private func signInWithApple() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            guard let user = await viewModel.signInWithAppleForOnboarding() else { return }
            if accountMode == .login {
                await viewModel.loadSignedInAccountForOnboarding()
            } else if await viewModel.shouldContinueNewProfileAfterSocialSignIn() {
                authenticatedUser = user
                authenticatedProvider = .apple
                displayName = user.displayName
                email = user.email
                await finalizeOnboarding(manageSubmittingState: false)
            }
        }
    }

    @MainActor
    private func finalizeOnboarding(manageSubmittingState: Bool = true) async {
        guard !isSubmitting || !manageSubmittingState else { return }
        if manageSubmittingState {
            isSubmitting = true
        }
        defer {
            if manageSubmittingState {
                isSubmitting = false
            }
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let onboarding = OnboardingPersonalization(
            spiritualStartingPoint: spiritualStartingPoint ?? .growing,
            dailyCommitmentMinutes: dailyCommitmentMinutes,
            preferredTimeWindow: preferredTimeWindow,
            primaryObstacle: obstacle?.title ?? "Inconsistency",
            whyStarted: resolvedWhyStarted,
            firstStepCompletedAt: firstStepCompletedAt,
            initialMilestoneDays: 3
        )

        _ = await viewModel.completeOnboarding(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email,
            password: password,
            authenticatedUser: authenticatedUser,
            ageGroup: ageChoice?.ageGroup ?? .lateTeen,
            goals: selectedGoalList,
            struggle: resolvedStruggle,
            streakGoal: 3,
            notificationHour: components.hour ?? preferredTimeWindow.defaultHour,
            notificationMinute: components.minute ?? 0,
            onboarding: onboarding
        )
    }

    private func providerTitle(_ provider: OnboardingAuthProvider) -> String {
        if authenticatedProvider == provider {
            return provider == .apple ? "Apple connected" : "Google connected"
        }
        let prefix = accountMode == .login ? "Sign in with" : "Continue with"
        return provider == .apple ? "\(prefix) Apple" : "\(prefix) Google"
    }
}

private enum OnboardingStep: Int, CaseIterable, Hashable {
    case opening
    case goals
    case obstacle
    case spiritualStartingPoint
    case age
    case commitment
    case schedule
    case building
    case pathReveal
    case missionIntro
    case missionTimer
    case reason
    case milestone
    case notification
    case account

    var next: OnboardingStep {
        Self(rawValue: min(rawValue + 1, Self.allCases.count - 1)) ?? .account
    }

    var previous: OnboardingStep {
        Self(rawValue: max(rawValue - 1, 0)) ?? .opening
    }

    var pathProgress: Double {
        switch self {
        case .opening: 0
        case .building: 0.46
        case .pathReveal: 0.54
        case .missionIntro, .missionTimer: 0.68
        case .reason: 0.76
        case .milestone: 0.84
        case .notification: 0.92
        case .account: 1
        default: Double(rawValue) / Double(Self.allCases.count - 1)
        }
    }

    var showsProgressHeader: Bool {
        self != .opening && self != .building
    }
}

private enum OnboardingMissionAttemptState: Hashable {
    case idle
    case running
    case interrupted
    case failed
    case completed
}

private struct OnboardingStepTaskID: Hashable {
    let step: OnboardingStep
    let missionAttemptID: Int
}

private struct OnboardingGoal: Identifiable {
    let id: String
    let title: String
    let systemImage: String

    static let options = [
        OnboardingGoal(id: "god", title: "Grow closer to God", systemImage: "cross"),
        OnboardingGoal(id: "discipline", title: "Become more disciplined", systemImage: "checkmark.seal"),
        OnboardingGoal(id: "prayer", title: "Build a consistent prayer life", systemImage: "hands.sparkles"),
        OnboardingGoal(id: "scripture", title: "Read Scripture consistently", systemImage: "book.closed"),
        OnboardingGoal(id: "temptation", title: "Break a habit or temptation", systemImage: "shield.lefthalf.filled"),
        OnboardingGoal(id: "peace", title: "Find peace and direction", systemImage: "sun.max")
    ]
}

private struct OnboardingObstacle: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let struggle: Struggle

    static let options = [
        OnboardingObstacle(id: "procrastination", title: "Procrastination", systemImage: "timer", struggle: .discipline),
        OnboardingObstacle(id: "temptation", title: "Lust and temptation", systemImage: "heart.slash", struggle: .purity),
        OnboardingObstacle(id: "social-media", title: "Social media", systemImage: "iphone.slash", struggle: .focus),
        OnboardingObstacle(id: "motivation", title: "Lack of motivation", systemImage: "battery.25", struggle: .consistency),
        OnboardingObstacle(id: "doubt", title: "Doubt", systemImage: "questionmark.circle", struggle: .scripture),
        OnboardingObstacle(id: "stress", title: "Stress or anxiety", systemImage: "waveform.path", struggle: .prayer),
        OnboardingObstacle(id: "inconsistency", title: "Inconsistency", systemImage: "repeat", struggle: .consistency),
        OnboardingObstacle(id: "unsure", title: "I don’t know where to start", systemImage: "signpost.right", struggle: .discipline)
    ]
}

private struct AgeChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let ageGroup: AgeGroup

    static let options = [
        AgeChoice(id: "13-15", title: "13 - 15", detail: "Clear, grounded first steps", systemImage: "person", ageGroup: .earlyTeen),
        AgeChoice(id: "16-18", title: "16 - 18", detail: "Identity, choices, and responsibility", systemImage: "person.fill", ageGroup: .lateTeen),
        AgeChoice(id: "19-24", title: "19 - 24", detail: "Independence and ownership", systemImage: "graduationcap", ageGroup: .college),
        AgeChoice(id: "25+", title: "25+", detail: "Stewardship, vocation, and leadership", systemImage: "briefcase", ageGroup: .youngAdult)
    ]
}

private struct DailyCommitment: Identifiable {
    let minutes: Int
    let title: String
    let detail: String
    let recommended: Bool

    var id: Int { minutes }

    static let options = [
        DailyCommitment(minutes: 5, title: "5 min", detail: "Start small", recommended: false),
        DailyCommitment(minutes: 10, title: "10 min", detail: "Build consistency", recommended: true),
        DailyCommitment(minutes: 15, title: "15 min", detail: "Go deeper", recommended: false),
        DailyCommitment(minutes: 20, title: "20+ min", detail: "Challenge me", recommended: false)
    ]
}

private struct OnboardingScripture {
    let reference: String
    let text: String
}

private struct OnboardingAction {
    let title: String
    let systemImage: String
    var isDisabled = false
    let action: () -> Void
}

private struct OnboardingBottomAction: View {
    let action: OnboardingAction

    var body: some View {
        PrimaryActionButton(
            title: action.title,
            systemImage: action.systemImage,
            isDisabled: action.isDisabled,
            action: action.action
        )
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }
}

private struct OnboardingProgressHeader: View {
    let progress: Double
    let canGoBack: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(ClimbTypography.sans(16, weight: .semibold))
                    .foregroundStyle(canGoBack ? Color.climbMist : Color.climbMuted.opacity(0.4))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!canGoBack)
            .accessibilityLabel("Back")

            ProgressBar(value: progress, height: 4, tint: .climbSage)

            Image(systemName: "flag.fill")
                .font(ClimbTypography.sans(12, weight: .semibold))
                .foregroundStyle(Color.climbSage.opacity(progress >= 1 ? 1 : 0.55))
                .frame(width: 24)
                .accessibilityHidden(true)
        }
    }
}

private struct OnboardingHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(ClimbTypography.sans(30, weight: .semibold))
                .foregroundStyle(Color.climbMist)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(ClimbTypography.sans(15, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(ClimbTypography.sans(12, weight: .semibold))
            .foregroundStyle(Color.climbSage)
    }
}

private struct OnboardingChoiceRow: View {
    let title: String
    var detail: String? = nil
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.selection()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.climbSage : Color.climbMuted)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: detail == nil ? 0 : 3) {
                    Text(title)
                        .font(ClimbTypography.sans(16, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(ClimbTypography.sans(12, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(ClimbTypography.sans(18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.climbSage : Color.climbDivider)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, detail == nil ? 15 : 13)
            .background(
                isSelected ? Color.climbSage.opacity(0.075) : Color.climbSurfaceRaised.opacity(0.58),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.climbSage.opacity(0.32) : Color.climbHairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SpiritualMountainSelector: View {
    @Binding var selection: SpiritualStartingPoint?

    var body: some View {
        ZStack(alignment: .leading) {
            ClimbPathShape()
                .stroke(Color.climbDivider, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 56)
                .padding(.leading, 4)
                .padding(.vertical, 26)

            VStack(spacing: 12) {
                ForEach(SpiritualStartingPoint.allCases.reversed()) { point in
                    Button {
                        HapticFeedback.selection()
                        selection = point
                    } label: {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(selection == point ? Color.climbSage : Color.climbSurfaceRaised)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.climbSage.opacity(selection == point ? 0.5 : 0.16), lineWidth: 2))
                                .shadow(color: selection == point ? Color.climbSage.opacity(0.26) : .clear, radius: 8)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(point.title)
                                    .font(ClimbTypography.sans(16, weight: .semibold))
                                    .foregroundStyle(Color.climbMist)
                                Text(point.detail)
                                    .font(ClimbTypography.sans(13, weight: .medium))
                                    .foregroundStyle(Color.climbTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            selection == point ? Color.climbSage.opacity(0.07) : Color.climbSurfaceRaised.opacity(0.50),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selection == point ? Color.climbSage.opacity(0.28) : Color.climbHairline, lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityAddTraits(selection == point ? .isSelected : [])
                }
            }
        }
    }
}

private struct CommitmentChoice: View {
    let option: DailyCommitment
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.selection()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(option.title)
                        .font(ClimbTypography.sans(25, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.climbSage)
                    }
                }

                Text(option.detail)
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)

                if option.recommended {
                    Text("RECOMMENDED")
                        .font(ClimbTypography.sans(9, weight: .semibold))
                        .foregroundStyle(Color.climbSage)
                        .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(16)
            .background(
                isSelected ? Color.climbSage.opacity(0.075) : Color.climbSurfaceRaised.opacity(0.58),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.climbSage.opacity(0.34) : Color.climbHairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FirstWeekPathView: View {
    let checkpoints: [FirstWeekCheckpoint]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(checkpoints.enumerated()), id: \.element.id) { index, checkpoint in
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == 0 ? Color.climbSage : Color.climbSurfaceRaised)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.climbSage.opacity(index == 0 ? 0.5 : 0.18), lineWidth: 2))
                        if index < checkpoints.count - 1 {
                            Rectangle()
                                .fill(Color.climbDivider)
                                .frame(width: 2, height: 42)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("DAY \(checkpoint.day)")
                            .font(ClimbTypography.sans(10, weight: .semibold))
                            .foregroundStyle(index == 0 ? Color.climbSage : Color.climbMuted)
                        Text(checkpoint.title)
                            .font(ClimbTypography.sans(17, weight: .semibold))
                            .foregroundStyle(Color.climbMist)
                    }
                    .padding(.top, -3)

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ScriptureMoment: View {
    let scripture: OnboardingScripture

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scripture.text)
                .font(ClimbTypography.serif(23))
                .foregroundStyle(Color.climbMist)
                .lineSpacing(5)
            Text(scripture.reference)
                .font(ClimbTypography.sans(12, weight: .semibold))
                .foregroundStyle(Color.climbGold)
            ScriptureAttributionText(reference: scripture.reference)
        }
    }
}

private struct ThreeDayMilestoneView: View {
    let firstDayComplete: Bool

    var body: some View {
        HStack(spacing: 22) {
            ForEach(1...3, id: \.self) { day in
                VStack(spacing: 8) {
                    Circle()
                        .fill(day == 1 && firstDayComplete ? Color.climbSage : Color.climbSurfaceRaised)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle()
                                .stroke(day == 1 ? Color.climbSage.opacity(0.38) : Color.climbDivider, lineWidth: 1.5)
                        )
                        .overlay {
                            if day == 1 && firstDayComplete {
                                Image(systemName: "checkmark")
                                    .font(ClimbTypography.sans(16, weight: .semibold))
                                    .foregroundStyle(Color.climbInk)
                            } else {
                                Text("\(day)")
                                    .font(ClimbTypography.sans(14, weight: .semibold))
                                    .foregroundStyle(Color.climbMuted)
                            }
                        }
                    Text("DAY \(day)")
                        .font(ClimbTypography.sans(9, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    day == 1 && firstDayComplete ? "Day 1, complete" : "Day \(day), upcoming"
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AccountProgressStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(ClimbTypography.sans(25, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AccountValidationNotice: View {
    let message: String
    let isReady: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "info.circle")
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(isReady ? Color.climbSage : Color.climbGold)
            Text(message)
                .font(ClimbTypography.sans(12, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .animation(ClimbMotion.quick, value: message)
    }
}

private struct BuildingPathMark: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            ClimbPathShape()
                .stroke(Color.climbDivider, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            ClimbPathShape()
                .trim(from: 0, to: progress)
                .stroke(Color.climbSage, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .shadow(color: Color.climbSage.opacity(0.26), radius: 12)

            Image(systemName: "flag.fill")
                .font(ClimbTypography.sans(18, weight: .semibold))
                .foregroundStyle(Color.climbSage)
                .offset(x: 55, y: -88)
        }
    }
}

private struct OnboardingPathBackdrop: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ClimbPathShape()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.climbSage.opacity(0.055),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: proxy.size.width * 0.40, height: proxy.size.height * 0.76)
                .position(x: proxy.size.width * 0.86, y: proxy.size.height * 0.52)
                .blur(radius: 0.4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ClimbPathShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.60, y: rect.minY + rect.height * 0.55),
            control1: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.78),
            control2: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.76)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.35),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.24)
        )
        return path
    }
}
