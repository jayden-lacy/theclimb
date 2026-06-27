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
    @State private var showDeleteAccountAlert = false
    @State private var showDeletePasswordSheet = false
    @State private var deletionPassword = ""
    @State private var showSupportSheet = false
#if canImport(FamilyControls) && os(iOS)
    @State private var showActivityPicker = false
    @State private var activitySelection = FamilyActivitySelection()
#endif

    var body: some View {
        ScreenContainer(title: "Profile") {
            if let profile = viewModel.profile {
                profileHeader(profile)
                settingsCard
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
        }
#endif
    }

    private func profileHeader(_ profile: UserProfile) -> some View {
        ClimbCard(padding: 22, cornerRadius: 26, isProminent: true) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.climbGreen.opacity(0.11))
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(Color.climbGreen.opacity(0.18), lineWidth: 1))
                    .overlay(
                        Text(String(profile.displayName.prefix(1)))
                            .font(ClimbTypography.sans(25, weight: .bold))
                            .foregroundStyle(Color.climbAction)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.displayName)
                        .font(ClimbTypography.sans(22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text("\(profile.ageGroup.rawValue) · \(profile.mainStruggle.rawValue)")
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 0)

                StatusBadge(text: "OVR \(profile.ovrScore)", color: .climbSage)
            }

            ProgressBar(value: Double(profile.ovrScore) / 100, height: 5, tint: .climbGreen)
        }
    }

    private var settingsCard: some View {
        ClimbCard(cornerRadius: 24) {
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

    private var dataCard: some View {
        ClimbCard(padding: 18, cornerRadius: 22) {
            SectionTitle(title: "Account", subtitle: "Session and data controls")
            SecondaryActionButton(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                showSignOutAlert = true
            }
            .disabled(viewModel.isLoading)

            SecondaryActionButton(title: "Delete Account", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                showDeleteAccountAlert = true
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var legalSupportCard: some View {
        ClimbCard(cornerRadius: 24) {
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
        }
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
                        .font(ClimbTypography.sans(28, weight: .bold))
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
                        .font(ClimbTypography.sans(28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("For help, account deletion questions, privacy requests, or community safety concerns.")
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ClimbCard(cornerRadius: 24) {
                    Text(SupportEmail.address)
                        .font(ClimbTypography.sans(16, weight: .bold))
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
                .font(ClimbTypography.sans(15, weight: .bold))
                .foregroundStyle(Color.climbSage)
                .frame(width: 34, height: 34)
                .background(Color.climbSage.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(ClimbTypography.sans(15, weight: .bold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(ClimbTypography.sans(12, weight: .bold))
                .foregroundStyle(Color.climbMuted)
        }
        .padding(.vertical, 10)
    }
}
