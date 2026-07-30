import SwiftUI
#if os(iOS)
import UIKit
#endif
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

struct HomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isMissionPresented = false
    @State private var focusedDevotional: Devotional?
    @State private var isRegenerationDialogPresented = false
    @State private var showFocusControlCenter = false
#if canImport(FamilyControls) && os(iOS)
    @State private var activitySelection = FamilyActivitySelection()
    @State private var adultWebFilterEnabled = FocusAdultContentFilterStore.isEnabled
#endif

    var body: some View {
        ScreenContainer(title: "Focus", hidesNavigationBar: true, bottomSafeAreaSpacing: 142) {
            if let profile = viewModel.profile {
                homeHeader(profile)
                screenTimeCommandCenter(profile)
            }

            if let mission = viewModel.todayMission {
                missionCard(mission)
            } else if viewModel.isPreparingTodayPlan {
                planPreparingCard
            } else {
                EmptyState(
                    title: "No mission yet",
                    detail: "Your next daily mission will appear when your plan refreshes.",
                    systemImage: "flag"
                )
            }

            if let devotional = viewModel.todayDevotional {
                dailyWordSection(devotional)
            } else if viewModel.isPreparingTodayPlan {
                devotionalPreparingCard
            }

            quickActionRow
        }
        .sheet(isPresented: $isMissionPresented) {
            if let mission = viewModel.todayMission {
                MissionSessionView(viewModel: viewModel, mission: mission)
            }
        }
        .sheet(isPresented: $showFocusControlCenter) {
            FocusControlCenterView(viewModel: viewModel)
        }
#if canImport(FamilyControls) && os(iOS)
        .onAppear {
            activitySelection = ScreenTimeActivitySelectionStore.loadSelection()
            adultWebFilterEnabled = FocusAdultContentFilterStore.isEnabled
            Task {
                await viewModel.refreshScreenTimeAuthorization()
            }
        }
#else
        .task {
            await viewModel.refreshScreenTimeAuthorization()
        }
#endif
        .overlay {
            if let focusedDevotional {
                DevotionalFocusOverlay(
                    devotional: focusedDevotional,
                    selectedFeedback: viewModel.contentFeedback(for: focusedDevotional.id, kind: .devotional),
                    onFeedback: { rating in
                        viewModel.submitContentFeedback(
                            kind: .devotional,
                            contentID: focusedDevotional.id,
                            title: focusedDevotional.title,
                            rating: rating
                        )
                    }
                ) {
                    withAnimation(ClimbMotion.focus) {
                        self.focusedDevotional = nil
                    }
                }
                .zIndex(20)
            }
        }
        .toolbar(focusedDevotional == nil ? .visible : .hidden, for: .tabBar)
        .confirmationDialog(
            "Change today's plan?",
            isPresented: $isRegenerationDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Too easy") {
                regenerateTodayPlan(reason: "Too easy")
            }
            Button("Doesn't fit today") {
                regenerateTodayPlan(reason: "Doesn't fit today")
            }
            Button("Need a different focus") {
                regenerateTodayPlan(reason: "Need a different focus")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Climb will build a new mission and Daily Word before you start.")
        }
        .animation(ClimbMotion.focus, value: focusedDevotional?.id)
        .animation(ClimbMotion.standard, value: viewModel.isRegeneratingTodayPlan)
    }

    private func homeHeader(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        Circle()
                            .fill(Color.climbGreen.opacity(0.76))
                            .frame(width: 4, height: 4)
                        Text("Personal plan")
                    }
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.climbTextSecondary)
                    .textCase(.uppercase)

                    Text("Today’s climb")
                        .font(ClimbTypography.sans(34, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                        .tracking(-0.5)
                        .lineSpacing(-1)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(homeContextLine(for: profile))
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: 5) {
                    Text("\(profile.ovrScore)")
                        .font(ClimbTypography.sans(28, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.climbMist)
                        .contentTransition(.numericText())
                    Text("OVR")
                        .font(ClimbTypography.sans(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.climbMuted)
                }
                .frame(width: 72, height: 64)
                .background(Color.climbSurfaceRaised.opacity(0.58), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.climbHairline, lineWidth: 0.8)
                )
            }

            StreakOverview(
                streak: profile.currentStreak,
                goal: profile.streakGoal,
                delta: todayOVRDelta
            )
        }
        .padding(.top, 6)
        .climbEntrance()
    }

    private func screenTimeCommandCenter(_ profile: UserProfile) -> some View {
        FaithFocusCommandCenter(
            focusState: viewModel.focusState,
            blockedItemCount: selectedBlockingItemCount,
            adultWebFilterEnabled: adultWebFilterEnabled,
            streak: profile.currentStreak,
            protectedMinutes: viewModel.todayMission?.durationMinutes ?? profile.ageGroup.baseMissionMinutes,
            isMissionReady: viewModel.todayMission != nil,
            isPreparingPlan: viewModel.isPreparingTodayPlan,
            onStart: {
                guard viewModel.todayMission != nil else { return }
                isMissionPresented = true
            },
            onSetup: {
                showFocusControlCenter = true
            }
        )
    }

    private var selectedBlockingItemCount: Int {
#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            return activitySelection.shieldableContentCount
        }
#endif
        return 0
    }

    private func missionCard(_ mission: Mission) -> some View {
        HomeSurface(padding: 0, cornerRadius: 27, accent: statusColor(mission.status), prominence: .hero) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Focus block")
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .tracking(1.25)
                            .foregroundStyle(Color.climbTextSecondary)
                            .textCase(.uppercase)
                        Text(missionLabel(for: mission))
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .foregroundStyle(Color.climbMuted)
                        Spacer(minLength: 0)
                        HomeStatusBadge(text: mission.status.rawValue.capitalized, color: statusColor(mission.status))
                    }

                    Text(mission.title)
                        .font(ClimbTypography.sans(30, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                        .tracking(-0.35)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(missionSummaryPreview(mission.summary))
                        .font(ClimbTypography.sans(15, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(4)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    FocusProtectionStrip(mission: mission)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 15)

                VStack(spacing: 10) {
                    PrimaryActionButton(
                        title: viewModel.isRegeneratingTodayPlan ? "Building new plan" : missionButtonTitle(mission.status),
                        systemImage: viewModel.isRegeneratingTodayPlan ? "sparkles" : missionButtonIcon(mission.status),
                        tint: missionButtonColor(mission.status)
                    ) {
                        isMissionPresented = true
                    }
                    .disabled(viewModel.isRegeneratingTodayPlan)

                    if mission.status == .pending {
                        Button {
                            HapticFeedback.selection()
                            isRegenerationDialogPresented = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(ClimbTypography.sans(12, weight: .semibold))
                                Text(viewModel.isRegeneratingTodayPlan ? "Regenerating..." : "Adjust difficulty or focus")
                                    .font(ClimbTypography.sans(13, weight: .semibold))
                            }
                            .foregroundStyle(Color.climbTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(!viewModel.canRegenerateTodayPlan)
                        .opacity(viewModel.canRegenerateTodayPlan ? 1 : 0.48)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .background(Color.black.opacity(0.15))
            }
        }
        .activeShimmer(mission.status == .active, cornerRadius: 27)
    }

    private func regenerateTodayPlan(reason: String) {
        Task {
            await viewModel.regenerateTodayPlan(reason: reason)
        }
    }

    private var planPreparingCard: some View {
        HomeSurface(padding: 20, cornerRadius: 28, accent: .climbGreen, prominence: .primary) {
            HStack(spacing: 14) {
                SwiftUI.ProgressView()
                    .tint(.climbGreen)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Building today's mission")
                        .font(ClimbTypography.sans(21, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    Text("Your home is ready. The daily plan will fill in automatically.")
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                }
            }
        }
    }

    private func dailyWordSection(_ devotional: Devotional) -> some View {
        Button {
            HapticFeedback.selection()
            withAnimation(ClimbMotion.focus) {
                focusedDevotional = devotional
            }
        } label: {
            HomeSurface(padding: 0, cornerRadius: 24, accent: .climbWarm, prominence: .quiet) {
                HStack(alignment: .top, spacing: 16) {
                    Capsule()
                        .fill(Color.climbWarm.opacity(0.82))
                        .frame(width: 3)
                        .padding(.vertical, 3)

                    VStack(alignment: .leading, spacing: 15) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Daily Word")
                                .font(ClimbTypography.sans(12, weight: .semibold))
                                .tracking(1.05)
                                .foregroundStyle(Color.climbTextSecondary)
                                .textCase(.uppercase)
                            Spacer(minLength: 12)
                            Text(devotional.bibleVerse)
                                .font(ClimbTypography.sans(12, weight: .semibold))
                                .foregroundStyle(Color.climbMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }

                        Text(devotional.title)
                            .font(ClimbTypography.serif(29))
                            .foregroundStyle(Color.climbMist)
                            .fixedSize(horizontal: false, vertical: true)

                        if let verseText = devotional.verseText, !verseText.isEmpty {
                            Text("“\(verseText)”")
                                .font(ClimbTypography.serif(21))
                                .foregroundStyle(Color.climbWarm.opacity(0.94))
                                .lineLimit(4)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                            ScriptureAttributionText(reference: devotional.bibleVerse)
                        } else {
                            Text(devotional.explanation)
                                .font(ClimbTypography.sans(15))
                                .foregroundStyle(Color.climbTextSecondary)
                                .lineLimit(4)
                                .lineSpacing(4)
                        }

                        HStack(alignment: .center, spacing: 10) {
                            Text(devotional.reflectionQuestion)
                                .font(ClimbTypography.sans(14, weight: .medium))
                                .foregroundStyle(Color.climbTextSecondary)
                                .lineLimit(2)
                            Spacer(minLength: 12)
                            HStack(spacing: 6) {
                                Text("Read")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(ClimbTypography.sans(13, weight: .semibold))
                            .foregroundStyle(Color.climbGreen)
                        }
                    }
                }
                .padding(20)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityLabel("Read full devotional")
    }

    private var devotionalPreparingCard: some View {
        HomeSurface(padding: 20, cornerRadius: 28, accent: .climbWarm, prominence: .quiet) {
            VStack(alignment: .leading, spacing: 13) {
                Text("DAILY WORD")
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.climbMuted)
                Text("Preparing scripture for today.")
                    .font(ClimbTypography.serif(26))
                    .foregroundStyle(Color.climbMist)
                ProgressBar(value: 0.42, height: 5, tint: .climbGreen)
            }
        }
    }

    private var quickActionRow: some View {
        HStack(spacing: 10) {
            NavigationLink {
                JournalHistoryView(
                    entries: viewModel.journalEntries,
                    exportText: viewModel.exportJournalMarkdown()
                )
            } label: {
                QuickActionTile(title: "Journal", detail: "Reflect", systemImage: "book.pages")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { HapticFeedback.selection() })

            NavigationLink {
                ProgressDashboardView(viewModel: viewModel)
            } label: {
                QuickActionTile(title: "Progress", detail: "Review", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { HapticFeedback.selection() })
        }
    }

    private func homeContextLine(for profile: UserProfile) -> String {
        let path = GrowthPathPersonalization.resolve(for: profile)
        guard let mission = viewModel.todayMission else {
            return "\(path.primaryGoal) · preparing today’s block"
        }

        switch mission.status {
        case .active:
            return "Block active · stay with the window"
        case .completed:
            return "\(profile.currentStreak)-day streak · reflection locked in"
        case .recovered:
            return "Recovery counted · keep the next promise small"
        case .failed:
            return "Recovery is available · don’t let one miss become two"
        case .pending:
            if profile.currentStreak == 0 {
                return "\(path.primaryGoal) · start with one honest win"
            }
            return "\(profile.currentStreak)-day streak · protect the next small promise"
        }
    }

    private var todayOVRDelta: Int {
        let sorted = viewModel.progress.sorted { $0.date > $1.date }
        guard let latest = sorted.first else { return 0 }
        guard Calendar.current.isDateInToday(latest.date) else { return 0 }
        guard let previous = sorted.dropFirst().first else { return latest.ovrScore - 50 }
        return latest.ovrScore - previous.ovrScore
    }

    private var todayOVRDeltaText: String {
        if todayOVRDelta > 0 {
            "+\(todayOVRDelta)"
        } else {
            "\(todayOVRDelta)"
        }
    }

    private func missionLabel(for mission: Mission) -> String {
        let day = max(viewModel.missions.count, 1)
        return "DAY \(day) BLOCK"
    }

    private func missionSummaryPreview(_ summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = trimmed
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let firstSentence = sentences.first {
            return firstSentence + "."
        }

        if trimmed.count > 170 {
            let end = trimmed.index(trimmed.startIndex, offsetBy: 167)
            return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }

        return trimmed
    }

    private func missionButtonTitle(_ status: MissionStatus) -> String {
        switch status {
        case .pending:
            "Start Protected Focus"
        case .active:
            "Continue"
        case .completed, .recovered:
            "Completed"
        case .failed:
            "Recovery Mission"
        }
    }

    private func missionButtonIcon(_ status: MissionStatus) -> String {
        switch status {
        case .pending:
            "play.fill"
        case .active:
            "timer"
        case .completed, .recovered:
            "checkmark.circle.fill"
        case .failed:
            "arrow.counterclockwise"
        }
    }

    private func missionButtonColor(_ status: MissionStatus) -> Color {
        switch status {
        case .pending, .active, .completed, .recovered:
            .climbGreen
        case .failed:
            .climbGold
        }
    }

    private func missionStatusIcon(_ status: MissionStatus) -> String {
        switch status {
        case .pending:
            "circle"
        case .active:
            "timer"
        case .completed, .recovered:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: MissionStatus) -> Color {
        switch status {
        case .pending:
            .climbMuted
        case .active:
            .climbGold
        case .completed, .recovered:
            .climbGreen
        case .failed:
            .climbRed
        }
    }

}

private struct FaithFocusCommandCenter: View {
    let focusState: FocusModeState
    let blockedItemCount: Int
    let adultWebFilterEnabled: Bool
    let streak: Int
    let protectedMinutes: Int
    let isMissionReady: Bool
    let isPreparingPlan: Bool
    let onStart: () -> Void
    let onSetup: () -> Void

    var body: some View {
        HomeSurface(padding: 0, cornerRadius: 30, accent: statusColor, prominence: .hero) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(ClimbTypography.sans(17, weight: .semibold))
                            .foregroundStyle(statusColor)
                            .frame(width: 42, height: 42)
                            .background(statusColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Faith Focus")
                                .font(ClimbTypography.sans(12, weight: .semibold))
                                .tracking(1.35)
                                .foregroundStyle(Color.climbTextSecondary)
                                .textCase(.uppercase)
                            Text(statusTitle)
                                .font(ClimbTypography.sans(15, weight: .semibold))
                                .foregroundStyle(statusColor)
                        }

                        Spacer(minLength: 0)

                        Text(protectionBadgeText)
                            .font(ClimbTypography.sans(12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(hasProtection ? Color.climbMist : Color.climbGold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.18), in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Block what pulls you away.")
                            .font(ClimbTypography.sans(31, weight: .semibold))
                            .tracking(-0.45)
                            .foregroundStyle(Color.climbMist)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Protect scripture, prayer, and focused work. During a protected focus block, The Climb restricts your selected distractions and can enable Apple’s adult website filter.")
                            .font(ClimbTypography.sans(15, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        FocusMetricTile(value: "\(protectedMinutes)m", label: "today", tint: .climbGreen)
                        FocusMetricTile(value: "\(streak)", label: streak == 1 ? "day" : "days", tint: .climbGold)
                        FocusMetricTile(
                            value: adultWebFilterEnabled ? "18+" : (blockedItemCount > 0 ? "Ready" : "Pick"),
                            label: adultWebFilterEnabled ? (focusState == .active ? "blocking" : "focus ready") : "apps",
                            tint: hasProtection ? .climbSage : .climbGold
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 16)

                VStack(spacing: 10) {
                    PrimaryActionButton(
                        title: primaryActionTitle,
                        systemImage: primaryActionIcon,
                        tint: .climbGreen,
                        isDisabled: !isMissionReady || isPreparingPlan
                    ) {
                        onStart()
                    }

                    Button {
                        HapticFeedback.selection()
                        onSetup()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: hasProtection ? "slider.horizontal.3" : "square.grid.2x2")
                                .font(ClimbTypography.sans(12, weight: .semibold))
                            Text(setupButtonTitle)
                                .font(ClimbTypography.sans(13, weight: .semibold))
                        }
                        .foregroundStyle(Color.climbTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 17)
                .background(Color.black.opacity(0.15))
            }
        }
    }

    private var primaryActionTitle: String {
        if isPreparingPlan { return "Preparing focus block" }
        return hasProtection ? "Start Protected Focus" : "Start Focus Setup"
    }

    private var primaryActionIcon: String {
        hasProtection ? "lock.shield.fill" : "play.fill"
    }

    private var hasProtection: Bool {
        blockedItemCount > 0 || adultWebFilterEnabled
    }

    private var protectionBadgeText: String {
        let isActive = focusState == .active
        if blockedItemCount > 0, adultWebFilterEnabled {
            return isActive ? "\(blockedItemCount) + web on" : "\(blockedItemCount) + web ready"
        }

        if adultWebFilterEnabled {
            return isActive ? "18+ blocking" : "18+ ready"
        }

        if blockedItemCount > 0 {
            return isActive ? "\(blockedItemCount) blocked" : "\(blockedItemCount) ready"
        }

        return "setup needed"
    }

    private var setupButtonTitle: String {
        "Open Focus controls"
    }

    private var statusTitle: String {
        switch focusState {
        case .active:
            "Blocking now"
        case .authorized:
            hasProtection ? "Shield ready" : "Access ready"
        case .permissionRequired:
            "Needs Screen Time access"
        case .selectionRequired:
            "Choose apps to block"
        case .denied:
            "Access denied"
        case .simulated:
            "Timer-only mode"
        case .unavailable:
            "Checking access"
        }
    }

    private var statusColor: Color {
        switch focusState {
        case .active, .authorized:
            hasProtection ? .climbGreen : .climbGold
        case .permissionRequired, .selectionRequired, .simulated, .unavailable:
            .climbGold
        case .denied:
            .climbRed
        }
    }
}

private struct FocusMetricTile: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(tint.opacity(0.88))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.climbBackgroundLifted.opacity(0.50), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.050), lineWidth: 0.7)
        )
    }
}

private enum HomeSurfaceProminence {
    case hero
    case primary
    case quiet

    var fillOpacity: Double {
        switch self {
        case .hero: 0.86
        case .primary: 0.76
        case .quiet: 0.58
        }
    }

    var borderOpacity: Double {
        switch self {
        case .hero: 0.105
        case .primary: 0.075
        case .quiet: 0.052
        }
    }

    var accentOpacity: Double {
        switch self {
        case .hero: 0.040
        case .primary: 0.024
        case .quiet: 0.010
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .hero: 22
        case .primary: 16
        case .quiet: 10
        }
    }
}

private struct HomeSurface<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    var accent: Color = .climbGreen
    var prominence: HomeSurfaceProminence = .primary
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.climbSurface.opacity(prominence.fillOpacity))
                .overlay(alignment: .topLeading) {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.038),
                            accent.opacity(prominence.accentOpacity),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(prominence.borderOpacity), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.20), radius: prominence.shadowRadius, x: 0, y: prominence == .hero ? 12 : 7)
        .climbEntrance()
    }
}

private struct HomeStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(ClimbTypography.sans(12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.10), in: Capsule())
    }
}

private struct StreakOverview: View {
    let streak: Int
    let goal: Int
    let delta: Int

    private var remaining: Int {
        max(goal - streak, 0)
    }

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(streak) / Double(goal), 1)
    }

    private var deltaText: String {
        if delta > 0 { return "+\(delta)" }
        return "\(delta)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                HeaderMetric(value: "\(streak)", label: streak == 1 ? "day" : "days", tint: .climbGreen)
                HeaderMetric(value: remaining == 0 ? "Goal" : "\(remaining)", label: remaining == 0 ? "reached" : "left", tint: .climbWarm)
                HeaderMetric(value: delta == 0 ? "0" : deltaText, label: "OVR today", tint: delta >= 0 ? .climbGreen : .climbRed)
            }

            ProgressBar(value: progress, height: 3, tint: .climbGreen)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(Color.climbBackgroundLifted.opacity(0.40), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.climbHairline.opacity(0.78), lineWidth: 0.7)
        )
    }
}

private struct HeaderMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(ClimbTypography.sans(19, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(tint.opacity(0.85))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MissionMetadataRow: View {
    let mission: Mission

    var body: some View {
        HStack(spacing: 0) {
            MissionMetadataItem(value: "\(mission.durationMinutes)", label: "min")
            VerticalDivider()
            MissionMetadataItem(value: "\(mission.difficulty)", label: "level")
            VerticalDivider()
            MissionMetadataItem(value: mission.category.rawValue, label: "type")
        }
        .padding(.vertical, 13)
        .background(Color.climbBackgroundLifted.opacity(0.52), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.045), lineWidth: 0.6)
        )
    }
}

private struct FocusProtectionStrip: View {
    let mission: Mission

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: mission.appBlockingEnabled ? "lock.shield.fill" : "target")
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(mission.appBlockingEnabled ? Color.climbGreen : Color.climbGold)
                    .frame(width: 30, height: 30)
                    .background(
                        (mission.appBlockingEnabled ? Color.climbGreen : Color.climbGold).opacity(0.11),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(mission.appBlockingEnabled ? "Protected focus window" : "Manual focus window")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    Text(mission.appBlockingEnabled ? "Selected apps stay locked while the timer runs." : "Start the timer and keep the promise yourself.")
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                MissionPill(value: "\(mission.durationMinutes)m", label: "time")
                MissionPill(value: "L\(mission.difficulty)", label: "level")
                MissionPill(value: mission.category.rawValue, label: "path")
            }
        }
        .padding(12)
        .background(Color.climbBackgroundLifted.opacity(0.48), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.climbHairline.opacity(0.82), lineWidth: 0.7)
        )
    }
}

private struct MissionPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(ClimbTypography.sans(12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(ClimbTypography.sans(9, weight: .semibold))
                .tracking(0.55)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.045), lineWidth: 0.6)
        )
    }
}

private struct MissionMetadataItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.climbDivider.opacity(0.8))
            .frame(width: 1, height: 28)
    }
}

private struct HomeMicroStat: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(12, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(ClimbTypography.sans(16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.climbMist)
                Text(label)
                    .font(ClimbTypography.sans(10, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.climbSurfaceRaised.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.045), lineWidth: 0.6)
        )
    }
}

private struct MissionFact: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.climbSurfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DevotionalFocusOverlay: View {
    let devotional: Devotional
    let selectedFeedback: DailyContentFeedbackRating?
    let onFeedback: (DailyContentFeedbackRating) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ClimbScreenBackground()
                .ignoresSafeArea()

            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("TODAY’S DEVOTIONAL")
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Color.climbMuted)

                        Text(devotional.title)
                            .font(ClimbTypography.serif(40))
                            .foregroundStyle(Color.climbMist)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(devotional.bibleVerse)
                            .font(ClimbTypography.sans(13, weight: .semibold))
                            .foregroundStyle(Color.climbMuted)

                        if let verseText = devotional.verseText, !verseText.isEmpty {
                            Text("“\(verseText)”")
                                .font(ClimbTypography.serif(27))
                                .foregroundStyle(Color.climbWarm)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 8)
                            ScriptureAttributionText(reference: devotional.bibleVerse)
                        }

                        Text(devotional.explanation)
                            .font(ClimbTypography.sans(15))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)

                    ClimbCard(padding: 22, cornerRadius: 24) {
                        Text("Reflection")
                            .font(ClimbTypography.sans(13, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Color.climbMuted)
                        Text(devotional.reflectionQuestion)
                            .font(ClimbTypography.serif(26))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ClimbCard(padding: 22, cornerRadius: 24) {
                        Text("Action")
                            .font(ClimbTypography.sans(13, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Color.climbMuted)
                        Text(devotional.practicalAction)
                            .font(ClimbTypography.sans(16, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DailyContentFeedbackStrip(
                        title: "Daily Word fit",
                        selected: selectedFeedback,
                        onSelect: onFeedback
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 82)
                .padding(.bottom, 54)
            }
            .scrollIndicators(.hidden)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.climbSurfaceGlass, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.top, 18)
            .padding(.trailing, 20)
            .accessibilityLabel("Close devotional")
        }
        .transition(.opacity)
    }
}

private struct DevotionalDetailView: View {
    let devotional: Devotional

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ClimbCard(padding: 24, cornerRadius: 24, isProminent: true) {
                    Label("Today’s Devotional", systemImage: "book.closed.fill")
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Color.climbMuted)

                    Text(devotional.title)
                        .font(ClimbTypography.serif(38))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(devotional.bibleVerse)
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)

                    if let verseText = devotional.verseText, !verseText.isEmpty {
                        Text("“\(verseText)”")
                            .font(ClimbTypography.serif(27))
                            .foregroundStyle(Color.climbWarm)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                        ScriptureAttributionText(reference: devotional.bibleVerse)
                    }

                    Text(devotional.explanation)
                        .font(ClimbTypography.sans(15))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ClimbCard(padding: 22, cornerRadius: 24) {
                    Text("Reflection")
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Color.climbMuted)
                    Text(devotional.reflectionQuestion)
                        .font(ClimbTypography.serif(24))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ClimbCard(padding: 22, cornerRadius: 24) {
                    Text("Action")
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Color.climbMuted)
                    Text(devotional.practicalAction)
                        .font(ClimbTypography.sans(16, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .background(ClimbScreenBackground())
        .navigationTitle("Devotional")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct QuickActionTile: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(Color.climbGreen)
                .frame(width: 32, height: 32)
                .background(Color.climbGreen.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(detail)
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.climbBackgroundLifted.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.climbHairline.opacity(0.72), lineWidth: 0.7)
        )
    }
}

private struct JournalHistoryView: View {
    let entries: [ReflectionEntry]
    let exportText: String
    @State private var searchText = ""
    @State private var filter: JournalFilter = .all

    var body: some View {
        ScreenContainer(title: "Journal") {
            if entries.isEmpty {
                EmptyState(
                    title: "No reflections yet",
                    detail: "Mission reflections will appear here after completion.",
                    systemImage: "book.pages"
                )
                journalPromptLibrary
            } else {
                journalHeader
                journalPromptLibrary
                journalSearchField
                journalFilterRow

                if filteredEntries.isEmpty {
                    EmptyState(
                        title: "No matching reflections",
                        detail: "Try a different word, mood, or reset the filter.",
                        systemImage: "magnifyingglass"
                    )
                } else {
                    ForEach(filteredEntries) { entry in
                        JournalEntryCard(entry: entry)
                    }
                }
            }
        }
    }

    private var sortedEntries: [ReflectionEntry] {
        entries.sorted { $0.date > $1.date }
    }

    private var filteredEntries: [ReflectionEntry] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sortedEntries.filter { entry in
            let matchesFilter = filter.matches(entry)
            let matchesSearch = trimmedSearch.isEmpty || [
                entry.hardestPart,
                entry.lessonLearned,
                entry.improvementPlan,
                entry.failureReason ?? "",
                entry.mood.rawValue
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(trimmedSearch)

            return matchesFilter && matchesSearch
        }
    }

    private var failureCount: Int {
        entries.filter { entry in
            guard let reason = entry.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return !reason.isEmpty
        }.count
    }

    private var averageEffort: Int {
        guard !entries.isEmpty else { return 0 }
        let total = entries.reduce(0) { $0 + $1.effortRating }
        return Int((Double(total) / Double(entries.count)).rounded())
    }

    private var journalHeader: some View {
        ClimbCard(padding: 20, cornerRadius: 24, isProminent: true) {
            Text("REFLECTION HISTORY")
                .font(ClimbTypography.sans(11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.climbGreen.opacity(0.86))
            Text("\(entries.count) saved reflections")
                .font(ClimbTypography.serif(31))
                .foregroundStyle(Color.climbMist)
            Text("Search what was hard, what you learned, and what changed after each mission.")
                .font(ClimbTypography.sans(14, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)

            HStack(spacing: 10) {
                JournalMetric(value: "\(averageEffort)/5", label: "effort")
                JournalMetric(value: "\(failureCount)", label: "failures")
                JournalMetric(value: "\(Set(entries.map(\.mood)).count)", label: "moods")
            }

            ShareLink(item: exportText) {
                Label("Export private journal", systemImage: "square.and.arrow.up")
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.climbBackgroundLifted.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
                    )
            }
        }
    }

    private var journalPromptLibrary: some View {
        ClimbCard(padding: 20, cornerRadius: 24) {
            SectionTitle(
                title: "Prompt Library",
                subtitle: "Use one of these when a reflection feels vague."
            )

            VStack(spacing: 10) {
                ForEach(JournalPrompt.allCases) { prompt in
                    JournalPromptCard(prompt: prompt)
                }
            }
        }
    }

    private var journalSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
            TextField("Search reflections", text: $searchText)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(Color.climbMist)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    HapticFeedback.selection()
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.climbMuted)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(14)
        .background(Color.climbSurfaceRaised.opacity(0.62), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
        )
    }

    private var journalFilterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(JournalFilter.allCases) { option in
                    Button {
                        HapticFeedback.selection()
                        withAnimation(ClimbMotion.quick) {
                            filter = option
                        }
                    } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .foregroundStyle(filter == option ? Color.climbInk : Color.climbTextSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                filter == option ? Color.climbGreen : Color.climbBackgroundLifted.opacity(0.62),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }
}

private enum JournalPrompt: String, CaseIterable, Identifiable {
    case conviction
    case recovery
    case gratitude
    case obedience

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conviction:
            "Conviction"
        case .recovery:
            "Recovery"
        case .gratitude:
            "Gratitude"
        case .obedience:
            "Obedience"
        }
    }

    var question: String {
        switch self {
        case .conviction:
            "What truth did I avoid before the mission started?"
        case .recovery:
            "What is the smallest honest step after a miss?"
        case .gratitude:
            "Where did God give help I would usually overlook?"
        case .obedience:
            "What is one action I need to take before I feel ready?"
        }
    }

    var symbol: String {
        switch self {
        case .conviction:
            "flame"
        case .recovery:
            "arrow.triangle.2.circlepath"
        case .gratitude:
            "heart"
        case .obedience:
            "figure.walk"
        }
    }
}

private struct JournalPromptCard: View {
    let prompt: JournalPrompt

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: prompt.symbol)
                .font(ClimbTypography.sans(14, weight: .semibold))
                .foregroundStyle(Color.climbGreen)
                .frame(width: 34, height: 34)
                .background(Color.climbGreen.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(prompt.title)
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)
                Text(prompt.question)
                    .font(ClimbTypography.serif(22))
                    .foregroundStyle(Color.climbWarm)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.climbBackgroundLifted.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
        )
    }
}

private enum JournalFilter: String, CaseIterable, Identifiable {
    case all
    case strong
    case steady
    case low
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .strong: "Strong"
        case .steady: "Steady"
        case .low: "Low"
        case .failed: "Failures"
        }
    }

    var symbol: String {
        switch self {
        case .all: "book.pages"
        case .strong: "arrow.up.circle"
        case .steady: "equal.circle"
        case .low: "arrow.down.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    func matches(_ entry: ReflectionEntry) -> Bool {
        switch self {
        case .all:
            true
        case .strong:
            entry.mood == .strong
        case .steady:
            entry.mood == .steady
        case .low:
            entry.mood == .low
        case .failed:
            !(entry.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}

private struct JournalMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(16, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color.climbBackgroundLifted.opacity(0.50), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct JournalEntryCard: View {
    let entry: ReflectionEntry

    private var hasFailure: Bool {
        !(entry.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        ClimbCard(cornerRadius: 22) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date, style: .date)
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                    Text(entry.mood.rawValue)
                        .font(ClimbTypography.sans(11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(moodColor)
                        .textCase(.uppercase)
                }
                Spacer()
                Text("\(entry.effortRating)/5")
                    .font(ClimbTypography.sans(13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.climbTextSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.climbBackgroundLifted.opacity(0.62), in: Capsule())
            }

            if hasFailure, let reason = entry.failureReason {
                JournalField(title: "Why it failed", text: reason, accent: Color.climbGold)
            }

            JournalField(title: "Lesson", text: entry.lessonLearned, accent: Color.climbWarm)
            JournalField(title: "Next step", text: entry.improvementPlan, accent: Color.climbTextSecondary)

            if !entry.hardestPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                JournalField(title: "Hardest part", text: entry.hardestPart, accent: Color.climbMuted)
            }
        }
    }

    private var moodColor: Color {
        switch entry.mood {
        case .low:
            Color.climbGold
        case .steady:
            Color.climbSage
        case .strong:
            Color.climbGreen
        }
    }
}

private struct JournalField: View {
    let title: String
    let text: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
            Text(text)
                .font(title == "Lesson" ? ClimbTypography.serif(23) : ClimbTypography.sans(14, weight: .medium))
                .foregroundStyle(accent)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
