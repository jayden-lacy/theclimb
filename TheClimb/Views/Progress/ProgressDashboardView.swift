import Charts
import SwiftUI

struct ProgressDashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isGeneratingLetter = false

    private var orderedProgress: [ProgressSnapshot] {
        viewModel.progress.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScreenContainer(title: "Progress") {
            if let profile = viewModel.profile {
                progressHeader(profile)
                OVRScoreCard(score: profile.ovrScore, delta: latestDelta)
                achievementCard
                ovrRulesCard
                statsCards(profile)
            }

            ovrChart
            reportCard
            monthlyLetterCard
            categoryCard
        }
    }

    private func progressHeader(_ profile: UserProfile) -> some View {
        ClimbPageHeader(
            eyebrow: "Focus report",
            title: "Proof of return",
            subtitle: "\(profile.currentStreak) day streak · \(Int(viewModel.completionRate * 100))% completion · \(profile.mainStruggle.shortLabel) path"
        ) {
            VStack(alignment: .center, spacing: 5) {
                Text("\(Int(viewModel.completionRate * 100))%")
                    .font(ClimbTypography.sans(25, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.climbMist)
                Text("DONE")
                    .font(ClimbTypography.sans(10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.climbMuted)
            }
            .frame(width: 74, height: 62)
            .background(Color.climbBackgroundLifted.opacity(0.46), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color.climbHairline, lineWidth: 0.75)
            )
        }
    }

    private func statsCards(_ profile: UserProfile) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(title: "Completed", value: "\(completedCount)", symbol: "checkmark.circle", tint: .climbSage)
            MetricTile(title: "Failed", value: "\(failedCount)", symbol: "xmark.circle", tint: .climbRed)
            MetricTile(title: "Streak", value: "\(profile.currentStreak)", symbol: "flame", tint: .climbGold)
            MetricTile(title: "Longest", value: "\(profile.longestStreak)", symbol: "medal", tint: .climbBlue)
        }
    }

    private var ovrChart: some View {
        ClimbQuietPanel(padding: 20, cornerRadius: 22, isProminent: true) {
            SectionTitle(title: "Momentum", subtitle: "The line matters less than the return.")
            if orderedProgress.isEmpty {
                EmptyState(
                    title: "No progress yet",
                    detail: "Complete your first mission to start charting OVR movement. Baseline starts at 50.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            } else {
                Chart(orderedProgress) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.date),
                        y: .value("OVR", snapshot.ovrScore)
                    )
                    .foregroundStyle(Color.climbSage)
                    .symbol(Circle())
                    AreaMark(
                        x: .value("Date", snapshot.date),
                        y: .value("OVR", snapshot.ovrScore)
                    )
                    .foregroundStyle(Color.climbSage.opacity(0.12))
                }
                .frame(height: 190)
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel().foregroundStyle(Color.climbMuted)
                    }
                }
            }
        }
    }

    private var reportCard: some View {
        ClimbQuietPanel(cornerRadius: 22) {
            SectionTitle(title: "Weekly Pulse")
            Text(viewModel.weeklyReport)
                .font(ClimbTypography.sans(15))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
            ProgressBar(value: viewModel.completionRate, height: 6, tint: .climbSage)
            Text("\(Int(viewModel.completionRate * 100))% mission completion")
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
        }
    }

    private var achievementCard: some View {
        let unlocked = viewModel.unlockedAchievements
        let next = Array(viewModel.nextAchievements.prefix(4))

        return ClimbQuietPanel(padding: 20, cornerRadius: 24, accent: .climbGold, isProminent: true) {
            SectionTitle(
                title: "Badges",
                subtitle: "Earned through focus, prayer, recovery, scripture, and accountability."
            )

            HStack(spacing: 10) {
                AchievementSummaryMetric(
                    value: "\(unlocked.count)",
                    label: "earned",
                    tint: .climbGold
                )
                AchievementSummaryMetric(
                    value: "\(viewModel.achievements.count)",
                    label: "total",
                    tint: .climbSage
                )
                AchievementSummaryMetric(
                    value: "\(Int(viewModel.achievementCompletionRate * 100))%",
                    label: "complete",
                    tint: .climbBlue
                )
            }

            ProgressBar(value: viewModel.achievementCompletionRate, height: 5, tint: .climbGold)

            if unlocked.isEmpty {
                EmptyState(
                    title: "No badges yet",
                    detail: "Complete your first protected focus block to earn First Yes.",
                    systemImage: "seal"
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Earned")
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .tracking(1.25)
                        .foregroundStyle(Color.climbMuted)
                        .textCase(.uppercase)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(unlocked) { achievement in
                                AchievementBadgePill(achievement: achievement, isCompact: true)
                            }
                        }
                    }
                }
            }

            if !next.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next up")
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .tracking(1.25)
                        .foregroundStyle(Color.climbMuted)
                        .textCase(.uppercase)

                    ForEach(next) { achievement in
                        AchievementProgressRow(achievement: achievement)
                    }
                }
            }
        }
    }

    private var monthlyLetterCard: some View {
        ClimbQuietPanel(padding: 22, cornerRadius: 22, accent: .climbWarm, isProminent: true) {
            SectionTitle(
                title: "Monthly Letter",
                subtitle: "A slower reflection on what your month is teaching you."
            )

            if let letter = viewModel.currentMonthLetter {
                VStack(alignment: .leading, spacing: 13) {
                    Text(letter.title)
                        .font(ClimbTypography.serif(25))
                        .foregroundStyle(Color.climbMist)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(letter.opening)
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(Color.climbWarm)
                        .lineSpacing(3)

                    Text(letter.body)
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        MonthlyLetterMetric(value: "\(letter.completedMissions)", label: "Done", tint: .climbSage)
                        MonthlyLetterMetric(value: "\(letter.failedMissions)", label: "Missed", tint: .climbRed)
                        MonthlyLetterMetric(
                            value: letter.ovrDelta >= 0 ? "+\(letter.ovrDelta)" : "\(letter.ovrDelta)",
                            label: "OVR",
                            tint: letter.ovrDelta >= 0 ? .climbSage : .climbGold
                        )
                    }

                    Text(letter.closingPrompt)
                        .font(ClimbTypography.serif(17))
                        .foregroundStyle(Color.climbMist.opacity(0.92))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Generate a letter from this month’s missions, misses, OVR movement, and journal effort.")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(3)
            }

            PrimaryActionButton(
                title: viewModel.currentMonthLetter == nil ? "Generate Letter" : "Refresh Letter",
                systemImage: isGeneratingLetter ? "hourglass" : "sparkles",
                isDisabled: isGeneratingLetter
            ) {
                isGeneratingLetter = true
                Task {
                    _ = await viewModel.generateMonthlyReflectionLetter()
                    await MainActor.run {
                        withAnimation(ClimbMotion.standard) {
                            isGeneratingLetter = false
                        }
                    }
                }
            }
        }
    }

    private var ovrRulesCard: some View {
        ClimbQuietPanel(cornerRadius: 22) {
            SectionTitle(title: "How OVR Is Earned", subtitle: "OVR starts at \(OVRScoring.baseline) and moves from real behavior.")
            ForEach(Array(OVRScoring.visibleRules.enumerated()), id: \.offset) { index, rule in
                OVRRuleRow(title: rule.0, points: rule.1, detail: rule.2)
                if index < OVRScoring.visibleRules.count - 1 {
                    Divider().overlay(Color.climbDivider)
                }
            }
        }
    }

    private var categoryCard: some View {
        ClimbQuietPanel(cornerRadius: 22) {
            SectionTitle(title: "Where You’re Building")
            ForEach(MissionCategory.allCases) { category in
                let completed = viewModel.missions.filter { $0.category == category && ($0.status == .completed || $0.status == .recovered) }.count
                HStack {
                    Label(category.rawValue, systemImage: category.symbol)
                        .font(ClimbTypography.sans(15, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(completed)")
                        .font(ClimbTypography.sans(16, weight: .semibold).monospacedDigit())
                        .foregroundStyle(completed > 0 ? Color.climbSage : Color.secondary)
                }
                if category != MissionCategory.allCases.last {
                    Divider().overlay(Color.climbDivider)
                }
            }
        }
    }

    private var completedCount: Int {
        viewModel.missions.filter { $0.status == .completed || $0.status == .recovered }.count
    }

    private var failedCount: Int {
        viewModel.failedMissionCount
    }

    private var latestDelta: Int {
        let sorted = viewModel.progress.sorted { $0.date > $1.date }
        guard let latest = sorted.first else { return 0 }
        guard let previous = sorted.dropFirst().first else { return latest.ovrScore - 50 }
        return latest.ovrScore - previous.ovrScore
    }
}

private struct MonthlyLetterMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(18, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label.uppercased())
                .font(ClimbTypography.sans(10, weight: .bold))
                .foregroundStyle(tint)
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.climbSurfaceRaised.opacity(0.68), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.climbHairline, lineWidth: 1)
        }
    }
}

private struct AchievementSummaryMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(20, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label.uppercased())
                .font(ClimbTypography.sans(10, weight: .bold))
                .tracking(0.75)
                .foregroundStyle(tint.opacity(0.88))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.climbSurfaceRaised.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 0.7)
        }
    }
}

private struct OVRRuleRow: View {
    let title: String
    let points: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(points)
                .font(ClimbTypography.sans(14, weight: .semibold).monospacedDigit())
                .foregroundStyle(points.hasPrefix("-") ? Color.climbRed : Color.climbSage)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}
