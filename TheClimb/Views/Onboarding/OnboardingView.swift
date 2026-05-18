import SwiftUI

private enum OnboardingAuthProvider {
    case apple
    case google
}

struct OnboardingView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var step: OnboardingStep = .welcome
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var ageChoice: AgeChoice = .teen16
    @State private var selectedGoals: Set<String> = ["Build discipline", "Grow closer to God"]
    @State private var struggle: Struggle = .focus
    @State private var streakGoal = 30
    @State private var reminderTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var isSubmitting = false
    @State private var preparationProgress = 0.08
    @State private var authenticatedUser: FirebaseSignedInUser?
    @State private var authenticatedProvider: OnboardingAuthProvider?
    @State private var legalDocument: LegalDocument?

    private let goals = OnboardingGoal.defaultGoals
    private let streakOptions = [7, 14, 30, 60, 90]

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                if step != .welcome {
                    OnboardingProgressHeader(
                        step: step,
                        progress: step.progress,
                        canGoBack: canGoBack,
                        onBack: goBack
                    )
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        content
                            .id(step)
                            .transition(.climbScreen)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, step == .welcome ? 28 : 18)
                    .padding(.bottom, step == .preparing ? 32 : 120)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if step != .preparing {
                ctaButton
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea()
                    )
            }
        }
        .preferredColorScheme(.dark)
        .animation(ClimbMotion.standard, value: step)
        .sheet(item: $legalDocument) { document in
            NavigationStack {
                LegalDocumentView(document: document)
            }
        }
    }

    private var background: some View {
        ClimbScreenBackground()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .account:
            accountStep
        case .age:
            ageStep
        case .goals:
            goalsStep
        case .struggle:
            struggleStep
        case .streak:
            streakStep
        case .reminder:
            reminderStep
        case .review:
            reviewStep
        case .preparing:
            preparingStep
        case .ready:
            readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            MountainHeroCard(
                title: "The Climb",
                subtitle: "Discipline is built daily. Growth is earned."
            )
                .frame(height: 360)

            ClimbCard(padding: 20, cornerRadius: 28) {
                FeatureLine(systemImage: "target", title: "Personalized daily missions")
                FeatureLine(systemImage: "book.closed", title: "Faith-based devotionals")
                FeatureLine(systemImage: "chart.line.uptrend.xyaxis", title: "Progress you can track")
                FeatureLine(systemImage: "shield.checkered", title: "Accountability that stays focused")
            }

            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundStyle(Color.climbTextSecondary)
                Text("Log in")
                    .foregroundStyle(Color.climbGreen)
            }
            .font(ClimbTypography.sans(13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeading(title: "Create Account", subtitle: "Let’s get you started.")
            ClimbCard(padding: 20, cornerRadius: 28) {
                TextField("Name", text: $displayName)
                    .textContentType(.name)
                    .formFieldStyle()
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .formFieldStyle()
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .formFieldStyle()

                if authenticatedUser == nil {
                    AccountValidationNotice(message: accountValidationMessage)
                }
            }

            DividerLabel("OR")

            VStack(spacing: 12) {
                SecondaryActionButton(
                    title: authButtonTitle(for: .apple),
                    systemImage: authButtonIcon(for: .apple)
                ) {
                    signInWithApple()
                }
                .disabled(isProviderDisabled(.apple))
                .opacity(isProviderDisabled(.apple) ? 0.48 : 1)

                SecondaryActionButton(
                    title: authButtonTitle(for: .google),
                    systemImage: authButtonIcon(for: .google)
                ) {
                    signInWithGoogle()
                }
                .disabled(isProviderDisabled(.google))
                .opacity(isProviderDisabled(.google) ? 0.48 : 1)
            }

            VStack(spacing: 6) {
                Text("By continuing, you agree to our")
                    .foregroundStyle(Color.climbMuted)
                HStack(spacing: 12) {
                    Button("Terms of Service") {
                        legalDocument = .termsOfService
                    }
                    Button("Privacy Policy") {
                        legalDocument = .privacyPolicy
                    }
                }
                .foregroundStyle(Color.climbGreen)
            }
                .font(ClimbTypography.sans(12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    private var ageStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "What’s your age group?", subtitle: "The Climb is available for users 13 and older.")
            VStack(spacing: 12) {
                ForEach(AgeChoice.allCases) { choice in
                    SelectableRow(
                        title: choice.title,
                        subtitle: choice.subtitle,
                        systemImage: choice.systemImage,
                        isSelected: ageChoice == choice
                    ) {
                        ageChoice = choice
                    }
                }
            }
        }
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "What are your goals?", subtitle: "Select every goal that applies.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(goals) { goal in
                    GoalOptionCard(
                        goal: goal,
                        isSelected: selectedGoals.contains(goal.title)
                    ) {
                        if selectedGoals.contains(goal.title) {
                            selectedGoals.remove(goal.title)
                        } else {
                            selectedGoals.insert(goal.title)
                        }
                    }
                }
            }
        }
    }

    private var struggleStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "What is your biggest struggle right now?", subtitle: "Be honest. This helps us guide you.")
            VStack(spacing: 10) {
                ForEach(Struggle.allCases) { option in
                    SelectableRow(
                        title: option.rawValue,
                        subtitle: struggleSubtitle(for: option),
                        systemImage: struggleIcon(for: option),
                        isSelected: struggle == option
                    ) {
                        struggle = option
                    }
                }
            }
        }
    }

    private var streakStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "What’s your streak goal?", subtitle: "Choose a goal that challenges you.")

            ClimbCard(padding: 20, cornerRadius: 28) {
                Text("What’s a streak goal?")
                    .font(ClimbTypography.sans(16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("It’s the number of days you want to stay consistent.")
                    .font(ClimbTypography.sans(14))
                    .foregroundStyle(Color.climbTextSecondary)
            }

            VStack(spacing: 10) {
                ForEach(streakOptions, id: \.self) { option in
                    SelectableRow(
                        title: "\(option) days",
                        subtitle: streakSubtitle(for: option),
                        systemImage: "flame",
                        isSelected: streakGoal == option
                    ) {
                        streakGoal = option
                    }
                }
            }
        }
    }

    private var reminderStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "When should we remind you?", subtitle: "We’ll send your daily mission at this time.")

            ClimbCard(padding: 20, cornerRadius: 28) {
                DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .clipped()
            }

            ClimbCard(padding: 20, cornerRadius: 28) {
                Text("You’ll get:")
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
                FeatureLine(systemImage: "checkmark", title: "Daily mission reminder")
                FeatureLine(systemImage: "checkmark", title: "Streak alerts and encouragement")
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeading(title: "Almost there!", subtitle: "Here’s what you’ve set up.")
            ClimbCard(padding: 20, cornerRadius: 28) {
                SetupSummaryRow(systemImage: "person.2", title: "Age Group", value: ageChoice.title)
                SetupSummaryRow(systemImage: "heart", title: "Goals", value: "\(selectedGoals.count) selected")
                SetupSummaryRow(systemImage: "shield", title: "Main Struggle", value: struggle.rawValue)
                SetupSummaryRow(systemImage: "flame", title: "Streak Goal", value: "\(streakGoal) days")
                SetupSummaryRow(systemImage: "alarm", title: "Reminder Time", value: reminderText)
            }
        }
    }

    private var preparingStep: some View {
        VStack(spacing: 28) {
            StepHeading(
                title: "Your path is being prepared.",
                subtitle: "We’re creating your personalized plan, missions, and devotionals."
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle()
                    .stroke(Color.climbDivider, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: preparationProgress)
                    .stroke(Color.climbGreen, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.climbGreen.opacity(0.28), radius: 18, x: 0, y: 0)
                MountainBadge()
                    .frame(width: 130, height: 130)
            }
            .frame(width: 240, height: 240)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .task {
                await runPreparation()
            }

            VStack(alignment: .leading, spacing: 14) {
                FeatureLine(systemImage: "checkmark.circle.fill", title: "Creating your growth path")
                FeatureLine(systemImage: "checkmark.circle.fill", title: "Generating Day 1 mission")
                FeatureLine(systemImage: "checkmark.circle.fill", title: "Preparing your devotional")
                FeatureLine(systemImage: "checkmark.circle.fill", title: "Setting up your profile")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 18)
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .center, spacing: 10) {
                Text("Let’s climb.")
                    .font(ClimbTypography.sans(28, weight: .bold))
                    .foregroundStyle(.white)
                Text("Your transformation starts today.")
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                MountainHeroCard(compact: true)
                    .frame(height: 260)
            }
            .frame(maxWidth: .infinity)

            ClimbCard(padding: 20, cornerRadius: 28) {
                Text("Day 1 is ready.")
                    .font(ClimbTypography.sans(18, weight: .semibold))
                    .foregroundStyle(.white)
                SetupSummaryRow(systemImage: "target", title: "Your mission", value: "Deep work and focus")
                SetupSummaryRow(systemImage: "book.closed", title: "Your devotional", value: "Prepared")
                SetupSummaryRow(systemImage: "square.and.pencil", title: "Your reflection", value: "Ready after mission")
            }
        }
    }

    private var ctaButton: some View {
        PrimaryActionButton(
            title: ctaTitle,
            systemImage: ctaIcon,
            isDisabled: ctaDisabled
        ) {
            advance()
        }
    }

    private var ctaTitle: String {
        if isSubmitting { return "Creating Home" }
        switch step {
        case .welcome:
            return "Get Started"
        case .review:
            return "Build My Path"
        case .ready:
            return "Go to Home"
        default:
            return "Continue"
        }
    }

    private var ctaIcon: String {
        switch step {
        case .ready:
            "house.fill"
        case .review:
            "sparkles"
        default:
            "arrow.right"
        }
    }

    private var ctaDisabled: Bool {
        switch step {
        case .account:
            return !isAccountReady
        case .goals:
            return selectedGoals.isEmpty
        case .ready:
            return isSubmitting
        default:
            return false
        }
    }

    private var canGoBack: Bool {
        step != .welcome && step != .preparing && !isSubmitting
    }

    private var reminderText: String {
        reminderTime.formatted(date: .omitted, time: .shortened)
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

    private var isAccountReady: Bool {
        authenticatedUser != nil || (isEmailValid && password.count >= 6)
    }

    private var accountValidationMessage: String {
        if normalizedEmail.isEmpty && password.isEmpty {
            return "Enter a valid email and a password with at least 6 characters."
        }
        if !isEmailValid {
            return "Enter a valid email address before continuing."
        }
        if password.count < 6 {
            return "Password must be at least 6 characters."
        }
        return "Account details are ready."
    }

    private func advance() {
        switch step {
        case .review:
            beginPreparing()
        case .ready:
            submit()
        default:
            step = step.next
        }
    }

    private func goBack() {
        guard canGoBack else { return }
        step = step.previous
    }

    private func beginPreparing() {
        preparationProgress = 0.08
        step = .preparing
    }

    private func runPreparation() async {
        guard step == .preparing else { return }
        withAnimation(.easeInOut(duration: 1.2)) {
            preparationProgress = 1
        }
        try? await Task.sleep(nanoseconds: 1_350_000_000)
        guard step == .preparing else { return }
        step = .ready
    }

    private func submit() {
        isSubmitting = true
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let name = displayName.isEmpty ? fallbackDisplayName : displayName
        Task {
            await viewModel.completeOnboarding(
                displayName: name,
                email: email,
                password: password,
                authenticatedUser: authenticatedUser,
                ageGroup: ageChoice.ageGroup,
                goals: Array(selectedGoals).sorted(),
                struggle: struggle,
                streakGoal: streakGoal,
                notificationHour: components.hour ?? 8,
                notificationMinute: components.minute ?? 0
            )
            isSubmitting = false
        }
    }

    private func signInWithGoogle() {
        guard !isSubmitting else { return }
        isSubmitting = true

        Task { @MainActor in
            defer { isSubmitting = false }
            if let user = await viewModel.signInWithGoogleForOnboarding() {
                applyAuthenticatedUser(user, provider: .google)
            }
        }
    }

    private func signInWithApple() {
        guard !isSubmitting else { return }
        isSubmitting = true

        Task { @MainActor in
            defer { isSubmitting = false }
            if let user = await viewModel.signInWithAppleForOnboarding() {
                applyAuthenticatedUser(user, provider: .apple)
            }
        }
    }

    private func applyAuthenticatedUser(_ user: FirebaseSignedInUser, provider: OnboardingAuthProvider) {
        authenticatedUser = user
        authenticatedProvider = provider
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayName = user.displayName
        }
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            email = user.email
        }
        step = step.next
    }

    private func authButtonTitle(for provider: OnboardingAuthProvider) -> String {
        if authenticatedProvider == provider {
            return provider == .apple ? "Apple Connected" : "Google Connected"
        }

        if let authenticatedProvider {
            return authenticatedProvider == .apple ? "Connected with Apple" : "Connected with Google"
        }

        return provider == .apple ? "Continue with Apple" : "Continue with Google"
    }

    private func authButtonIcon(for provider: OnboardingAuthProvider) -> String {
        authenticatedProvider == provider ? "checkmark.circle.fill" : (provider == .apple ? "apple.logo" : "g.circle")
    }

    private func isProviderDisabled(_ provider: OnboardingAuthProvider) -> Bool {
        isSubmitting || (authenticatedProvider != nil && authenticatedProvider != provider)
    }

    private var fallbackDisplayName: String {
        let prefix = email.split(separator: "@").first
        return prefix.map(String.init) ?? "Climber"
    }

    private func struggleSubtitle(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "Phone use, deep work, attention"
        case .discipline:
            "Doing what you said you would do"
        case .consistency:
            "Showing up when motivation drops"
        case .purity:
            "Self-control and clean choices"
        case .prayer:
            "Building a steady prayer life"
        case .scripture:
            "Getting rooted in the Word"
        case .socialPressure:
            "Standing firm around others"
        }
    }

    private func struggleIcon(for struggle: Struggle) -> String {
        switch struggle {
        case .focus:
            "iphone.slash"
        case .discipline:
            "checkmark.seal"
        case .consistency:
            "repeat"
        case .purity:
            "heart.shield"
        case .prayer:
            "hands.sparkles"
        case .scripture:
            "book.closed"
        case .socialPressure:
            "person.2"
        }
    }

    private func streakSubtitle(for option: Int) -> String {
        switch option {
        case 7:
            "A focused first week"
        case 14:
            "Two weeks of discipline"
        case 30:
            "A serious reset"
        case 60:
            "Build a durable rhythm"
        default:
            "Long-term transformation"
        }
    }
}

private enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case account
    case age
    case goals
    case struggle
    case streak
    case reminder
    case review
    case preparing
    case ready

    var progress: Double {
        switch self {
        case .welcome:
            return 0
        case .preparing:
            return 0.92
        case .ready:
            return 1
        default:
            return Double(rawValue) / Double(Self.allCases.count - 1)
        }
    }

    var next: OnboardingStep {
        Self(rawValue: min(rawValue + 1, Self.allCases.count - 1)) ?? .ready
    }

    var previous: OnboardingStep {
        Self(rawValue: max(rawValue - 1, 0)) ?? .welcome
    }
}

private struct AgeChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let ageGroup: AgeGroup

    static let teen13 = AgeChoice(id: "13-15", title: "13 - 15", subtitle: "Start with simple wins", systemImage: "person", ageGroup: .teen)
    static let teen16 = AgeChoice(id: "16-18", title: "16 - 18", subtitle: "Build discipline now", systemImage: "person.fill", ageGroup: .teen)
    static let young19 = AgeChoice(id: "19-24", title: "19 - 24", subtitle: "Own your daily system", systemImage: "graduationcap", ageGroup: .college)
    static let adult25 = AgeChoice(id: "25+", title: "25+", subtitle: "Sustain a mature rhythm", systemImage: "briefcase", ageGroup: .youngAdult)

    static let allCases: [AgeChoice] = [.teen13, .teen16, .young19, .adult25]
}

private struct OnboardingGoal: Identifiable {
    let id: String
    let title: String
    let systemImage: String

    static let defaultGoals = [
        OnboardingGoal(id: "discipline", title: "Build discipline", systemImage: "checkmark.seal"),
        OnboardingGoal(id: "faith", title: "Grow closer to God", systemImage: "cross"),
        OnboardingGoal(id: "procrastination", title: "Stop procrastinating", systemImage: "timer"),
        OnboardingGoal(id: "phone", title: "Control phone use", systemImage: "iphone.slash"),
        OnboardingGoal(id: "focus", title: "Improve focus", systemImage: "scope"),
        OnboardingGoal(id: "confidence", title: "Build confidence", systemImage: "figure.stand"),
        OnboardingGoal(id: "habits", title: "Break bad habits", systemImage: "arrow.triangle.2.circlepath"),
        OnboardingGoal(id: "consistency", title: "Become consistent", systemImage: "calendar.badge.checkmark"),
        OnboardingGoal(id: "prayer", title: "Improve prayer life", systemImage: "hands.sparkles"),
        OnboardingGoal(id: "self-control", title: "Strengthen self-control", systemImage: "shield")
    ]
}

private struct OnboardingProgressHeader: View {
    let step: OnboardingStep
    let progress: Double
    let canGoBack: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(ClimbTypography.sans(17, weight: .bold))
                    .foregroundStyle(canGoBack ? .white : Color.climbMuted.opacity(0.45))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!canGoBack)

            ProgressBar(value: progress, height: 5, tint: .climbGreen)

            Text("\(min(step.rawValue + 1, OnboardingStep.allCases.count))/\(OnboardingStep.allCases.count)")
                .font(ClimbTypography.sans(11, weight: .bold))
                .foregroundStyle(Color.climbMuted)
                .monospacedDigit()
        }
    }
}

private struct StepHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ClimbTypography.sans(30, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(ClimbTypography.sans(15, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AccountValidationNotice: View {
    let message: String

    private var isReady: Bool {
        message == "Account details are ready."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(ClimbTypography.sans(14, weight: .bold))
                .foregroundStyle(isReady ? Color.climbGreen : Color.climbGold)
                .padding(.top, 1)

            Text(message)
                .font(ClimbTypography.sans(12, weight: .semibold))
                .foregroundStyle(isReady ? Color.climbGreen : Color.climbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isReady ? Color.climbGreen : Color.climbGold).opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((isReady ? Color.climbGreen : Color.climbGold).opacity(0.20), lineWidth: 0.8)
        )
        .animation(ClimbMotion.quick, value: message)
    }
}

private struct SelectableRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(ClimbTypography.sans(16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.climbGreen : Color.climbMuted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(ClimbTypography.sans(16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(ClimbTypography.sans(18, weight: .bold))
                    .foregroundStyle(isSelected ? Color.climbGreen : Color.climbMuted)
            }
            .padding(16)
            .background(isSelected ? Color.climbGreen.opacity(0.13) : Color.climbSurfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? Color.climbGreen.opacity(0.72) : Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct GoalOptionCard: View {
    let goal: OnboardingGoal
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.climbGreen.opacity(0.18) : Color.climbSurfaceGlass)
                        .frame(width: 34, height: 34)
                    Image(systemName: isSelected ? "checkmark" : goal.systemImage)
                        .font(ClimbTypography.sans(14, weight: .bold))
                        .foregroundStyle(isSelected ? Color.climbGreen : Color.climbMuted)
                }

                Text(goal.title)
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 116)
            .padding(10)
            .background(isSelected ? Color.climbGreen.opacity(0.12) : Color.climbSurfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? Color.climbGreen.opacity(0.72) : Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct FeatureLine: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(13, weight: .bold))
                .foregroundStyle(Color.climbGreen)
                .frame(width: 20)
            Text(title)
                .font(ClimbTypography.sans(14, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
        }
    }
}

private struct SetupSummaryRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
                Text(value)
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct DividerLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(Color.climbDivider)
                .frame(height: 1)
            Text(title)
                .font(ClimbTypography.sans(12, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
            Rectangle()
                .fill(Color.climbDivider)
                .frame(height: 1)
        }
    }
}

private struct MountainHeroCard: View {
    var compact = false
    var title: String?
    var subtitle: String?

    private var cornerRadius: CGFloat {
        compact ? 24 : 28
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MountainScene(compact: compact)

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(compact ? 0.28 : 0.72)
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            if compact {
                MountainBadge()
                    .frame(width: 120, height: 120)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Spacer()
                    Image(systemName: "figure.hiking")
                        .font(ClimbTypography.sans(34, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(title ?? "Begin with one honest step.")
                        .font(title == nil ? ClimbTypography.serif(26) : ClimbTypography.sans(40, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let subtitle {
                        Text(subtitle)
                            .font(ClimbTypography.sans(15, weight: .semibold))
                            .foregroundStyle(Color.climbGreen)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                }
                .padding(24)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.climbDivider, lineWidth: 1)
        )
    }
}

private struct MountainScene: View {
    var compact = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color(hex: 0x202127),
                        Color.climbSurface,
                        Color(hex: 0x090A0D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RidgeLine(points: [
                    CGPoint(x: 0.00, y: 0.82),
                    CGPoint(x: 0.18, y: 0.58),
                    CGPoint(x: 0.34, y: 0.76),
                    CGPoint(x: 0.52, y: 0.50),
                    CGPoint(x: 0.73, y: 0.70),
                    CGPoint(x: 1.00, y: 0.45)
                ])
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x2D3038).opacity(0.78),
                            Color(hex: 0x111217)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: size.height * 0.04)

                MountainPeak(
                    leftBase: 0.10,
                    rightBase: 0.98,
                    peakX: 0.64,
                    peakY: compact ? 0.24 : 0.20,
                    leftShoulder: 0.46,
                    rightShoulder: 0.78
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x5E626B),
                            Color(hex: 0x23252C),
                            Color(hex: 0x0D0E12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 18)

                MountainFace(
                    peakX: 0.64,
                    peakY: compact ? 0.24 : 0.20,
                    baseX: 0.98,
                    midX: 0.72
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                SnowCap(
                    peakX: 0.64,
                    peakY: compact ? 0.24 : 0.20,
                    width: compact ? 0.14 : 0.17,
                    depth: compact ? 0.13 : 0.15
                )
                .fill(Color.white.opacity(0.72))

                MountainPeak(
                    leftBase: 0.02,
                    rightBase: 0.42,
                    peakX: 0.22,
                    peakY: 0.49,
                    leftShoulder: 0.13,
                    rightShoulder: 0.31
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x444751),
                            Color(hex: 0x16171D)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(0.9)

                SummitFlag()
                    .frame(width: compact ? 30 : 38, height: compact ? 32 : 40)
                    .position(x: size.width * 0.64 + 10, y: size.height * (compact ? 0.23 : 0.19))

                TrailPath()
                    .stroke(
                        Color.white.opacity(0.22),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 8])
                    )
                    .frame(width: size.width, height: size.height)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.46)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
    }
}

private struct MountainBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.climbSurfaceRaised)
                .overlay(Circle().stroke(Color.climbDivider, lineWidth: 1))
            Image(systemName: "mountain.2.fill")
                .font(ClimbTypography.sans(48, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
                .offset(y: 8)
            Image(systemName: "flag.fill")
                .font(ClimbTypography.sans(22, weight: .bold))
                .foregroundStyle(Color.climbGreen)
                .offset(x: 18, y: -28)
        }
    }
}

private struct RidgeLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: 0, y: rect.maxY))
        for point in points {
            path.addLine(to: CGPoint(x: rect.width * point.x, y: rect.height * point.y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MountainPeak: Shape {
    let leftBase: CGFloat
    let rightBase: CGFloat
    let peakX: CGFloat
    let peakY: CGFloat
    let leftShoulder: CGFloat
    let rightShoulder: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * leftBase, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * leftShoulder, y: rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.width * peakX, y: rect.height * peakY))
        path.addLine(to: CGPoint(x: rect.width * rightShoulder, y: rect.height * 0.62))
        path.addLine(to: CGPoint(x: rect.width * rightBase, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MountainFace: Shape {
    let peakX: CGFloat
    let peakY: CGFloat
    let baseX: CGFloat
    let midX: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * peakX, y: rect.height * peakY))
        path.addLine(to: CGPoint(x: rect.width * midX, y: rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.width * baseX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.70, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SnowCap: Shape {
    let peakX: CGFloat
    let peakY: CGFloat
    let width: CGFloat
    let depth: CGFloat

    func path(in rect: CGRect) -> Path {
        let peak = CGPoint(x: rect.width * peakX, y: rect.height * peakY)
        var path = Path()

        path.move(to: peak)
        path.addLine(to: CGPoint(x: rect.width * (peakX - width * 0.48), y: rect.height * (peakY + depth)))
        path.addLine(to: CGPoint(x: rect.width * (peakX - width * 0.14), y: rect.height * (peakY + depth * 0.72)))
        path.addLine(to: CGPoint(x: rect.width * peakX, y: rect.height * (peakY + depth * 1.12)))
        path.addLine(to: CGPoint(x: rect.width * (peakX + width * 0.17), y: rect.height * (peakY + depth * 0.68)))
        path.addLine(to: CGPoint(x: rect.width * (peakX + width * 0.52), y: rect.height * (peakY + depth * 1.02)))
        path.closeSubpath()
        return path
    }
}

private struct SummitFlag: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color.white.opacity(0.76))
                .frame(width: 2, height: 34)
                .offset(x: 6, y: 6)
            Path { path in
                path.move(to: CGPoint(x: 8, y: 6))
                path.addLine(to: CGPoint(x: 31, y: 10))
                path.addLine(to: CGPoint(x: 8, y: 18))
                path.closeSubpath()
            }
            .fill(Color.climbGreen)
            .shadow(color: Color.climbGreen.opacity(0.45), radius: 8, x: 0, y: 0)
        }
    }
}

private struct TrailPath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.30, y: rect.height * 0.94))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.51, y: rect.height * 0.71),
            control1: CGPoint(x: rect.width * 0.38, y: rect.height * 0.86),
            control2: CGPoint(x: rect.width * 0.43, y: rect.height * 0.75)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.42),
            control1: CGPoint(x: rect.width * 0.56, y: rect.height * 0.64),
            control2: CGPoint(x: rect.width * 0.59, y: rect.height * 0.52)
        )
        return path
    }
}
