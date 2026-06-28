import SwiftUI

struct GrowView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var prayerNote = ""
    @State private var selectedHabit: SelectedHabit?
    @State private var selectedSection: GrowSection = .habits
    @Namespace private var growNamespace

    var body: some View {
        ScreenContainer(title: "Grow") {
            growHeader
            GrowSectionSwitcher(selection: $selectedSection, namespace: growNamespace)

            activeSection
                .id(selectedSection)
                .transition(.climbScreen)
        }
        .sheet(item: $selectedHabit) { selection in
            HabitDetailSheet(viewModel: viewModel, habitID: selection.id)
                .presentationDetents([.medium, .large])
        }
        .animation(ClimbMotion.focus, value: selectedSection)
    }

    private var growHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("GROWTH PATH")
                .font(ClimbTypography.sans(11, weight: .semibold))
                .tracking(1.7)
                .foregroundStyle(Color.climbGreen.opacity(0.86))
            Text("Practice, then repeat.")
                .font(ClimbTypography.sans(30, weight: .semibold))
                .foregroundStyle(Color.climbMist)
                .fixedSize(horizontal: false, vertical: true)
            Text("One practice at a time. Small enough to keep, serious enough to matter.")
                .font(ClimbTypography.sans(14, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .climbEntrance()
    }

    @ViewBuilder
    private var activeSection: some View {
        switch selectedSection {
        case .habits:
            habitsSection
        case .word:
            VStack(spacing: 14) {
                if let devotional = viewModel.todayDevotional {
                    devotionalCard(devotional)
                } else {
                    EmptyState(
                        title: "Devotional preparing",
                        detail: "Your next devotional appears once today’s plan syncs.",
                        systemImage: "book.closed"
                    )
                }
                growthPath
            }
        case .prayer:
            prayerSection
        }
    }

    private func devotionalCard(_ devotional: Devotional) -> some View {
        ClimbCard(padding: 22, cornerRadius: 26, isProminent: true) {
            Text("DAILY WORD")
                .font(ClimbTypography.sans(12, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.climbWarm.opacity(0.76))
            Text(devotional.title)
                .font(ClimbTypography.serif(32))
                .foregroundStyle(Color.climbMist)
                .fixedSize(horizontal: false, vertical: true)
            Text(devotional.bibleVerse)
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
            if let verseText = devotional.verseText, !verseText.isEmpty {
                Text("“\(verseText)”")
                    .font(ClimbTypography.serif(24))
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

            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                Text("Reflection")
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.climbMuted)
                Text(devotional.reflectionQuestion)
                    .font(ClimbTypography.serif(24))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Action")
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.climbMuted)
                Text(devotional.practicalAction)
                    .font(ClimbTypography.sans(15))
                    .foregroundStyle(Color.climbTextSecondary)
            }
        }
    }

    private var growthPath: some View {
        let path = viewModel.profile.map { GrowthPathPersonalization.resolve(for: $0) }
        return ClimbCard(padding: 20, cornerRadius: 24) {
            SectionTitle(
                title: "Daily System",
                subtitle: path?.headline ?? "Personal"
            )
            if let path {
                Text(path.planSummary)
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                PathStep(number: "1", title: "Word")
                PathStep(number: "2", title: "Mission")
                PathStep(number: "3", title: "Reflect")
                PathStep(number: "4", title: "Partner")
            }
        }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HabitSummaryCard(
                completed: viewModel.todayHabitCompletionCount,
                total: viewModel.activeHabits.count,
                progress: viewModel.todayHabitCompletionRate
            )

            if viewModel.habits.isEmpty {
                EmptyState(title: "No habits yet", detail: "Habits are generated from your growth path.", systemImage: "checklist")
            } else {
                ForEach(viewModel.habits) { habit in
                    HabitTrackerCard(
                        habit: habit,
                        onToggleToday: {
                            Task {
                                await viewModel.toggleHabitCompletion(habit.id)
                            }
                        },
                        onToggleEnabled: {
                            Task {
                                await viewModel.setHabitEnabled(habit.id, isEnabled: !habit.isEnabled)
                            }
                        },
                        onOpenDetails: {
                            selectedHabit = SelectedHabit(id: habit.id)
                        }
                    )
                }
            }
        }
    }

    private var prayerSection: some View {
        ClimbCard(padding: 22, cornerRadius: 24) {
            Text("Guided Prayer")
                .font(ClimbTypography.serif(30))
                .foregroundStyle(.white)
            TextField("Write a short prayer or next step", text: $prayerNote, axis: .vertical)
                .lineLimit(3...6)
                .formFieldStyle()
            HStack {
                Spacer()
                Button {
                    prayerNote = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(ScaleButtonStyle())
                .foregroundStyle(Color.climbMuted)
            }
        }
    }

}

private enum GrowSection: String, CaseIterable, Identifiable {
    case habits = "Habits"
    case word = "Word"
    case prayer = "Prayer"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .habits:
            "checkmark.seal"
        case .word:
            "book.closed"
        case .prayer:
            "hands.sparkles"
        }
    }
}

private struct GrowSectionSwitcher: View {
    @Binding var selection: GrowSection
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GrowSection.allCases) { section in
                Button {
                    HapticFeedback.selection()
                    withAnimation(ClimbMotion.focus) {
                        selection = section
                    }
                } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .foregroundStyle(selection == section ? Color.climbMist : Color.climbTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background {
                            if selection == section {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(Color.climbSurfaceRaised)
                                    .matchedGeometryEffect(id: "grow-section", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.climbBackgroundLifted.opacity(0.62), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
        )
        .climbEntrance(index: 1)
    }
}

private struct SelectedHabit: Identifiable {
    let id: String
}

private struct HabitSummaryCard: View {
    let completed: Int
    let total: Int
    let progress: Double

    var body: some View {
        ClimbCard(padding: 20, cornerRadius: 24, isProminent: true) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("HABIT CHECK-IN")
                        .font(ClimbTypography.sans(11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Color.climbGreen.opacity(0.86))
                    Text(total == 0 ? "No active habits" : "\(completed) of \(total) done today")
                        .font(ClimbTypography.sans(24, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                        .contentTransition(.numericText())
                    Text(total == 0 ? "Turn on a habit to start tracking daily rhythm." : summaryLine)
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                }

                Spacer(minLength: 0)

                ScoreRing(value: progress, text: "\(Int((progress * 100).rounded()))", size: 62)
            }

            ProgressBar(value: progress, height: 5, tint: .climbGreen)
        }
    }

    private var summaryLine: String {
        if completed == total {
            return "All daily habits are protected. Keep the rhythm small enough to repeat."
        }
        if completed == 0 {
            return "Start with one check-in. The first honest mark creates momentum."
        }
        return "Good start. Finish the remaining habits before the day gets noisy."
    }
}

private struct HabitTrackerCard: View {
    let habit: GrowthHabit
    let onToggleToday: () -> Void
    let onToggleEnabled: () -> Void
    let onOpenDetails: () -> Void

    private var isDoneToday: Bool {
        habit.isCompleted()
    }

    private var weeklyCount: Int {
        habit.completionsInLastSevenDays()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Button(action: onToggleToday) {
                Image(systemName: isDoneToday ? "checkmark.circle.fill" : "circle")
                    .font(ClimbTypography.sans(25, weight: .semibold))
                    .foregroundStyle(isDoneToday ? Color.climbGreen : Color.climbMuted)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!habit.isEnabled)

            Button(action: onOpenDetails) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(habit.title)
                            .font(ClimbTypography.sans(17, weight: .semibold))
                            .foregroundStyle(habit.isEnabled ? Color.climbMist : Color.climbMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        if !habit.isEnabled {
                            Text("PAUSED")
                                .font(ClimbTypography.sans(9, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Color.climbGold)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(habit.cadence)
                        Text("•")
                        Text("\(habit.streak()) day streak")
                        Text("•")
                        Text("\(weeklyCount)/7")
                    }
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                    HabitMiniWeekDots(habit: habit)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onToggleEnabled) {
                Image(systemName: habit.isEnabled ? "pause" : "play.fill")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(habit.isEnabled ? Color.climbMuted : Color.climbGreen)
                    .frame(width: 34, height: 34)
                    .background(Color.climbBackgroundLifted.opacity(0.74), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 0.7))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(14)
        .background(Color.climbSurfaceRaised.opacity(habit.isEnabled ? 0.58 : 0.32), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(isDoneToday ? Color.climbGreen.opacity(0.20) : Color.white.opacity(0.058), lineWidth: 0.75)
        )
        .opacity(habit.isEnabled ? 1 : 0.72)
        .animation(ClimbMotion.quick, value: isDoneToday)
        .animation(ClimbMotion.quick, value: habit.isEnabled)
    }
}

private struct HabitMiniWeekDots: View {
    let habit: GrowthHabit

    private var days: [Date] {
        let today = Date().startOfDay
        return Array((0..<7)
            .compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
            .reversed())
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days, id: \.self) { day in
                Capsule()
                    .fill(habit.isCompleted(on: day) ? Color.climbGreen : Color.climbDivider.opacity(0.80))
                    .frame(width: Calendar.current.isDateInToday(day) ? 18 : 10, height: 5)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct HabitWeekDots: View {
    let habit: GrowthHabit

    private var days: [Date] {
        let today = Date().startOfDay
        return Array((0..<7)
            .compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
            .reversed())
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(days, id: \.self) { day in
                VStack(spacing: 5) {
                    Circle()
                        .fill(habit.isCompleted(on: day) ? Color.climbGreen : Color.climbDivider.opacity(0.85))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(habit.isCompleted(on: day) ? Color.climbGreen.opacity(0.35) : Color.white.opacity(0.04), lineWidth: 1)
                        )
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(ClimbTypography.sans(9, weight: .semibold))
                        .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.climbMist : Color.climbMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Color.climbBackgroundLifted.opacity(0.52), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct HabitMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.climbBackgroundLifted.opacity(0.48), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct HabitDetailSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let habitID: String

    private var habit: GrowthHabit? {
        viewModel.habits.first { $0.id == habitID }
    }

    var body: some View {
        ZStack {
            ClimbScreenBackground()

            if let habit {
                VStack(alignment: .leading, spacing: 18) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 42, height: 4)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(habit.isCompleted() ? "Completed today" : "Habit tracker")
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(habit.isCompleted() ? Color.climbGreen : Color.climbMuted)
                            .textCase(.uppercase)
                        Text(habit.title)
                            .font(ClimbTypography.sans(31, weight: .semibold))
                            .foregroundStyle(Color.climbMist)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(habit.cadence)
                            .font(ClimbTypography.sans(14, weight: .semibold))
                            .foregroundStyle(Color.climbTextSecondary)
                    }

                    HabitWeekDots(habit: habit)

                    HStack(spacing: 10) {
                        HabitMetric(value: "\(habit.streak())", label: "current")
                        HabitMetric(value: "\(habit.completionsInLastSevenDays())/7", label: "week")
                        HabitMetric(value: "\(habit.bestStreak())", label: "best")
                    }

                    Text(habit.isEnabled ? encouragement(for: habit) : "This habit is paused. Resume it when you want it back in your daily rhythm.")
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    PrimaryActionButton(
                        title: habit.isCompleted() ? "Undo Today" : "Mark Done Today",
                        systemImage: habit.isCompleted() ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill",
                        isDisabled: !habit.isEnabled
                    ) {
                        Task {
                            await viewModel.toggleHabitCompletion(habit.id)
                        }
                    }

                    SecondaryActionButton(title: habit.isEnabled ? "Pause Habit" : "Resume Habit", systemImage: habit.isEnabled ? "pause.circle" : "play.circle") {
                        Task {
                            await viewModel.setHabitEnabled(habit.id, isEnabled: !habit.isEnabled)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            } else {
                EmptyState(title: "Habit not found", detail: "This habit may have been removed from your plan.", systemImage: "checklist")
                    .padding(20)
            }
        }
    }

    private func encouragement(for habit: GrowthHabit) -> String {
        if habit.isCompleted() {
            return "Logged. The goal is not a perfect routine; it is a repeated return."
        }
        if habit.streak() > 0 {
            return "You have a \(habit.streak()) day rhythm. Keep the promise small and finish it today."
        }
        return "Start with the smallest honest version. One check-in is enough to begin the chain."
    }
}

private struct PathStep: View {
    let number: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Text(number)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: Circle())
                .background(Color.climbSurfaceGlass, in: Circle())
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.climbDivider, lineWidth: 1))
            Text(title)
                .font(ClimbTypography.sans(11, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
