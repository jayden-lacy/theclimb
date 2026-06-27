import Charts
import SwiftUI

struct ProgressDashboardView: View {
    @ObservedObject var viewModel: AppViewModel

    private var orderedProgress: [ProgressSnapshot] {
        viewModel.progress.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScreenContainer(title: "Progress") {
            if let profile = viewModel.profile {
                progressHeader(profile)
                OVRScoreCard(score: profile.ovrScore, delta: latestDelta)
                ovrRulesCard
                statsCards(profile)
            }

            ovrChart
            reportCard
            categoryCard
        }
    }

    private func progressHeader(_ profile: UserProfile) -> some View {
        ClimbCard(padding: 22, cornerRadius: 26, isProminent: true) {
            Text("FOCUS REPORT")
                .font(ClimbTypography.sans(13, weight: .bold))
                .foregroundStyle(Color.climbGreen.opacity(0.86))
                .tracking(1.3)
                .textCase(.uppercase)
            Text("Proof you came back.")
                .font(ClimbTypography.sans(30, weight: .bold))
                .foregroundStyle(Color.climbMist)
            Text("\(profile.currentStreak) day streak · \(Int(viewModel.completionRate * 100))% completion · \(profile.mainStruggle.shortLabel) path")
                .font(ClimbTypography.sans(14, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
            ProgressBar(value: viewModel.completionRate, height: 6, tint: .climbSage)
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
        ClimbCard(padding: 20, cornerRadius: 24) {
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
        ClimbCard(cornerRadius: 22) {
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

    private var ovrRulesCard: some View {
        ClimbCard(cornerRadius: 22) {
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
        ClimbCard(cornerRadius: 22) {
            SectionTitle(title: "Where You’re Building")
            ForEach(MissionCategory.allCases) { category in
                let completed = viewModel.missions.filter { $0.category == category && ($0.status == .completed || $0.status == .recovered) }.count
                HStack {
                    Label(category.rawValue, systemImage: category.symbol)
                        .font(ClimbTypography.sans(15, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(completed)")
                        .font(ClimbTypography.sans(16, weight: .bold).monospacedDigit())
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

private struct OVRRuleRow: View {
    let title: String
    let points: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(points)
                .font(ClimbTypography.sans(14, weight: .bold).monospacedDigit())
                .foregroundStyle(points.hasPrefix("-") ? Color.climbRed : Color.climbSage)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClimbTypography.sans(15, weight: .bold))
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
