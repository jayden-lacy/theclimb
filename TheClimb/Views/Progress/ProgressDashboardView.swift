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
                statsCards(profile)
            }

            ovrChart
            reportCard
            categoryCard
        }
    }

    private func progressHeader(_ profile: UserProfile) -> some View {
        ClimbCard(padding: 24, cornerRadius: 32, isProminent: true) {
            Text("Growth analytics")
                .font(ClimbTypography.sans(13, weight: .bold))
                .foregroundStyle(Color.climbGreen)
                .tracking(1.3)
                .textCase(.uppercase)
            Text("Evidence of becoming.")
                .font(ClimbTypography.sans(32, weight: .bold))
                .foregroundStyle(Color.climbMist)
            Text("\(profile.currentStreak) day streak · \(Int(viewModel.completionRate * 100))% completion · \(profile.mainStruggle.shortLabel) path")
                .font(ClimbTypography.sans(14, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
            ProgressBar(value: viewModel.completionRate, height: 6, tint: .climbGreen)
        }
    }

    private func statsCards(_ profile: UserProfile) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(title: "Completed", value: "\(completedCount)", symbol: "checkmark.circle", tint: .climbGreen)
            MetricTile(title: "Failed", value: "\(failedCount)", symbol: "xmark.circle", tint: .climbRed)
            MetricTile(title: "Streak", value: "\(profile.currentStreak)", symbol: "flame", tint: .climbGold)
            MetricTile(title: "Longest", value: "\(profile.longestStreak)", symbol: "medal", tint: .climbBlue)
        }
    }

    private var ovrChart: some View {
        ClimbCard(padding: 22, cornerRadius: 32, isProminent: true) {
            SectionTitle(title: "Momentum", subtitle: "The line matters less than the return.")
            if orderedProgress.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Progress appears after your first mission.")
                        .font(ClimbTypography.sans(14))
                        .foregroundStyle(Color.climbTextSecondary)
                    ProgressBar(value: 0.5, height: 6, tint: .climbMuted)
                    Text("Baseline OVR starts at 50.")
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                }
            } else {
                Chart(orderedProgress) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.date),
                        y: .value("OVR", snapshot.ovrScore)
                    )
                    .foregroundStyle(Color.climbGreen)
                    .symbol(Circle())
                    AreaMark(
                        x: .value("Date", snapshot.date),
                        y: .value("OVR", snapshot.ovrScore)
                    )
                    .foregroundStyle(Color.climbGreen.opacity(0.12))
                }
                .frame(height: 210)
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
        ClimbCard(cornerRadius: 30) {
            SectionTitle(title: "Weekly Pulse")
            Text(viewModel.weeklyReport)
                .font(ClimbTypography.sans(15))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
            ProgressBar(value: viewModel.completionRate, height: 6, tint: .climbGreen)
            Text("\(Int(viewModel.completionRate * 100))% mission completion")
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
        }
    }

    private var categoryCard: some View {
        ClimbCard(cornerRadius: 30) {
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
                        .foregroundStyle(completed > 0 ? Color.climbGreen : Color.secondary)
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
        viewModel.missions.filter { $0.status == .failed }.count
    }

    private var latestDelta: Int {
        let sorted = viewModel.progress.sorted { $0.date > $1.date }
        guard let latest = sorted.first else { return 0 }
        guard let previous = sorted.dropFirst().first else { return latest.ovrScore - 50 }
        return latest.ovrScore - previous.ovrScore
    }
}
