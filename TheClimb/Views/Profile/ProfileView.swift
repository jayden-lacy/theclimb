import SwiftUI
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
    @State private var showResetAlert = false
    @State private var showSignOutAlert = false
    @State private var showDeleteAccountAlert = false
#if canImport(FamilyControls) && os(iOS)
    @State private var showActivityPicker = false
    @State private var activitySelection = FamilyActivitySelection()
#endif

    var body: some View {
        ScreenContainer(title: "Profile") {
            if let profile = viewModel.profile {
                profileHeader(profile)
                goalsCard(profile)
                settingsCard
                dataCard
                legalSupportCard
            }
        }
        .onAppear(perform: syncLocalState)
        .alert("Reset local data?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    await viewModel.resetLocalData()
                }
            }
        } message: {
            Text("This clears the locally stored profile, missions, journal, and progress on this device.")
        }
        .alert("Sign out?", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    await viewModel.signOut()
                }
            }
        } message: {
            Text("This signs you out on this device. You can sign back in anytime.")
        }
        .alert("Delete account?", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task {
                    await viewModel.deleteAccount()
                }
            }
        } message: {
            Text("This permanently deletes your account, progress, journal entries, missions, and synced data. This cannot be undone.")
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
        ClimbCard(padding: 24, cornerRadius: 32, isProminent: true) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.climbGreen.opacity(0.13))
                    .frame(width: 64, height: 64)
                    .overlay(Circle().stroke(Color.climbGreen.opacity(0.24), lineWidth: 1))
                    .overlay(
                        Text(String(profile.displayName.prefix(1)))
                            .font(ClimbTypography.sans(28, weight: .bold))
                            .foregroundStyle(Color.climbGreen)
                    )
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.displayName)
                        .font(ClimbTypography.sans(24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(profile.ageGroup.rawValue) - \(profile.mainStruggle.rawValue)")
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                }
            }
        }
    }

    private func goalsCard(_ profile: UserProfile) -> some View {
        ClimbCard(cornerRadius: 30) {
            SectionTitle(title: "Goals")
            ForEach(profile.goals, id: \.self) { goal in
                Label(goal, systemImage: "checkmark.circle")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }
        }
    }

    private var settingsCard: some View {
        ClimbCard(cornerRadius: 30) {
            SectionTitle(title: "Settings")
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

                Toggle("App blocking", isOn: $appBlockingEnabled)
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .tint(.climbGreen)
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)

                Divider().overlay(Color.climbDivider)

                screenTimePermissionRow

                Divider().overlay(Color.climbDivider)

                DatePicker("Notification", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
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

    private var screenTimePermissionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Screen Time access", systemImage: "shield.lefthalf.filled")
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                StatusBadge(text: screenTimeStatusText, color: screenTimeStatusColor)
            }

            Text("Allow The Climb to use Apple Screen Time APIs for mission focus mode.")
                .font(ClimbTypography.sans(13, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryActionButton(title: screenTimeButtonTitle, systemImage: "lock.shield") {
                Task {
                    await viewModel.requestScreenTimeAuthorization()
                }
            }

#if canImport(FamilyControls) && os(iOS)
            SecondaryActionButton(title: screenTimeSelectionButtonTitle, systemImage: "square.grid.2x2") {
                showActivityPicker = true
            }
#endif
        }
        .padding(.vertical, 10)
    }

    private var dataCard: some View {
        ClimbCard(cornerRadius: 30) {
            SectionTitle(title: "Account")
            Label("Sign out ends this session. Delete account permanently removes your profile and synced app records.", systemImage: "person.crop.circle.badge.checkmark")
                .font(ClimbTypography.sans(13))
                .foregroundStyle(Color.climbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SecondaryActionButton(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                showSignOutAlert = true
            }
            .disabled(viewModel.isLoading)

            SecondaryActionButton(title: "Delete Account", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                showDeleteAccountAlert = true
            }
            .disabled(viewModel.isLoading)

            Divider().overlay(Color.climbDivider)
                .padding(.vertical, 4)

            Label("Local reset only clears this device and widget cache.", systemImage: "externaldrive.connected.to.line.below")
                .font(ClimbTypography.sans(13))
                .foregroundStyle(Color.climbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SecondaryActionButton(title: "Reset Local Data", systemImage: "trash", role: .destructive) {
                showResetAlert = true
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var legalSupportCard: some View {
        ClimbCard(cornerRadius: 30) {
            SectionTitle(title: "Support & Legal")

            NavigationLink {
                LegalDocumentView(document: .privacyPolicy)
            } label: {
                ProfileDestinationRow(title: "Privacy Policy", systemImage: "hand.raised")
            }
            .buttonStyle(.plain)

            Divider().overlay(Color.climbDivider)

            NavigationLink {
                LegalDocumentView(document: .termsOfService)
            } label: {
                ProfileDestinationRow(title: "Terms of Service", systemImage: "doc.text")
            }
            .buttonStyle(.plain)

            Divider().overlay(Color.climbDivider)

            Button(action: contactSupport) {
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
        }
    }

    private var screenTimeStatusText: String {
        switch viewModel.focusState {
        case .active:
            "Active"
        case .authorized:
            "Allowed"
        case .permissionRequired:
            "Needs access"
        case .selectionRequired:
            "Choose apps"
        case .denied:
            "Denied"
        case .simulated:
            "Simulated"
        case .unavailable:
            "Unavailable"
        }
    }

    private var screenTimeStatusColor: Color {
        switch viewModel.focusState {
        case .active, .authorized:
            .climbGreen
        case .permissionRequired:
            .climbGold
        case .selectionRequired:
            .climbGold
        case .denied:
            .climbRed
        case .simulated, .unavailable:
            .climbMuted
        }
    }

    private var screenTimeButtonTitle: String {
        switch viewModel.focusState {
        case .active, .authorized:
            "Refresh Screen Time Access"
        case .denied:
            "Request Again"
        default:
            "Allow Screen Time Access"
        }
    }

    private func contactSupport() {
        guard let url = URL(string: "mailto:support@jointheclimb.app?subject=The%20Climb%20Support") else { return }
        openURL(url)
    }

#if canImport(FamilyControls) && os(iOS)
    private var screenTimeSelectionButtonTitle: String {
        let count = activitySelection.shieldableContentCount
        return count == 0 ? "Choose Apps to Block" : "\(count) Focus Targets Selected"
    }
#endif
}

private struct ProfileDestinationRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(15, weight: .bold))
                .foregroundStyle(Color.climbGreen)
                .frame(width: 34, height: 34)
                .background(Color.climbGreen.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
