import SwiftUI

struct GrowView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var prayerNote = ""

    var body: some View {
        ScreenContainer(title: "Grow") {
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
            habitsSection
            challengesSection
            prayerSection
        }
    }

    private func devotionalCard(_ devotional: Devotional) -> some View {
        ClimbCard(padding: 24, cornerRadius: 32, isProminent: true) {
            Text("TODAY’S DEVOTIONAL")
                .font(ClimbTypography.sans(12, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.climbGreen)
            Text(devotional.title)
                .font(ClimbTypography.serif(36))
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
                    .padding(.vertical, 4)
            }
            Text(devotional.explanation)
                .font(ClimbTypography.sans(15))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                Text("Reflection")
                    .font(ClimbTypography.sans(13, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.climbMuted)
                Text(devotional.reflectionQuestion)
                    .font(ClimbTypography.serif(24))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Action")
                    .font(ClimbTypography.sans(13, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.climbMuted)
                Text(devotional.practicalAction)
                    .font(ClimbTypography.sans(15))
                    .foregroundStyle(Color.climbTextSecondary)
            }
        }
    }

    private var growthPath: some View {
        ClimbCard(padding: 22, cornerRadius: 30) {
            SectionTitle(
                title: "Obedience Loop",
                subtitle: viewModel.profile?.mainStruggle.rawValue ?? "Personal"
            )
            HStack(spacing: 10) {
                PathStep(number: "1", title: "Devotional")
                PathStep(number: "2", title: "Mission")
                PathStep(number: "3", title: "Reflection")
                PathStep(number: "4", title: "Accountability")
            }
        }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Habits")
            if viewModel.habits.isEmpty {
                EmptyState(title: "No habits yet", detail: "Habits are generated from your growth path.", systemImage: "checklist")
            } else {
                ForEach(viewModel.habits) { habit in
                    HStack(spacing: 12) {
                        Image(systemName: habit.isEnabled ? "checkmark.circle.fill" : "circle")
                            .font(ClimbTypography.sans(20, weight: .semibold))
                            .foregroundStyle(habit.isEnabled ? Color.climbGreen : Color.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(habit.title)
                                .font(ClimbTypography.sans(16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(habit.cadence)
                                .font(ClimbTypography.sans(12, weight: .medium))
                                .foregroundStyle(Color.climbTextSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: habitBinding(habit))
                            .labelsHidden()
                            .tint(.climbGreen)
                    }
                    .padding(17)
                    .background(Color.climbSurfaceGlass, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
                }
            }
        }
    }

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Challenges")
            if viewModel.challenges.isEmpty {
                EmptyState(title: "No challenges yet", detail: "Challenges unlock after your plan is created.", systemImage: "flag.checkered")
            } else {
                ForEach(viewModel.challenges) { challenge in
                    ClimbCard(cornerRadius: 28) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: challenge.category.symbol)
                                .font(ClimbTypography.sans(18, weight: .semibold))
                                .foregroundStyle(Color.climbMuted)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(challenge.title)
                                    .font(ClimbTypography.sans(17, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(challenge.detail)
                                    .font(ClimbTypography.sans(14))
                                    .foregroundStyle(Color.climbTextSecondary)
                                StatusBadge(text: "\(challenge.daysRemaining) days left", color: .climbGold)
                            }
                        }
                    }
                }
            }
        }
    }

    private var prayerSection: some View {
        ClimbCard(padding: 22, cornerRadius: 30) {
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

    private func habitBinding(_ habit: GrowthHabit) -> Binding<Bool> {
        Binding(
            get: { viewModel.habits.first(where: { $0.id == habit.id })?.isEnabled ?? false },
            set: { _ in
                Task {
                    await viewModel.toggleHabit(habit)
                }
            }
        )
    }
}

private struct PathStep: View {
    let number: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Text(number)
                .font(ClimbTypography.sans(15, weight: .bold))
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
