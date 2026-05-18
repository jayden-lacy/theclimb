import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isMissionPresented = false
    @State private var focusedDevotional: Devotional?

    var body: some View {
        ScreenContainer(title: "Today", hidesNavigationBar: true, bottomSafeAreaSpacing: 142) {
            if let profile = viewModel.profile {
                homeHeader(profile)
            }

            if let mission = viewModel.todayMission {
                missionCard(mission)
            } else {
                EmptyState(
                    title: "No mission yet",
                    detail: "Your next daily mission will appear after the plan syncs.",
                    systemImage: "flag"
                )
            }

            if let devotional = viewModel.todayDevotional {
                dailyWordSection(devotional)
            }

            quickActionRow
        }
        .sheet(isPresented: $isMissionPresented) {
            if let mission = viewModel.todayMission {
                MissionSessionView(viewModel: viewModel, mission: mission)
            }
        }
        .overlay {
            if let focusedDevotional {
                DevotionalFocusOverlay(
                    devotional: focusedDevotional
                ) {
                    withAnimation(ClimbMotion.focus) {
                        self.focusedDevotional = nil
                    }
                }
                .zIndex(20)
            }
        }
        .toolbar(focusedDevotional == nil ? .visible : .hidden, for: .tabBar)
        .animation(ClimbMotion.focus, value: focusedDevotional?.id)
    }

    private func homeHeader(_ profile: UserProfile) -> some View {
        ClimbCard(padding: 20, cornerRadius: 30, isProminent: true) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(ClimbTypography.sans(12, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.climbGreen)
                        .textCase(.uppercase)

                    Text("One step today.")
                        .font(ClimbTypography.sans(28, weight: .bold))
                        .foregroundStyle(Color.climbMist)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(homeContextLine(for: profile))
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                ScoreRing(value: Double(profile.ovrScore) / 100, text: "\(profile.ovrScore)", size: 58)
            }

            StreakOverview(
                streak: profile.currentStreak,
                goal: profile.streakGoal,
                delta: todayOVRDelta
            )
        }
        .padding(.top, 2)
    }

    private func missionCard(_ mission: Mission) -> some View {
        ClimbCard(padding: 20, cornerRadius: 32, isProminent: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(missionLabel(for: mission))
                            .font(ClimbTypography.sans(11, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(Color.climbMuted)
                        Text("Primary mission")
                            .font(ClimbTypography.sans(13, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                    }
                    Spacer()
                    StatusBadge(text: mission.status.rawValue.capitalized, color: statusColor(mission.status))
                }

                Text(mission.title)
                    .font(ClimbTypography.sans(26, weight: .bold))
                    .foregroundStyle(Color.climbMist)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(missionSummaryPreview(mission.summary))
                    .font(ClimbTypography.sans(15, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(4)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                MissionMetadataRow(mission: mission)

                PrimaryActionButton(
                    title: missionButtonTitle(mission.status),
                    systemImage: missionButtonIcon(mission.status),
                    tint: missionButtonColor(mission.status)
                ) {
                    isMissionPresented = true
                }
            }
        }
        .activeShimmer(mission.status == .active, cornerRadius: 32)
    }

    private func dailyWordSection(_ devotional: Devotional) -> some View {
        Button {
            HapticFeedback.selection()
            withAnimation(ClimbMotion.focus) {
                focusedDevotional = devotional
            }
        } label: {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("DAILY WORD")
                        .font(ClimbTypography.sans(11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.climbGreen)
                    Spacer()
                    Text(devotional.bibleVerse)
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(devotional.title)
                        .font(ClimbTypography.serif(29))
                        .foregroundStyle(Color.climbMist)
                        .fixedSize(horizontal: false, vertical: true)

                    if let verseText = devotional.verseText, !verseText.isEmpty {
                        Text("“\(verseText)”")
                            .font(ClimbTypography.serif(22))
                            .foregroundStyle(Color.climbWarm.opacity(0.92))
                            .lineLimit(4)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(devotional.explanation)
                            .font(ClimbTypography.sans(15))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineLimit(4)
                            .lineSpacing(4)
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    Text(devotional.reflectionQuestion)
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 12)
                    Label("Read", systemImage: "arrow.up.right")
                        .font(ClimbTypography.sans(13, weight: .bold))
                        .foregroundStyle(Color.climbGreen)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 22)
            .padding(.horizontal, 20)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.climbSurfaceGlass)
                    .overlay(
                        RadialGradient(
                            colors: [
                                Color.climbWarm.opacity(0.11),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 340
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.24), radius: 24, x: 0, y: 16)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityLabel("Read full devotional")
    }

    private var quickActionRow: some View {
        HStack(spacing: 12) {
            NavigationLink {
                JournalHistoryView(entries: viewModel.journalEntries)
            } label: {
                QuickActionTile(title: "Journal", systemImage: "book.pages")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { HapticFeedback.selection() })

            NavigationLink {
                ProgressDashboardView(viewModel: viewModel)
            } label: {
                QuickActionTile(title: "View Progress", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { HapticFeedback.selection() })
        }
    }

    private func homeContextLine(for profile: UserProfile) -> String {
        guard let mission = viewModel.todayMission else {
            return "\(profile.mainStruggle.shortLabel) path · preparing today’s plan"
        }

        switch mission.status {
        case .active:
            return "Focus window active."
        case .completed:
            return "\(profile.currentStreak)-day streak · reflection locked in"
        case .recovered:
            return "Recovery counted · keep the next promise small"
        case .failed:
            return "Recovery is available · don’t let one miss become two"
        case .pending:
            if profile.currentStreak == 0 {
                return "\(profile.mainStruggle.shortLabel) path · start with one honest win"
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
        return "DAY \(day) MISSION"
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
            "Start Mission"
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
        HStack(alignment: .center, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(streak)")
                    .font(ClimbTypography.sans(24, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.climbMist)
                    .contentTransition(.numericText())
                Text(streak == 1 ? "day steady" : "days steady")
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(Color.climbTextSecondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(remaining == 0 ? "Goal reached" : "\(remaining) to goal")
                    Spacer(minLength: 6)
                    Text(delta == 0 ? "Steady" : "\(deltaText) OVR")
                }
                .font(ClimbTypography.sans(12, weight: .bold))
                .foregroundStyle(delta >= 0 ? Color.climbGreen : Color.climbRed)

                ProgressBar(value: progress, height: 4, tint: .climbGreen)
            }
        }
        .padding(14)
        .background(Color.climbBackgroundLifted.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
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
        .background(Color.climbBackgroundLifted.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
        )
    }
}

private struct MissionMetadataItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(14, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .bold))
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
                .font(ClimbTypography.sans(12, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(ClimbTypography.sans(16, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.climbMist)
                Text(label)
                    .font(ClimbTypography.sans(10, weight: .bold))
                    .foregroundStyle(Color.climbMuted)
                    .textCase(.uppercase)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.climbSurfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
        )
    }
}

private struct MissionFact: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(15, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .bold))
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
                            .font(ClimbTypography.sans(12, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(Color.climbGreen)

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
                        }

                        Text(devotional.explanation)
                            .font(ClimbTypography.sans(15))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)

                    ClimbCard(padding: 22, cornerRadius: 28) {
                        Text("Reflection")
                            .font(ClimbTypography.sans(13, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color.climbMuted)
                        Text(devotional.reflectionQuestion)
                            .font(ClimbTypography.serif(26))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ClimbCard(padding: 22, cornerRadius: 28) {
                        Text("Action")
                            .font(ClimbTypography.sans(13, weight: .bold))
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
                .padding(.top, 82)
                .padding(.bottom, 54)
            }
            .scrollIndicators(.hidden)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(ClimbTypography.sans(15, weight: .bold))
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
                ClimbCard(padding: 24, cornerRadius: 32, isProminent: true) {
                    Label("Today’s Devotional", systemImage: "book.closed.fill")
                        .font(ClimbTypography.sans(12, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.climbGreen)

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
                    }

                    Text(devotional.explanation)
                        .font(ClimbTypography.sans(15))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ClimbCard(padding: 22, cornerRadius: 28) {
                    Text("Reflection")
                        .font(ClimbTypography.sans(13, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Color.climbMuted)
                    Text(devotional.reflectionQuestion)
                        .font(ClimbTypography.serif(24))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ClimbCard(padding: 22, cornerRadius: 28) {
                    Text("Action")
                        .font(ClimbTypography.sans(13, weight: .bold))
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
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(17, weight: .semibold))
            Text(title)
                .font(ClimbTypography.sans(14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(Color.climbSurfaceGlass, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }
}

private struct JournalHistoryView: View {
    let entries: [ReflectionEntry]

    var body: some View {
        ScreenContainer(title: "Journal") {
            if entries.isEmpty {
                EmptyState(
                    title: "No reflections yet",
                    detail: "Mission reflections will appear here after completion.",
                    systemImage: "book.pages"
                )
            } else {
                ForEach(entries) { entry in
                    ClimbCard(cornerRadius: 28) {
                        Text(entry.date, style: .date)
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .foregroundStyle(Color.climbMuted)
                        Text(entry.lessonLearned)
                            .font(ClimbTypography.serif(24))
                            .foregroundStyle(Color.climbWarm)
                        Text(entry.improvementPlan)
                            .font(ClimbTypography.sans(14))
                            .foregroundStyle(Color.climbTextSecondary)
                    }
                }
            }
        }
    }
}
