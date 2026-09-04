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
        ScreenContainer(
            title: "Focus",
            hidesNavigationBar: true,
            showsScrollIndicators: false,
            bottomSafeAreaSpacing: 142
        ) {
            if let profile = viewModel.profile {
                opalHomeHeader(profile)
                climbTimeDashboard(profile)
                compactDailyClimb(profile)
            }

            if let mission = viewModel.todayMission {
                compactMissionCard(mission)
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
#if DEBUG
            guard !ProcessInfo.processInfo.arguments.contains("-screenshotFixture") else {
                return
            }
#endif
            Task {
                await viewModel.refreshScreenTimeAuthorization()
                viewModel.refreshClimbControlState()
            }
        }
#else
        .task {
            await viewModel.refreshScreenTimeAuthorization()
            viewModel.refreshClimbControlState()
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

    private func opalHomeHeader(_ profile: UserProfile) -> some View {
        HStack(spacing: 13) {
            Image("BrandLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("The Climb")
                    .font(ClimbTypography.sans(17, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)
            }

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.climbGold)
                Text("\(profile.currentStreak)")
                    .font(ClimbTypography.sans(15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.climbMist)
                Text(profile.currentStreak == 1 ? "day" : "days")
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .foregroundStyle(Color.climbTextSecondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.climbSurfaceRaised.opacity(0.62), in: Capsule())
            .overlay {
                Capsule().stroke(Color.climbHairline, lineWidth: 0.75)
            }
        }
        .padding(.top, 1)
        .climbEntrance()
    }

    private func climbTimeDashboard(_ profile: UserProfile) -> some View {
        let wallet = viewModel.climbTimeWallet
        let totalAllowance = max(
            1,
            min(
                (wallet?.baseAllowanceSeconds ?? 30 * 60)
                    + (wallet?.earnedSeconds ?? 0),
                wallet?.hardStopSeconds ?? 60 * 60
            )
        )
        let consumed = min(wallet?.consumedSeconds ?? 0, totalAllowance)
        let remaining = max(0, totalAllowance - consumed)
        let progress = Double(consumed) / Double(totalAllowance)

        return VStack(spacing: 18) {
            VStack(spacing: 7) {
                Text("CLIMB TIME")
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Color.climbTextSecondary)

                Text(durationLabel(remaining))
                    .font(ClimbTypography.sans(52, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.climbMist)
                    .contentTransition(.numericText())

                Text(climbTimeRemainingCaption(remaining: remaining))
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
            }

            ClimbTimeFocusDial(
                progress: progress,
                isActive: viewModel.focusState == .active,
                statusColor: climbTimeStatusColor
            )

            VStack(spacing: 12) {
                HStack {
                    Text("Selected app use")
                    Spacer()
                    Text("\(durationLabel(consumed)) used")
                        .monospacedDigit()
                }
                .font(ClimbTypography.sans(12, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)

                ClimbTimeAllowanceRail(progress: progress)

                HStack(spacing: 0) {
                    FocusDashboardMetric(
                        value: wallet.map { "+\(durationLabel($0.earnedSeconds))" } ?? "+0m",
                        label: "earned",
                        tint: .climbSage
                    )
                    FocusDashboardDivider()
                    FocusDashboardMetric(
                        value: wallet.map { durationLabel($0.hardStopSeconds) } ?? "60m",
                        label: "hard stop",
                        tint: .climbGold
                    )
                    FocusDashboardDivider()
                    FocusDashboardMetric(
                        value: "\(profile.ovrScore)",
                        label: "momentum",
                        tint: .climbViolet
                    )
                }
            }

            PrimaryActionButton(
                title: primaryFocusActionTitle,
                systemImage: primaryFocusActionIcon,
                tint: .climbGreen
            ) {
                HapticFeedback.impact(.medium)
                showFocusControlCenter = true
            }

            Button {
                HapticFeedback.selection()
                showFocusControlCenter = true
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(climbTimeStatusColor)
                        .frame(width: 7, height: 7)
                    Text(climbTimeStatusTitle)
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .foregroundStyle(Color.climbTextSecondary)
                    Spacer(minLength: 8)
                    Text(protectionConfigurationLabel)
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.climbMuted)
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityHint("Opens Climb Control settings")
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 5)
        .climbEntrance()
    }

    private func compactDailyClimb(_ profile: UserProfile) -> some View {
        let dailyClimb = viewModel.dailyClimb

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today")
                        .font(ClimbTypography.sans(21, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    Text(nextDailyStepTitle(dailyClimb))
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbMuted)
                }

                Spacer(minLength: 12)

                Text("\(dailyClimb.completedCount)/\(dailyClimb.actions.count)")
                    .font(ClimbTypography.sans(13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.climbTextSecondary)
            }

            HStack(spacing: 8) {
                ForEach(dailyClimb.actions) { action in
                    DailyClimbStatusMarker(action: action)
                }
            }

            ProgressBar(value: dailyClimb.progress, height: 3, tint: .climbGreen)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today’s Climb for \(profile.displayName)")
    }

    private func compactMissionCard(_ mission: Mission) -> some View {
        HomeSurface(
            padding: 18,
            cornerRadius: 22,
            accent: statusColor(mission.status),
            prominence: .primary
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text("TODAY’S MISSION")
                        .font(ClimbTypography.sans(10, weight: .semibold))
                        .tracking(1.35)
                        .foregroundStyle(Color.climbTextSecondary)
                    Spacer(minLength: 8)
                    HomeStatusBadge(
                        text: mission.status.rawValue.capitalized,
                        color: statusColor(mission.status)
                    )
                }

                Button {
                    HapticFeedback.selection()
                    isMissionPresented = true
                } label: {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(mission.title)
                                .font(ClimbTypography.sans(20, weight: .semibold))
                                .foregroundStyle(Color.climbMist)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 7) {
                                Label("\(mission.durationMinutes) min", systemImage: "timer")
                                Text("·")
                                Text(mission.category.rawValue)
                            }
                            .font(ClimbTypography.sans(12, weight: .medium))
                            .foregroundStyle(Color.climbMuted)
                        }

                        Spacer(minLength: 6)

                        Image(systemName: missionButtonIcon(mission.status))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.climbInk)
                            .frame(width: 46, height: 46)
                            .background(missionButtonColor(mission.status), in: Circle())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(missionButtonTitle(mission.status)): \(mission.title)")

                if mission.status == .pending {
                    Button {
                        HapticFeedback.selection()
                        isRegenerationDialogPresented = true
                    } label: {
                        Label("Adjust mission", systemImage: "slider.horizontal.3")
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .foregroundStyle(Color.climbTextSecondary)
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(!viewModel.canRegenerateTodayPlan)
                    .opacity(viewModel.canRegenerateTodayPlan ? 1 : 0.45)
                }
            }
        }
    }

    private var primaryFocusActionTitle: String {
        switch viewModel.focusState {
        case .active:
            "View Active Focus"
        case .permissionRequired, .selectionRequired, .denied, .unavailable:
            "Set Up Climb Control"
        case .authorized, .simulated:
            selectedBlockingItemCount > 0 || adultWebFilterEnabled
                ? "Start Focus"
                : "Choose Distractions"
        }
    }

    private var primaryFocusActionIcon: String {
        viewModel.focusState == .active ? "timer" : "lock.fill"
    }

    private var climbTimeStatusTitle: String {
        switch viewModel.climbTimeMonitoringState {
        case .scheduled:
            "Climb Time active"
        case .permissionRequired:
            "Screen Time access needed"
        case .selectionRequired:
            "Choose distractions"
        case .degraded:
            "Protection needs attention"
        case .unavailable:
            "Checking protection"
        }
    }

    private var climbTimeStatusColor: Color {
        switch viewModel.climbTimeMonitoringState {
        case .scheduled:
            .climbGreen
        case .permissionRequired, .selectionRequired, .unavailable:
            .climbGold
        case .degraded:
            .climbRed
        }
    }

    private var protectionConfigurationLabel: String {
        if adultWebFilterEnabled, selectedBlockingItemCount > 0 {
            return "\(selectedBlockingItemCount) items + web"
        }
        if adultWebFilterEnabled {
            return "18+ web filter"
        }
        if selectedBlockingItemCount > 0 {
            return "\(selectedBlockingItemCount) selected"
        }
        return "Manage"
    }

    private func climbTimeRemainingCaption(remaining: Int) -> String {
        guard viewModel.climbTimeMonitoringState == .scheduled else {
            return "daily allowance after setup"
        }
        return remaining == 0
            ? "distractions paused"
            : "remaining for selected apps"
    }

    private func nextDailyStepTitle(_ dailyClimb: DailyClimb) -> String {
        if let next = dailyClimb.actions.first(where: {
            $0.state != .completed && $0.state != .unavailable
        }) {
            return "Next: \(next.title)"
        }
        return dailyClimb.completedCount == dailyClimb.actions.count
            ? "Today is complete"
            : "Keep the next step small"
    }

    private func durationLabel(_ seconds: Int) -> String {
        let minutes = max(0, seconds / 60)
        return "\(minutes)m"
    }

    private var selectedBlockingItemCount: Int {
#if canImport(FamilyControls) && os(iOS)
        if #available(iOS 16.0, *) {
            return activitySelection.shieldableContentCount
        }
#endif
        return 0
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
            HomeSurface(padding: 19, cornerRadius: 22, accent: .climbWarm, prominence: .quiet) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Daily Word")
                            .font(ClimbTypography.sans(10, weight: .semibold))
                            .tracking(1.35)
                            .foregroundStyle(Color.climbTextSecondary)
                            .textCase(.uppercase)
                        Spacer(minLength: 12)
                        Text(devotional.bibleVerse)
                            .font(ClimbTypography.sans(11, weight: .semibold))
                            .foregroundStyle(Color.climbMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Text(devotional.title)
                        .font(ClimbTypography.serif(24))
                        .foregroundStyle(Color.climbMist)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let verseText = devotional.verseText, !verseText.isEmpty {
                        Text("“\(verseText)”")
                            .font(ClimbTypography.serif(18))
                            .foregroundStyle(Color.climbWarm.opacity(0.92))
                            .lineLimit(3)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(devotional.explanation)
                            .font(ClimbTypography.sans(14))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineLimit(3)
                            .lineSpacing(3)
                    }

                    HStack(spacing: 8) {
                        ScriptureAttributionText(reference: devotional.bibleVerse)
                        Spacer(minLength: 8)
                        Text("Read")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbGreen)
                    .frame(minHeight: 22)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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

private struct ClimbTimeFocusDial: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double
    let isActive: Bool
    let statusColor: Color

    private var normalizedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.climbSurface.opacity(0.74))
                .frame(width: 154, height: 154)
                .shadow(color: statusColor.opacity(isActive ? 0.16 : 0.07), radius: 30)

            Circle()
                .stroke(Color.white.opacity(0.065), lineWidth: 9)
                .frame(width: 170, height: 170)

            Circle()
                .trim(from: 0, to: normalizedProgress)
                .stroke(
                    statusColor,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .frame(width: 170, height: 170)
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : ClimbMotion.slow, value: normalizedProgress)

            Image("BrandLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 29, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                }

            if isActive {
                Circle()
                    .fill(Color.climbGreen)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.climbBackgroundDeep, lineWidth: 3))
                    .offset(x: 59, y: -59)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Climb Time")
        .accessibilityValue("\(Int(normalizedProgress * 100)) percent used")
    }
}

private struct ClimbTimeAllowanceRail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double
    private let segmentCount = 20

    private var consumedSegments: Int {
        Int((min(max(progress, 0), 1) * Double(segmentCount)).rounded(.up))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < consumedSegments ? Color.climbGold : Color.climbDivider.opacity(0.78))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 5)
        .animation(reduceMotion ? nil : ClimbMotion.standard, value: consumedSegments)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily allowance used")
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}

private struct FocusDashboardMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(ClimbTypography.sans(17, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(ClimbTypography.sans(9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(tint.opacity(0.9))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct FocusDashboardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.climbHairline)
            .frame(width: 1, height: 30)
            .accessibilityHidden(true)
    }
}

private struct DailyClimbStatusMarker: View {
    let action: DailyClimbAction

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 38, height: 38)
                .background(backgroundColor, in: Circle())
                .overlay {
                    Circle().stroke(borderColor, lineWidth: 0.75)
                }

            Text(shortLabel)
                .font(ClimbTypography.sans(9, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(action.title), \(stateLabel)")
    }

    private var shortLabel: String {
        switch action.kind {
        case .scripture: "Word"
        case .prayer: "Prayer"
        case .mission: "Mission"
        case .screenGoal: "Limit"
        case .reflection: "Reflect"
        }
    }

    private var icon: String {
        switch action.state {
        case .completed: "checkmark"
        case .inProgress: "timer"
        case .needsAttention: "exclamationmark"
        case .unavailable: "minus"
        case .ready:
            switch action.kind {
            case .scripture: "book.closed"
            case .prayer: "hands.sparkles"
            case .mission: "flag"
            case .screenGoal: "hourglass"
            case .reflection: "square.and.pencil"
            }
        }
    }

    private var foregroundColor: Color {
        switch action.state {
        case .completed: .climbInk
        case .inProgress: .climbGreen
        case .needsAttention: .climbGold
        case .ready: .climbTextSecondary
        case .unavailable: .climbMuted
        }
    }

    private var backgroundColor: Color {
        switch action.state {
        case .completed: .climbGreen
        case .inProgress: .climbGreen.opacity(0.12)
        case .needsAttention: .climbGold.opacity(0.12)
        case .ready: .climbSurfaceRaised.opacity(0.72)
        case .unavailable: .climbBackgroundLifted.opacity(0.60)
        }
    }

    private var borderColor: Color {
        switch action.state {
        case .completed: .climbGreen.opacity(0.45)
        case .inProgress: .climbGreen.opacity(0.32)
        case .needsAttention: .climbGold.opacity(0.32)
        case .ready, .unavailable: .climbHairline
        }
    }

    private var stateLabel: String {
        switch action.state {
        case .completed: "done"
        case .inProgress: "active"
        case .needsAttention: "needs attention"
        case .ready: "ready"
        case .unavailable: "later"
        }
    }
}

private struct DailyClimbActionRow: View {
    let action: DailyClimbAction

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: actionIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(actionColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                if let detail = action.detail, !detail.isEmpty {
                    Text(detail)
                        .font(ClimbTypography.sans(11, weight: .medium))
                        .foregroundStyle(Color.climbMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(statusLabel)
                .font(ClimbTypography.sans(11, weight: .semibold))
                .foregroundStyle(actionColor)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }

    private var actionIcon: String {
        switch action.state {
        case .completed:
            "checkmark.circle.fill"
        case .inProgress:
            "circle.dotted.circle.fill"
        case .needsAttention:
            "exclamationmark.circle.fill"
        case .ready:
            iconForKind
        case .unavailable:
            "minus.circle"
        }
    }

    private var iconForKind: String {
        switch action.kind {
        case .scripture:
            "book.closed"
        case .prayer:
            "hands.sparkles"
        case .mission:
            "flag"
        case .screenGoal:
            "hourglass"
        case .reflection:
            "square.and.pencil"
        }
    }

    private var actionColor: Color {
        switch action.state {
        case .completed:
            .climbGreen
        case .inProgress:
            .climbSage
        case .needsAttention:
            .climbGold
        case .ready:
            .climbTextSecondary
        case .unavailable:
            .climbMuted
        }
    }

    private var statusLabel: String {
        switch action.state {
        case .completed:
            "Done"
        case .inProgress:
            "Active"
        case .needsAttention:
            "Recover"
        case .ready:
            "Ready"
        case .unavailable:
            "Later"
        }
    }
}

private struct ClimbTimeSummaryMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ClimbTypography.sans(17, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(ClimbTypography.sans(9, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(Color.climbTextSecondary)
                .textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    prominence == .hero ? Color.climbSurfaceLine.opacity(0.94) : Color.white.opacity(prominence.borderOpacity),
                    lineWidth: 0.75
                )
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
