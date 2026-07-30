import Charts
import SwiftUI
#if canImport(DeviceActivity) && os(iOS)
import DeviceActivity
#endif
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

#if canImport(DeviceActivity) && os(iOS)
private extension DeviceActivityReport.Context {
    static let theClimbAttentionSummary = Self(
        "the-climb.attention-summary"
    )
}
#endif

private enum AttentionReportRange: Int, CaseIterable, Identifiable {
    case today = 1
    case sevenDays = 7
    case fourWeeks = 28
    case threeMonths = 90

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7D"
        case .fourWeeks: "4W"
        case .threeMonths: "3M"
        }
    }
}

struct ProgressDashboardView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isGeneratingLetter = false
    @State private var focusDomain = FocusSessionDomainEnvelope()
    @State private var attentionRange = AttentionReportRange.sevenDays
    @State private var isShowingStewardshipDetails = false

    private var orderedProgress: [ProgressSnapshot] {
        viewModel.progress.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScreenContainer(title: "Progress") {
            if let profile = viewModel.profile {
                progressHeader(profile)
                OVRScoreCard(score: profile.ovrScore, delta: latestDelta)
                stewardshipCard
                attentionUsageReport
                achievementCard
                ovrRulesCard
                statsCards(profile)
            }

            ovrChart
            reportCard
            monthlyLetterCard
            categoryCard
        }
        .task {
            focusDomain = (try? FocusSessionRuntimeService().loadState())
                ?? FocusSessionDomainEnvelope()
        }
        .sheet(isPresented: $isShowingStewardshipDetails) {
            StewardshipScoreDetailView(result: currentStewardshipScore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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

    @ViewBuilder
    private var attentionUsageReport: some View {
#if canImport(DeviceActivity) && os(iOS)
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: "Screen Time",
                subtitle: "Apple provides this report privately on your device."
            )

            Picker("Report range", selection: $attentionRange) {
                ForEach(AttentionReportRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Changes the date range of the Screen Time report")

            DeviceActivityReport(
                .theClimbAttentionSummary,
                filter: attentionActivityFilter
            )
            .id(attentionRange)
            .frame(minHeight: 470)
            .background(
                Color.climbSurfaceRaised,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.climbHairline, lineWidth: 0.7)
            )
        }
#endif
    }

#if canImport(DeviceActivity) && os(iOS)
    private var attentionActivityFilter: DeviceActivityFilter {
        let end = Date()
        let start: Date
        if attentionRange == .today {
            start = Calendar.current.startOfDay(for: end)
        } else {
            start = Calendar.current.date(
                byAdding: .day,
                value: -attentionRange.rawValue,
                to: end
            ) ?? end.addingTimeInterval(
                -TimeInterval(attentionRange.rawValue) * 24 * 60 * 60
            )
        }
#if canImport(FamilyControls)
        let selection = ScreenTimeActivitySelectionStore.loadSelection()
        return DeviceActivityFilter(
            segment: .daily(
                during: DateInterval(start: start, end: end)
            ),
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens
        )
#else
        return DeviceActivityFilter(
            segment: .daily(
                during: DateInterval(start: start, end: end)
            )
        )
#endif
    }
#endif

    private var stewardshipCard: some View {
        let result = currentStewardshipScore

        return ClimbQuietPanel(
            padding: 20,
            cornerRadius: 22,
            accent: .climbSage,
            isProminent: true
        ) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("STEWARDSHIP")
                        .font(ClimbTypography.sans(11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.climbMuted)
                    Text(result.score.map(String.init) ?? "—")
                        .font(
                            ClimbTypography.sans(42, weight: .semibold)
                                .monospacedDigit()
                        )
                        .foregroundStyle(Color.climbMist)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(
                        result.state == .scored
                            ? "Behavior you can verify"
                            : "More real evidence needed"
                    )
                    .font(ClimbTypography.sans(16, weight: .semibold))
                    .foregroundStyle(Color.climbMist)

                    Text(
                        result.state == .scored
                            ? "Built from protected focus, completed missions, and reflections this week."
                            : "Complete at least three actions across two measured areas to calculate a score."
                    )
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(3)

                    Text("This measures stewardship habits, never spiritual worth.")
                        .font(ClimbTypography.sans(11, weight: .medium))
                        .foregroundStyle(Color.climbMuted)

                    Button {
                        isShowingStewardshipDetails = true
                    } label: {
                        Label("How this score works", systemImage: "info.circle")
                            .font(ClimbTypography.sans(13, weight: .semibold))
                            .foregroundStyle(Color.climbSage)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        "Shows the evidence and weighting behind your stewardship score"
                    )
                }
            }
        }
    }

    private var currentStewardshipScore: StewardshipScoreResult {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let weekEnd = calendar.date(
            byAdding: .day,
            value: 7,
            to: weekStart
        ) ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        let interval = DateInterval(start: weekStart, end: weekEnd)

        let missionEvidence = viewModel.missions.compactMap {
            missionCompletionEvidence($0)
        }
        let reflectionEvidence = viewModel.journalEntries.map {
            StewardshipCompletionRecord(
                id: "reflection:\($0.id)",
                kind: .reflection,
                itemID: $0.id,
                scheduledAt: $0.date,
                completedAt: $0.date,
                outcome: .completed
            )
        }
        let evidence = StewardshipScoreEvidence(
            protectedFocusRecords: focusDomain.history.records,
            rhythmAdherenceRecords: [],
            boundaryAdherenceRecords: [],
            completionRecords: missionEvidence + reflectionEvidence
        )
        return StewardshipScoreEngine().score(
            evidence: evidence,
            within: interval,
            evaluatedAt: now
        )
    }

    private func missionCompletionEvidence(
        _ mission: Mission
    ) -> StewardshipCompletionRecord? {
        let outcome: StewardshipCompletionOutcome
        switch mission.status {
        case .completed, .recovered:
            outcome = .completed
        case .failed:
            outcome = .missed
        case .pending, .active:
            return nil
        }
        return StewardshipCompletionRecord(
            id: "mission:\(mission.id)",
            kind: .mission,
            itemID: mission.id,
            scheduledAt: mission.date,
            completedAt: outcome == .completed ? mission.date : nil,
            outcome: outcome
        )
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

private struct StewardshipScoreDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let result: StewardshipScoreResult

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.score.map(String.init) ?? "Not scored")
                            .font(
                                ClimbTypography.sans(38, weight: .semibold)
                                    .monospacedDigit()
                            )
                            .foregroundStyle(Color.climbMist)
                        Text(scoreSummary)
                            .font(ClimbTypography.sans(14, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(3)
                    }

                    VStack(spacing: 0) {
                        ForEach(
                            Array(result.factors.enumerated()),
                            id: \.element.factor
                        ) { index, factor in
                            StewardshipFactorRow(breakdown: factor)
                            if index < result.factors.count - 1 {
                                Divider().overlay(Color.climbDivider)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(
                        Color.climbSurfaceRaised,
                        in: RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 20,
                            style: .continuous
                        )
                        .stroke(Color.climbHairline, lineWidth: 0.7)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "A behavioral measure",
                            systemImage: "checkmark.shield"
                        )
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(Color.climbMist)

                        Text(
                            "Only measured factors count. Missing Screen Time data is excluded instead of guessed. Available weights are normalized to 100, and at least three records across two factors are required."
                        )
                        .font(ClimbTypography.sans(13, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)

                        Text(
                            "This score reflects consistency with your chosen commitments. It never measures faith, salvation, or spiritual worth."
                        )
                        .font(ClimbTypography.serif(16))
                        .foregroundStyle(Color.climbMist.opacity(0.92))
                        .lineSpacing(4)
                    }
                }
                .padding(20)
            }
            .background(Color.climbBackground.ignoresSafeArea())
            .navigationTitle("Stewardship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var scoreSummary: String {
        if result.state == .scored {
            return "\(result.evidenceCount) verified actions across \(result.measuredFactorCount) measured areas."
        }
        return "Complete more verified actions to calculate a fair score."
    }
}

private struct StewardshipFactorRow: View {
    let breakdown: StewardshipScoreFactorBreakdown

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: breakdown.factor.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    breakdown.availability == .measured
                        ? Color.climbSage
                        : Color.climbMuted
                )
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(breakdown.factor.displayName)
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                Text(factorDetail)
                    .font(ClimbTypography.sans(11, weight: .medium))
                    .foregroundStyle(Color.climbMuted)
            }

            Spacer(minLength: 12)

            Text(factorValue)
                .font(
                    ClimbTypography.sans(15, weight: .semibold)
                        .monospacedDigit()
                )
                .foregroundStyle(
                    breakdown.availability == .measured
                        ? Color.climbMist
                        : Color.climbMuted
                )
        }
        .padding(.vertical, 13)
    }

    private var factorDetail: String {
        guard breakdown.availability == .measured else {
            return "Not measured"
        }
        return "\(breakdown.evidenceCount) records · \(Int(breakdown.effectiveWeight.rounded()))% of score"
    }

    private var factorValue: String {
        guard let score = breakdown.factorScore else { return "—" }
        return "\(Int(score.rounded()))"
    }
}

private extension StewardshipScoreFactor {
    var displayName: String {
        switch self {
        case .protectedFocus: "Protected focus"
        case .rhythmAdherence: "Rhythms"
        case .boundaryAdherence: "Boundaries"
        case .missionCompletion: "Missions"
        case .habitCompletion: "Habits"
        case .reflectionCompletion: "Reflections"
        }
    }

    var symbol: String {
        switch self {
        case .protectedFocus: "hourglass"
        case .rhythmAdherence: "repeat"
        case .boundaryAdherence: "gauge.with.dots.needle.50percent"
        case .missionCompletion: "scope"
        case .habitCompletion: "checkmark.circle"
        case .reflectionCompletion: "text.book.closed"
        }
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
