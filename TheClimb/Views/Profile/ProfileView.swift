import SwiftUI
#if os(iOS)
import UIKit
#endif
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

struct ProfileView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: AppViewModel

    @State private var displayName = ""
    @State private var struggle: Struggle = .focus
    @State private var streakGoal = 7
    @State private var appBlockingEnabled = true
    @State private var reminderTime = Date()
    @State private var showSignOutAlert = false
    @State private var showRestartOnboardingAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showDeletePasswordSheet = false
    @State private var deletionPassword = ""
    @State private var showSupportSheet = false
    @State private var attentionFrequency: AttentionAssistFrequency = .off
    @State private var attentionQuietHoursEnabled = true
    @State private var attentionQuietStart = Date()
    @State private var attentionQuietEnd = Date()
    @State private var attentionAssistStatus = "Off"
    @State private var isSavingAttentionAssist = false
#if canImport(FamilyControls) && os(iOS)
    @State private var showActivityPicker = false
    @State private var activitySelection = FamilyActivitySelection()
    @State private var focusTemplates: [FocusTemplateSummary] = []
    @State private var adultWebFilterEnabled = FocusAdultContentFilterStore.isEnabled
#endif

    var body: some View {
        ScreenContainer(title: "Profile") {
            if let profile = viewModel.profile {
                profileHeader(profile)
                badgeCaseCard
                settingsCard
                attentionAssistCard
#if canImport(FamilyControls) && os(iOS)
                focusTemplatesCard
#endif
                legalSupportCard
                dataCard
            }
        }
        .onAppear(perform: syncLocalState)
        .alert("Sign out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    await viewModel.signOut()
                }
            }
        } message: {
            Text("This clears this device's saved session and returns you to the welcome screen. You can sign back in anytime.")
        }
        .alert("Restart onboarding?", isPresented: $showRestartOnboardingAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Restart Onboarding", role: .destructive) {
                Task {
                    await viewModel.restartOnboardingOnThisDevice()
                }
            }
        } message: {
            Text("This signs out and clears only this device's saved session so you can walk through onboarding again. Your Firebase account and synced data are not deleted.")
        }
        .alert("Delete account?", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                if viewModel.requiresPasswordForAccountDeletion {
                    deletionPassword = ""
                    showDeletePasswordSheet = true
                } else {
                    Task {
                        await viewModel.deleteAccount()
                    }
                }
            }
        } message: {
            Text("This permanently deletes your account, progress, journal entries, missions, and synced data. This cannot be undone.")
        }
        .sheet(isPresented: $showDeletePasswordSheet) {
            DeleteAccountPasswordSheet(
                password: $deletionPassword,
                isLoading: viewModel.isLoading,
                onDelete: { password in
                    Task {
                        await viewModel.deleteAccount(password: password)
                        if viewModel.profile == nil {
                            deletionPassword = ""
                            showDeletePasswordSheet = false
                        }
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSupportSheet) {
            SupportContactSheet(openEmail: contactSupport)
                .presentationDetents([.medium])
        }
#if canImport(FamilyControls) && os(iOS)
        .familyActivityPicker(
            headerText: "Pick the apps, categories, or websites The Climb should block during missions.",
            footerText: "These choices stay on this device.",
            isPresented: $showActivityPicker,
            selection: $activitySelection
        )
        .onChange(of: activitySelection) { _, newSelection in
            ScreenTimeActivitySelectionStore.saveSelection(newSelection)
            reloadFocusTemplates()
            viewModel.refreshClimbControlState()
        }
#endif
    }

    private func profileHeader(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ClimbPageHeader(
                eyebrow: "Profile",
                title: profile.displayName,
                subtitle: "\(profile.ageGroup.displayTitle) · \(profile.mainStruggle.rawValue)"
            ) {
                VStack(alignment: .center, spacing: 5) {
                    Text("\(profile.ovrScore)")
                        .font(ClimbTypography.sans(27, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.climbMist)
                    Text("OVR")
                        .font(ClimbTypography.sans(10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Color.climbMuted)
                }
                .frame(width: 72, height: 64)
                .background(Color.climbBackgroundLifted.opacity(0.48), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.climbHairline, lineWidth: 0.75)
                )
            }

            ClimbQuietPanel(padding: 16, cornerRadius: 20) {
                HStack(spacing: 12) {
                    ClimbInlineMetric(value: "\(profile.currentStreak)", label: "streak")
                    ClimbInlineMetric(value: "\(profile.longestStreak)", label: "best", tint: .climbGold)
                    ClimbInlineMetric(value: "\(profile.streakGoal)", label: "goal", tint: .climbWarm)
                }
                ProgressBar(value: Double(profile.ovrScore) / 100, height: 4, tint: .climbGreen)
            }
        }
    }

    private var settingsCard: some View {
        ClimbQuietPanel(cornerRadius: 22, isProminent: true) {
            SectionTitle(title: "Daily Controls", subtitle: "Keep the account simple and the plan personal.")
            TextField("Name", text: $displayName)
                .formFieldStyle()

            VStack(spacing: 0) {
                Picker("Main Struggle", selection: $struggle) {
                    ForEach(Struggle.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .padding(.vertical, 10)

                Divider().overlay(Color.climbDivider)

                Stepper("Streak goal: \(streakGoal) days", value: $streakGoal, in: 3...60)
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)

                Divider().overlay(Color.climbDivider)

                Toggle("App blocking", isOn: appBlockingToggleBinding)
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .tint(.climbSage)
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)

                Divider().overlay(Color.climbDivider)

                DatePicker("Notification", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)

                Divider().overlay(Color.climbDivider)

                notificationPermissionRow
            }

            PrimaryActionButton(title: "Save Settings", systemImage: "checkmark") {
                let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                Task {
                    await viewModel.updateProfile(
                        displayName: displayName,
                        struggle: struggle,
                        streakGoal: streakGoal,
                        appBlockingEnabled: appBlockingEnabled,
                        notificationHour: components.hour ?? 8,
                        notificationMinute: components.minute ?? 0
                    )
                }
            }
        }
    }

    private var badgeCaseCard: some View {
        let unlocked = Array(viewModel.unlockedAchievements.prefix(6))
        let next = viewModel.nextAchievements.first

        return ClimbQuietPanel(padding: 18, cornerRadius: 22, accent: .climbGold, isProminent: true) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(
                    title: "Badge Case",
                    subtitle: "\(viewModel.unlockedAchievements.count) earned · \(Int(viewModel.achievementCompletionRate * 100))% complete"
                )
                Spacer(minLength: 10)
                StatusBadge(
                    text: viewModel.unlockedAchievements.isEmpty ? "Start" : "Earned",
                    color: viewModel.unlockedAchievements.isEmpty ? .climbGold : .climbGreen
                )
            }

            if unlocked.isEmpty {
                if let next {
                    AchievementProgressRow(achievement: next)
                } else {
                    EmptyState(
                        title: "No badges yet",
                        detail: "Complete your first protected focus block to start your badge case.",
                        systemImage: "seal"
                    )
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(unlocked) { achievement in
                            AchievementBadgePill(achievement: achievement, isCompact: true)
                        }
                    }
                }

                if let next {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Next")
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Color.climbMuted)
                            .textCase(.uppercase)
                        AchievementProgressRow(achievement: next)
                    }
                }
            }
        }
    }

    private var notificationPermissionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Notification access", systemImage: "bell.badge")
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                StatusBadge(text: notificationStatusText, color: notificationStatusColor)
            }

            Text("Allow reminders for your daily mission, incomplete mission, streak alerts, and recovery prompts.")
                .font(ClimbTypography.sans(13, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryActionButton(title: notificationButtonTitle, systemImage: "bell") {
                if viewModel.notificationState == .denied {
                    openAppSettings()
                } else {
                    Task {
                        await viewModel.requestNotificationAuthorization()
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var attentionAssistCard: some View {
        ClimbQuietPanel(cornerRadius: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionTitle(
                    title: "Attention Assist",
                    subtitle: "A few evidence-based nudges, never another noisy feed."
                )
                Spacer(minLength: 0)
                StatusBadge(
                    text: attentionAssistStatus,
                    color: attentionFrequency == .off
                        ? .climbMuted
                        : .climbGreen
                )
            }

            Picker("Frequency", selection: $attentionFrequency) {
                Text("Off").tag(AttentionAssistFrequency.off)
                Text("Minimal").tag(AttentionAssistFrequency.minimal)
                Text("Balanced").tag(AttentionAssistFrequency.balanced)
                Text("Frequent").tag(AttentionAssistFrequency.frequent)
            }
            .pickerStyle(.segmented)

            if attentionFrequency != .off {
                Toggle(
                    "Quiet hours",
                    isOn: $attentionQuietHoursEnabled
                )
                .font(ClimbTypography.sans(15, weight: .medium))
                .tint(.climbSage)
                .foregroundStyle(Color.climbMist)

                if attentionQuietHoursEnabled {
                    HStack(spacing: 12) {
                        DatePicker(
                            "From",
                            selection: $attentionQuietStart,
                            displayedComponents: .hourAndMinute
                        )
                        DatePicker(
                            "Until",
                            selection: $attentionQuietEnd,
                            displayedComponents: .hourAndMinute
                        )
                    }
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                }

                Text("Uses upcoming rhythms and protection health. Screen-time comparisons appear only when Apple supplies measured usage.")
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecondaryActionButton(
                title: isSavingAttentionAssist
                    ? "Saving Attention Assist"
                    : "Save Attention Assist",
                systemImage: "bell.and.waves.left.and.right"
            ) {
                saveAttentionAssist()
            }
            .disabled(isSavingAttentionAssist)
        }
        .animation(ClimbMotion.standard, value: attentionFrequency)
        .animation(ClimbMotion.standard, value: attentionQuietHoursEnabled)
    }

#if canImport(FamilyControls) && os(iOS)
    private var focusTemplatesCard: some View {
        ClimbQuietPanel(cornerRadius: 22, isProminent: true) {
            SectionTitle(
                title: "Focus Shield",
                subtitle: "Adult websites are blocked during protected focus. Add app-blocking setups for the parts of your day that need stronger boundaries."
            )

            HStack(spacing: 12) {
                FocusTemplateMetric(
                    value: adultWebFilterEnabled ? "On" : "Off",
                    label: "18+ web"
                )
                FocusTemplateMetric(
                    value: "\(activitySelection.shieldableContentCount)",
                    label: "selected"
                )
                FocusTemplateMetric(
                    value: "\(focusTemplates.count)",
                    label: "saved"
                )
            }

            SecondaryActionButton(
                title: activitySelection.hasShieldableContent ? "Edit Blocked Apps" : "Add Apps to Block",
                systemImage: "square.grid.2x2"
            ) {
                showActivityPicker = true
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Save current selection")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)

                HStack(spacing: 10) {
                    ForEach(FocusTemplateDraft.defaults) { draft in
                        FocusTemplateSaveButton(
                            draft: draft,
                            isDisabled: !activitySelection.hasShieldableContent
                        ) {
                            saveTemplate(draft)
                        }
                    }
                }
            }

            if focusTemplates.isEmpty {
                Text("Choose apps once, then save the setup as a template. Templates stay private on this device.")
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Saved")
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.climbMuted)
                        .textCase(.uppercase)

                    ForEach(focusTemplates) { template in
                        ProfileFocusTemplateRow(
                            template: template,
                            onApply: {
                                applyTemplate(template)
                            },
                            onDelete: {
                                deleteTemplate(template)
                            }
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(ClimbMotion.standard, value: focusTemplates)
        .animation(ClimbMotion.standard, value: activitySelection.shieldableContentCount)
        .animation(ClimbMotion.standard, value: adultWebFilterEnabled)
    }
#endif

    private var dataCard: some View {
        ClimbQuietPanel(padding: 18, cornerRadius: 20) {
            SectionTitle(title: "Account", subtitle: "Session and data controls")
            SecondaryActionButton(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                showSignOutAlert = true
            }
            .disabled(viewModel.isLoading)

            SecondaryActionButton(title: "Restart Onboarding", systemImage: "arrow.counterclockwise") {
                showRestartOnboardingAlert = true
            }
            .disabled(viewModel.isLoading)

            Text("Testing path: clears this device and returns to the first onboarding screen without deleting your account.")
                .font(ClimbTypography.sans(12, weight: .medium))
                .foregroundStyle(Color.climbMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryActionButton(title: "Delete Account", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                showDeleteAccountAlert = true
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var legalSupportCard: some View {
        ClimbQuietPanel(cornerRadius: 22) {
            SectionTitle(title: "Support & Legal")

            Button {
                openURL(LegalDocument.privacyPolicy.onlineURL)
            } label: {
                ProfileDestinationRow(title: "Privacy Policy", systemImage: "hand.raised")
            }
            .buttonStyle(.plain)

            Divider().overlay(Color.climbDivider)

            Button {
                openURL(LegalDocument.termsOfService.onlineURL)
            } label: {
                ProfileDestinationRow(title: "Terms of Service", systemImage: "doc.text")
            }
            .buttonStyle(.plain)

            Divider().overlay(Color.climbDivider)

            Button {
                contactSupport()
            } label: {
                ProfileDestinationRow(title: "Contact Support", systemImage: "envelope")
            }
            .buttonStyle(.plain)
        }
    }

    private func syncLocalState() {
        guard let profile = viewModel.profile else { return }
        displayName = profile.displayName
        struggle = profile.mainStruggle
        streakGoal = profile.streakGoal
        appBlockingEnabled = profile.appBlockingEnabled
#if canImport(FamilyControls) && os(iOS)
        activitySelection = ScreenTimeActivitySelectionStore.loadSelection()
        adultWebFilterEnabled = FocusAdultContentFilterStore.isEnabled
        reloadFocusTemplates()
#endif
        reminderTime = Calendar.current.date(
            bySettingHour: profile.notificationHour,
            minute: profile.notificationMinute,
            second: 0,
            of: Date()
        ) ?? Date()

        Task {
            await viewModel.refreshScreenTimeAuthorization()
            await viewModel.refreshNotificationAuthorization()
            await loadAttentionAssist()
        }
    }

    private func loadAttentionAssist() async {
        do {
            let preferences = try await AttentionAssistRuntimeService()
                .preferences()
            await MainActor.run {
                attentionFrequency = preferences.frequency
                attentionAssistStatus = preferences.isEnabled
                    ? preferences.frequency.title
                    : "Off"
                if let quietHours = preferences.quietHours {
                    attentionQuietHoursEnabled = true
                    attentionQuietStart = date(
                        forMinuteOfDay: quietHours.startMinuteOfDay
                    )
                    attentionQuietEnd = date(
                        forMinuteOfDay: quietHours.endMinuteOfDay
                    )
                } else {
                    attentionQuietHoursEnabled = false
                    attentionQuietStart = date(forMinuteOfDay: 22 * 60)
                    attentionQuietEnd = date(forMinuteOfDay: 7 * 60)
                }
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func saveAttentionAssist() {
        guard !isSavingAttentionAssist else { return }
        isSavingAttentionAssist = true

        Task {
            do {
                let runtime = AttentionAssistRuntimeService()
                if attentionFrequency == .off {
                    try await runtime.disable()
                } else {
                    let permission = try await runtime
                        .requestNotificationPermission()
                    guard permission == .authorized else {
                        throw permission == .denied
                            ? AttentionAssistRuntimeError.notificationPermissionDenied
                            : AttentionAssistRuntimeError.notificationPermissionUnavailable
                    }

                    let quietHours = attentionQuietHoursEnabled
                        ? AttentionAssistQuietHours(
                            startMinuteOfDay: minuteOfDay(
                                for: attentionQuietStart
                            ),
                            endMinuteOfDay: minuteOfDay(
                                for: attentionQuietEnd
                            )
                        )
                        : nil
                    let preferences = AttentionAssistPreferences.recommended(
                        frequency: attentionFrequency,
                        quietHours: quietHours
                    )
                    try await runtime.savePreferences(preferences)
                    _ = try await runtime.reconcile(
                        signals: AttentionAssistSignalSource().currentSignals()
                    )
                }

                await MainActor.run {
                    attentionAssistStatus = attentionFrequency.title
                    isSavingAttentionAssist = false
                    HapticFeedback.success()
                }
            } catch {
                await MainActor.run {
                    isSavingAttentionAssist = false
                    viewModel.errorMessage = error.localizedDescription
                    HapticFeedback.impact(.medium)
                }
            }
        }
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: date
        )
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func date(forMinuteOfDay minuteOfDay: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private var appBlockingToggleBinding: Binding<Bool> {
        Binding(
            get: { appBlockingEnabled },
            set: { newValue in
                guard newValue != appBlockingEnabled else { return }
                appBlockingEnabled = newValue

                if newValue {
                    handleAppBlockingEnabled()
                }
            }
        )
    }

    private func handleAppBlockingEnabled() {
        HapticFeedback.selection()
        Task {
            await viewModel.requestScreenTimeAuthorization()
            await viewModel.refreshScreenTimeAuthorization()
#if canImport(FamilyControls) && os(iOS)
            await MainActor.run {
                showActivityPicker = true
            }
#endif
        }
    }

#if canImport(FamilyControls) && os(iOS)
    private func reloadFocusTemplates() {
        focusTemplates = ScreenTimeActivitySelectionStore.loadTemplateSummaries()
    }

    private func saveTemplate(_ draft: FocusTemplateDraft) {
        ScreenTimeActivitySelectionStore.saveCurrentSelectionAsTemplate(draft)
        reloadFocusTemplates()
        HapticFeedback.selection()
    }

    private func applyTemplate(_ template: FocusTemplateSummary) {
        guard let selection = ScreenTimeActivitySelectionStore.applyTemplate(id: template.id) else { return }
        activitySelection = selection
        reloadFocusTemplates()
        HapticFeedback.selection()
    }

    private func deleteTemplate(_ template: FocusTemplateSummary) {
        ScreenTimeActivitySelectionStore.deleteTemplate(id: template.id)
        reloadFocusTemplates()
        HapticFeedback.impact(.light)
    }
#endif

    private var notificationStatusText: String {
        switch viewModel.notificationState {
        case .notDetermined:
            "Not set"
        case .authorized:
            "Allowed"
        case .denied:
            "Off"
        case .unavailable:
            "Unavailable"
        }
    }

    private var notificationStatusColor: Color {
        switch viewModel.notificationState {
        case .authorized:
            .climbGreen
        case .notDetermined:
            .climbGold
        case .denied:
            .climbRed
        case .unavailable:
            .climbMuted
        }
    }

    private var notificationButtonTitle: String {
        switch viewModel.notificationState {
        case .authorized:
            "Refresh Notification Access"
        case .denied:
            "Open Notification Settings"
        case .notDetermined:
            "Allow Notifications"
        case .unavailable:
            "Check Notification Access"
        }
    }

    private func openAppSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func contactSupport() {
        SupportEmail.open { didOpen in
            guard !didOpen else { return }
            showSupportSheet = true
        }
    }

}

private enum SupportEmail {
    static let address = "support@theclimbapp.org"

    @MainActor
    static func open(completion: @escaping (Bool) -> Void) {
        guard let url = mailURL else {
            completion(false)
            return
        }

        #if os(iOS)
        UIApplication.shared.open(url, options: [:]) { didOpen in
            Task { @MainActor in
                completion(didOpen)
            }
        }
        #else
        completion(false)
        #endif
    }

    private static var mailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "The Climb Support"),
            URLQueryItem(name: "body", value: """
            Hi The Climb team,

            I need help with:

            """)
        ]
        return components.url
    }
}

private extension AttentionAssistFrequency {
    var title: String {
        switch self {
        case .off:
            "Off"
        case .minimal:
            "Minimal"
        case .balanced:
            "Balanced"
        case .frequent:
            "Frequent"
        case .custom:
            "Custom"
        }
    }
}

#if canImport(FamilyControls) && os(iOS)
private struct FocusTemplateMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ClimbTypography.sans(24, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
            Text(label)
                .font(ClimbTypography.sans(11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.climbBackgroundLifted.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 0.7)
        )
    }
}

private struct FocusTemplateSaveButton: View {
    let draft: FocusTemplateDraft
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: draft.systemImage)
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(isDisabled ? Color.climbMuted : Color.climbGreen)
                    .frame(width: 34, height: 34)
                    .background(
                        (isDisabled ? Color.climbDivider : Color.climbGreen).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                Text(draft.name)
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(isDisabled ? Color.climbMuted : Color.climbMist)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.climbSurface.opacity(0.70), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.white.opacity(isDisabled ? 0.035 : 0.065), lineWidth: 0.7)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.56 : 1)
    }
}

private struct ProfileFocusTemplateRow: View {
    let template: FocusTemplateSummary
    let onApply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.systemImage)
                .font(ClimbTypography.sans(16, weight: .semibold))
                .foregroundStyle(Color.climbGreen)
                .frame(width: 40, height: 40)
                .background(Color.climbGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text("\(template.shieldableContentCount) distractions · \(template.subtitle)")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 8)

            Button {
                onApply()
            } label: {
                Image(systemName: "checkmark")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbInk)
                    .frame(width: 32, height: 32)
                    .background(Color.climbGreen, in: Circle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Apply \(template.name)")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbRed)
                    .frame(width: 32, height: 32)
                    .background(Color.climbRed.opacity(0.10), in: Circle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Delete \(template.name)")
        }
        .padding(12)
        .background(Color.climbSurface.opacity(0.70), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 0.7)
        )
    }
}
#endif

private struct DeleteAccountPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var password: String
    let isLoading: Bool
    let onDelete: (String) -> Void

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            ClimbScreenBackground()
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 42, height: 4)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm deletion")
                        .font(ClimbTypography.sans(28, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Enter your password so Firebase can verify this is really you before deleting the account.")
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("Password", text: $password)
                    .formFieldStyle()
                    .textContentType(.password)

                PrimaryActionButton(
                    title: isLoading ? "Deleting" : "Delete Account",
                    systemImage: "trash.fill",
                    tint: .climbRed,
                    isDisabled: trimmedPassword.count < 6 || isLoading
                ) {
                    onDelete(trimmedPassword)
                }

                SecondaryActionButton(title: "Cancel", systemImage: "xmark") {
                    password = ""
                    dismiss()
                }
            }
            .padding(20)
        }
    }
}

private struct SupportContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    let openEmail: () -> Void

    var body: some View {
        ZStack {
            ClimbScreenBackground()
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 42, height: 4)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Contact Support")
                        .font(ClimbTypography.sans(28, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("For help, account deletion questions, privacy requests, or community safety concerns.")
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ClimbCard(cornerRadius: 24) {
                    Text(SupportEmail.address)
                        .font(ClimbTypography.sans(16, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    Text("If your email app does not open, copy this address and send us a message from your preferred inbox.")
                        .font(ClimbTypography.sans(13, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                }

                PrimaryActionButton(title: "Email Support", systemImage: "envelope.fill") {
                    openEmail()
                    dismiss()
                }

                SecondaryActionButton(title: "Copy Email", systemImage: "doc.on.doc") {
                    #if os(iOS)
                    UIPasteboard.general.string = SupportEmail.address
                    #endif
                    dismiss()
                }
            }
            .padding(20)
        }
    }
}

private struct ProfileDestinationRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(Color.climbSage)
                .frame(width: 34, height: 34)
                .background(Color.climbSage.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(ClimbTypography.sans(12, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
        }
        .padding(.vertical, 10)
    }
}
