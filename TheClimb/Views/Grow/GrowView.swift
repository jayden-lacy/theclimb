import Combine
import SwiftUI
import WidgetKit

struct GrowView: View {
    private static let sharedPrayerDefaults = UserDefaults(suiteName: LocalAppRepository.appGroupID)

    @ObservedObject var viewModel: AppViewModel
    @State private var prayerNote = ""
    @State private var selectedHabit: SelectedHabit?
    @State private var selectedVersePack: VersePack?
    @State private var selectedMemoryVerse: MemorizedVerse?
    @State private var selectedSection: GrowSection = .habits
    @State private var selectedPrayerMinutes = 5
    @State private var prayerRemainingSeconds = 5 * 60
    @State private var isPrayerRunning = false
    @State private var isStartingProtectedFocus = false
    @State private var focusErrorMessage: String?
    @State private var showFocusSetup = false
    @AppStorage("climb.prayer.sessionsCompleted", store: GrowView.sharedPrayerDefaults) private var prayerSessionsCompleted = 0
    @AppStorage("climb.prayer.minutesCompleted", store: GrowView.sharedPrayerDefaults) private var prayerMinutesCompleted = 0
    @AppStorage("climb.prayer.lastCompletedAt", store: GrowView.sharedPrayerDefaults) private var prayerLastCompletedAt = 0.0
    @AppStorage("climb.dailyWordFeedbackDate") private var dailyWordFeedbackDate = ""
    @AppStorage("climb.dailyWordFeedbackValue") private var dailyWordFeedbackValue = ""
    @Namespace private var growNamespace
    private let prayerTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let focusRuntime = FocusSessionRuntimeService()

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
        .sheet(item: $selectedVersePack) { pack in
            VersePackDetailSheet(pack: pack, viewModel: viewModel)
                .presentationDetents([.large])
        }
        .sheet(item: $selectedMemoryVerse) { verse in
            VerseMemoryReviewSheet(viewModel: viewModel, verse: verse)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFocusSetup) {
            FocusControlCenterView(viewModel: viewModel)
        }
        .alert(
            "Focus protection needs setup",
            isPresented: Binding(
                get: { focusErrorMessage != nil },
                set: { if !$0 { focusErrorMessage = nil } }
            )
        ) {
            Button("Open Focus Setup") {
                showFocusSetup = true
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text(focusErrorMessage ?? "")
        }
        .animation(ClimbMotion.focus, value: selectedSection)
        .onChange(of: selectedPrayerMinutes) { _, minutes in
            guard !isPrayerRunning else { return }
            prayerRemainingSeconds = minutes * 60
            prayerDefaults.set(minutes, forKey: PrayerStorageKey.selectedMinutes)
        }
        .onReceive(prayerTimer) { _ in
            tickPrayerTimer()
        }
        .onAppear {
            loadSharedPrayerTimerState()
        }
    }

    private var growHeader: some View {
        ClimbPageHeader(
            eyebrow: "Growth path",
            title: "Practice, then repeat",
            subtitle: "One practice at a time. Small enough to keep, serious enough to matter."
        )
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
                verseMemorySection
                growthPath
                versePackLibrary
            }
        case .prayer:
            prayerSection
        }
    }

    private func devotionalCard(_ devotional: Devotional) -> some View {
        ClimbQuietPanel(padding: 22, cornerRadius: 24, accent: .climbWarm, isProminent: true) {
            Text("DAILY WORD")
                .font(ClimbTypography.sans(12, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.climbTextSecondary)
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

                Button {
                    Task {
                        await viewModel.memorizeVerse(
                            reference: devotional.bibleVerse,
                            text: verseText,
                            sourceTitle: devotional.title,
                            struggle: viewModel.profile?.mainStruggle
                        )
                    }
                } label: {
                    Label(
                        viewModel.isVerseMemorized(reference: devotional.bibleVerse) ? "Saved to memory" : "Memorize this verse",
                        systemImage: viewModel.isVerseMemorized(reference: devotional.bibleVerse) ? "checkmark.seal.fill" : "plus.circle"
                    )
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .foregroundStyle(viewModel.isVerseMemorized(reference: devotional.bibleVerse) ? Color.climbGreen : Color.climbMist)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.climbBackgroundLifted.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(viewModel.isVerseMemorized(reference: devotional.bibleVerse) ? Color.climbGreen.opacity(0.28) : Color.white.opacity(0.07), lineWidth: 0.7)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
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

            Divider().overlay(Color.white.opacity(0.08))

            PrimaryActionButton(
                title: isStartingProtectedFocus
                    ? "Starting protection"
                    : "Protect 15 minutes",
                systemImage: "shield.lefthalf.filled",
                tint: .climbGreen,
                isDisabled: isStartingProtectedFocus
            ) {
                startProtectedFocus(
                    purpose: .bibleStudy,
                    minutes: 15,
                    beginPrayerTimer: false
                )
            }

            DailyWordFeedbackRow(
                selected: dailyWordFeedback(for: devotional),
                onSelect: { option in
                    submitDailyWordFeedback(option, for: devotional)
                }
            )
        }
    }

    private var verseMemorySection: some View {
        let activeVerses = viewModel.activeVerseMemory
        let dueVerses = viewModel.dueVerseMemory
        let averageMastery = activeVerses.isEmpty
            ? 0.0
            : activeVerses.reduce(0.0) { $0 + $1.mastery } / Double(activeVerses.count)

        return ClimbQuietPanel(padding: 20, cornerRadius: 22, isProminent: true) {
            HStack(alignment: .top, spacing: 14) {
                SectionTitle(
                    title: "Verse Memory",
                    subtitle: activeVerses.isEmpty
                        ? "Save one verse from today or a pack, then review it before the day gets loud."
                        : "A quiet review rhythm for scripture you want to carry under pressure."
                )

                Spacer(minLength: 0)

                ScoreRing(
                    value: averageMastery,
                    text: "\(Int((averageMastery * 100).rounded()))",
                    size: 58,
                    tint: .climbGreen
                )
            }

            HStack(spacing: 10) {
                MemoryMetric(value: "\(activeVerses.count)", label: "saved")
                MemoryMetric(value: "\(dueVerses.count)", label: "due")
                MemoryMetric(value: activeVerses.first?.nextReviewLabel ?? "None", label: "next")
            }

            if let dueVerse = dueVerses.first ?? activeVerses.first {
                Button {
                    HapticFeedback.selection()
                    selectedMemoryVerse = dueVerse
                } label: {
                    VerseMemoryRow(verse: dueVerse, isPrimary: dueVerse.isDue)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start with one line.")
                        .font(ClimbTypography.serif(24))
                        .foregroundStyle(Color.climbMist)
                    Text("Open a verse pack below and save the verse you need most this week.")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineSpacing(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.climbBackgroundLifted.opacity(0.50), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(Color.white.opacity(0.065), lineWidth: 0.7)
                )
            }

            if activeVerses.count > 1 {
                VStack(spacing: 8) {
                    ForEach(activeVerses.dropFirst().prefix(2)) { verse in
                        Button {
                            HapticFeedback.selection()
                            selectedMemoryVerse = verse
                        } label: {
                            VerseMemoryRow(verse: verse, isPrimary: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var growthPath: some View {
        let path = viewModel.profile.map { GrowthPathPersonalization.resolve(for: $0) }
        return ClimbQuietPanel(padding: 20, cornerRadius: 22) {
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

    private var versePackLibrary: some View {
        let packs = VersePack.recommended(for: viewModel.profile?.mainStruggle)
        return ClimbQuietPanel(padding: 20, cornerRadius: 22) {
            SectionTitle(
                title: "Verse Packs",
                subtitle: "Practice scripture for the battle you are training."
            )

            VStack(spacing: 10) {
                ForEach(packs) { pack in
                    Button {
                        HapticFeedback.selection()
                        AppAnalytics.record(.versePackOpened, properties: ["pack": pack.id])
                        selectedVersePack = pack
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pack.symbol)
                                .font(ClimbTypography.sans(16, weight: .semibold))
                                .foregroundStyle(Color.climbGreen)
                                .frame(width: 36, height: 36)
                                .background(Color.climbGreen.opacity(0.11), in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(pack.title)
                                    .font(ClimbTypography.sans(16, weight: .semibold))
                                    .foregroundStyle(Color.climbMist)
                                Text(pack.subtitle)
                                    .font(ClimbTypography.sans(12, weight: .semibold))
                                    .foregroundStyle(Color.climbTextSecondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)

                            Text("\(pack.verses.count)")
                                .font(ClimbTypography.sans(12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.climbMuted)
                                .frame(width: 30, height: 30)
                                .background(Color.climbBackgroundLifted.opacity(0.72), in: Circle())
                        }
                        .padding(12)
                        .background(Color.climbBackgroundLifted.opacity(0.46), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
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
        VStack(alignment: .leading, spacing: 14) {
            ClimbQuietPanel(padding: 22, cornerRadius: 24, isProminent: true) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRAYER TIMER")
                            .font(ClimbTypography.sans(11, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(Color.climbTextSecondary)
                        Text(prayerPhaseTitle)
                            .font(ClimbTypography.serif(34))
                            .foregroundStyle(Color.climbMist)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(prayerPhaseSubtitle)
                            .font(ClimbTypography.sans(14, weight: .semibold))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    PrayerTimerRing(
                        progress: prayerProgress,
                        remainingSeconds: prayerRemainingSeconds,
                        isRunning: isPrayerRunning
                    )
                }

                PrayerDurationPicker(
                    selectedMinutes: $selectedPrayerMinutes,
                    isDisabled: isPrayerRunning
                )

                HStack(spacing: 10) {
                    PrimaryActionButton(
                        title: isPrayerRunning ? "Pause" : "Begin Prayer",
                        systemImage: isPrayerRunning ? "pause.fill" : "play.fill"
                    ) {
                        togglePrayerTimer()
                    }

                    SecondaryActionButton(
                        title: "Reset",
                        systemImage: "arrow.counterclockwise"
                    ) {
                        resetPrayerTimer()
                    }
                }

                if !isPrayerRunning {
                    SecondaryActionButton(
                        title: isStartingProtectedFocus
                            ? "Starting protection"
                            : "Protect and Begin",
                        systemImage: "shield.lefthalf.filled"
                    ) {
                        startProtectedFocus(
                            purpose: .prayer,
                            minutes: selectedPrayerMinutes,
                            beginPrayerTimer: true
                        )
                    }
                    .disabled(isStartingProtectedFocus)
                    .opacity(isStartingProtectedFocus ? 0.55 : 1)
                }

                if isPrayerRunning || prayerRemainingSeconds < selectedPrayerMinutes * 60 {
                    SecondaryActionButton(title: "Finish Prayer", systemImage: "checkmark.circle") {
                        completePrayerSession()
                    }
                }
            }

            ClimbQuietPanel(padding: 20, cornerRadius: 22) {
                SectionTitle(title: "Prayer note", subtitle: "Name what you are bringing to God.")
                TextField("Write a short prayer or next step", text: $prayerNote, axis: .vertical)
                    .lineLimit(3...6)
                    .formFieldStyle()
                HStack(spacing: 10) {
                    PrayerMetric(value: "\(prayerSessionsCompleted)", label: "sessions")
                    PrayerMetric(value: "\(prayerMinutesCompleted)", label: "minutes")
                }
                HStack {
                    Spacer()
                    Button {
                        HapticFeedback.impact(.light)
                        prayerNote = ""
                    } label: {
                        Label("Clear note", systemImage: "xmark.circle")
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
                }
            }
        }
    }

    private var prayerProgress: Double {
        let total = max(selectedPrayerMinutes * 60, 1)
        return 1 - (Double(prayerRemainingSeconds) / Double(total))
    }

    private var prayerPhaseTitle: String {
        if prayerRemainingSeconds == 0 {
            return "Prayer complete"
        }
        return isPrayerRunning ? "Stay present." : "Settle your heart."
    }

    private var prayerPhaseSubtitle: String {
        if prayerRemainingSeconds == 0 {
            return "Log the session, write the next obedient step, then return to your day."
        }
        if isPrayerRunning {
            return "No performing. No rushing. Pray honestly and let the timer hold the space."
        }
        return "Choose a quiet window. Start small enough to repeat, serious enough to matter."
    }

    private enum PrayerStorageKey {
        static let isRunning = "climb.prayer.isRunning"
        static let startedAt = "climb.prayer.startedAt"
        static let endsAt = "climb.prayer.endsAt"
        static let remainingSeconds = "climb.prayer.remainingSeconds"
        static let selectedMinutes = "climb.prayer.selectedMinutes"
    }

    private var prayerDefaults: UserDefaults {
        Self.sharedPrayerDefaults ?? .standard
    }

    private func loadSharedPrayerTimerState() {
        let defaults = prayerDefaults
        let storedMinutes = defaults.integer(forKey: PrayerStorageKey.selectedMinutes)
        if storedMinutes > 0 {
            selectedPrayerMinutes = min(max(storedMinutes, 1), 30)
        }

        let storedRemaining = defaults.integer(forKey: PrayerStorageKey.remainingSeconds)
        let endsAtInterval = defaults.double(forKey: PrayerStorageKey.endsAt)
        let endsAt = endsAtInterval > 0 ? Date(timeIntervalSince1970: endsAtInterval) : nil

        guard defaults.bool(forKey: PrayerStorageKey.isRunning) else {
            prayerRemainingSeconds = storedRemaining > 0 ? min(storedRemaining, selectedPrayerMinutes * 60) : selectedPrayerMinutes * 60
            return
        }

        guard let endsAt else {
            isPrayerRunning = false
            prayerRemainingSeconds = selectedPrayerMinutes * 60
            clearSharedPrayerTimer()
            return
        }

        let remaining = Int(ceil(endsAt.timeIntervalSinceNow))
        if remaining > 0 {
            isPrayerRunning = true
            prayerRemainingSeconds = min(remaining, selectedPrayerMinutes * 60)
        } else {
            prayerSessionsCompleted += 1
            prayerMinutesCompleted += max(1, selectedPrayerMinutes)
            isPrayerRunning = false
            prayerRemainingSeconds = selectedPrayerMinutes * 60
            clearSharedPrayerTimer()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func startSharedPrayerTimer() {
        let defaults = prayerDefaults
        let now = Date()
        let safeRemaining = max(prayerRemainingSeconds, 60)
        defaults.set(true, forKey: PrayerStorageKey.isRunning)
        defaults.set(now.timeIntervalSince1970, forKey: PrayerStorageKey.startedAt)
        defaults.set(now.addingTimeInterval(TimeInterval(safeRemaining)).timeIntervalSince1970, forKey: PrayerStorageKey.endsAt)
        defaults.set(safeRemaining, forKey: PrayerStorageKey.remainingSeconds)
        defaults.set(selectedPrayerMinutes, forKey: PrayerStorageKey.selectedMinutes)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func pauseSharedPrayerTimer() {
        let defaults = prayerDefaults
        defaults.set(false, forKey: PrayerStorageKey.isRunning)
        defaults.set(max(prayerRemainingSeconds, 0), forKey: PrayerStorageKey.remainingSeconds)
        defaults.removeObject(forKey: PrayerStorageKey.startedAt)
        defaults.removeObject(forKey: PrayerStorageKey.endsAt)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func clearSharedPrayerTimer() {
        let defaults = prayerDefaults
        defaults.set(false, forKey: PrayerStorageKey.isRunning)
        defaults.removeObject(forKey: PrayerStorageKey.startedAt)
        defaults.removeObject(forKey: PrayerStorageKey.endsAt)
        defaults.removeObject(forKey: PrayerStorageKey.remainingSeconds)
    }

    private func tickPrayerTimer() {
        guard isPrayerRunning else { return }
        guard prayerRemainingSeconds > 0 else {
            completePrayerSession()
            return
        }

        prayerRemainingSeconds -= 1

        if prayerRemainingSeconds == 0 {
            completePrayerSession()
        }
    }

    private func togglePrayerTimer() {
        HapticFeedback.impact(.medium)
        if prayerRemainingSeconds == 0 {
            prayerRemainingSeconds = selectedPrayerMinutes * 60
        }
        let shouldRun = !isPrayerRunning
        withAnimation(ClimbMotion.quick) {
            isPrayerRunning = shouldRun
        }
        if shouldRun {
            startSharedPrayerTimer()
        } else {
            pauseSharedPrayerTimer()
        }
    }

    private func resetPrayerTimer() {
        HapticFeedback.selection()
        withAnimation(ClimbMotion.quick) {
            isPrayerRunning = false
            prayerRemainingSeconds = selectedPrayerMinutes * 60
        }
        clearSharedPrayerTimer()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func completePrayerSession() {
        guard isPrayerRunning || prayerRemainingSeconds < selectedPrayerMinutes * 60 else { return }
        HapticFeedback.impact(.medium)
        let completedSeconds = max((selectedPrayerMinutes * 60) - prayerRemainingSeconds, 60)
        let completedMinutes = max(1, Int((Double(completedSeconds) / 60).rounded()))
        prayerSessionsCompleted += 1
        prayerMinutesCompleted += completedMinutes
        prayerLastCompletedAt = Date().timeIntervalSince1970
        AppAnalytics.record(
            .prayerSessionCompleted,
            properties: [
                "minutes": "\(completedMinutes)",
                "target": "\(selectedPrayerMinutes)"
            ]
        )
        withAnimation(ClimbMotion.standard) {
            isPrayerRunning = false
            prayerRemainingSeconds = selectedPrayerMinutes * 60
        }
        clearSharedPrayerTimer()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func startProtectedFocus(
        purpose: FocusPurpose,
        minutes: Int,
        beginPrayerTimer: Bool
    ) {
        guard !isStartingProtectedFocus else { return }
        isStartingProtectedFocus = true
        let request = FocusSessionRequest(
            purpose: purpose,
            customPurposeName: nil,
            plannedDuration: TimeInterval(max(minutes, 1) * 60),
            strictness: .intentional,
            selectionReference: FocusSelectionReference(
                rawValue: ScreenTimeSelectionReference.defaultSelection
            ),
            essentialAppsReference: nil,
            blocksAdultWebContent: FocusAdultContentFilterStore.isEnabled
        )

        Task {
            do {
                _ = try await focusRuntime.start(request)
                await MainActor.run {
                    isStartingProtectedFocus = false
                    if beginPrayerTimer, !isPrayerRunning {
                        togglePrayerTimer()
                    }
                    HapticFeedback.success()
                }
            } catch {
                await MainActor.run {
                    isStartingProtectedFocus = false
                    focusErrorMessage = error.localizedDescription
                    HapticFeedback.impact(.medium)
                }
            }
        }
    }

    private func dailyWordFeedback(for devotional: Devotional) -> DailyWordFeedbackOption? {
        let dayKey = Self.feedbackDayKey(for: devotional.date)
        guard dailyWordFeedbackDate == dayKey else { return nil }
        return DailyWordFeedbackOption(rawValue: dailyWordFeedbackValue)
    }

    private func submitDailyWordFeedback(_ option: DailyWordFeedbackOption, for devotional: Devotional) {
        HapticFeedback.selection()
        dailyWordFeedbackDate = Self.feedbackDayKey(for: devotional.date)
        dailyWordFeedbackValue = option.rawValue
        AppAnalytics.record(
            .dailyWordFeedback,
            properties: [
                "feedback": option.rawValue,
                "verse": devotional.bibleVerse
            ]
        )
    }

    private static func feedbackDayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
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
                    AppAnalytics.record(.growSectionChanged, properties: ["section": section.rawValue])
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

private enum DailyWordFeedbackOption: String, CaseIterable, Identifiable {
    case helpful
    case challenging
    case missed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .helpful: "Helpful"
        case .challenging: "Convicting"
        case .missed: "Missed"
        }
    }

    var symbol: String {
        switch self {
        case .helpful: "checkmark.circle.fill"
        case .challenging: "flame.fill"
        case .missed: "arrow.triangle.2.circlepath"
        }
    }
}

private struct DailyWordFeedbackRow: View {
    let selected: DailyWordFeedbackOption?
    let onSelect: (DailyWordFeedbackOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selected == nil ? "Was this word useful today?" : "Feedback saved for today")
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)

            HStack(spacing: 8) {
                ForEach(DailyWordFeedbackOption.allCases) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .foregroundStyle(selected == option ? Color.climbInk : Color.climbTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selected == option ? Color.climbGreen : Color.climbBackgroundLifted.opacity(0.62),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected == option ? Color.climbGreen.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 0.7)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }
}

private struct MemoryMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(ClimbTypography.sans(9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.climbBackgroundLifted.opacity(0.52), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 0.7)
        )
    }
}

private struct VerseMemoryRow: View {
    let verse: MemorizedVerse
    let isPrimary: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack {
                Circle()
                    .fill(verse.isDue ? Color.climbGreen.opacity(0.16) : Color.climbBackgroundLifted.opacity(0.72))
                Image(systemName: verse.isDue ? "bell.badge.fill" : "book.closed.fill")
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(verse.isDue ? Color.climbGreen : Color.climbMuted)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                Text(verse.reference)
                    .font(ClimbTypography.sans(isPrimary ? 16 : 14, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(verse.isDue ? "Review now" : "Next review: \(verse.nextReviewLabel)")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(verse.isDue ? Color.climbGreen : Color.climbTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)

            Text("\(Int((verse.mastery * 100).rounded()))%")
                .font(ClimbTypography.sans(12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.climbBackgroundLifted.opacity(0.64), in: Capsule())
        }
        .padding(14)
        .background(
            Color.climbSurfaceRaised.opacity(isPrimary ? 0.62 : 0.42),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(verse.isDue ? Color.climbGreen.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 0.7)
        )
    }
}

private struct VersePack: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let focus: Struggle
    let verses: [VersePackVerse]

    static func recommended(for struggle: Struggle?) -> [VersePack] {
        let all = library
        guard let struggle else {
            return Array(all.prefix(4))
        }

        let primary = all.filter { $0.focus == struggle }
        let secondary = all.filter { $0.focus != struggle }
        return Array((primary + secondary).prefix(4))
    }

    private static let library: [VersePack] = [
        VersePack(
            id: "focus-boundaries",
            title: "Attention Under God",
            subtitle: "Verses for focus, phone boundaries, and undivided work.",
            symbol: "scope",
            focus: .focus,
            verses: [
                VersePackVerse(
                    reference: "Colossians 3:23 (WEB)",
                    text: "And whatever you do, work heartily, as for the Lord, and not for men,",
                    prompt: "Where can you give God one cleaner block of attention today?"
                ),
                VersePackVerse(
                    reference: "Proverbs 4:25 (WEB)",
                    text: "Let your eyes look straight ahead. Fix your gaze directly before you.",
                    prompt: "What distraction needs to lose authority over your next hour?"
                ),
                VersePackVerse(
                    reference: "Matthew 6:22 (WEB)",
                    text: "The lamp of the body is the eye. If therefore your eye is sound, your whole body will be full of light.",
                    prompt: "What are you looking at that is shaping your desires?"
                )
            ]
        ),
        VersePack(
            id: "discipline-faithfulness",
            title: "Faithful in Small Things",
            subtitle: "Verses for consistency, delayed tasks, and doing the next right thing.",
            symbol: "checkmark.seal",
            focus: .discipline,
            verses: [
                VersePackVerse(
                    reference: "Luke 16:10 (WEB)",
                    text: "He who is faithful in a very little is faithful also in much. He who is dishonest in a very little is also dishonest in much.",
                    prompt: "What small act of faithfulness is in front of you right now?"
                ),
                VersePackVerse(
                    reference: "Proverbs 13:4 (WEB)",
                    text: "The soul of the sluggard desires, and has nothing, but the desire of the diligent shall be fully satisfied.",
                    prompt: "What desire needs diligence instead of more intention?"
                ),
                VersePackVerse(
                    reference: "Galatians 6:9 (WEB)",
                    text: "Let us not be weary in doing good, for we will reap in due season, if we don't give up.",
                    prompt: "Where are you tired of doing good, and what would it mean not to give up today?"
                )
            ]
        ),
        VersePack(
            id: "self-control-purity",
            title: "Guard the First Move",
            subtitle: "Verses for temptation, purity, and prepared boundaries.",
            symbol: "shield.lefthalf.filled",
            focus: .purity,
            verses: [
                VersePackVerse(
                    reference: "1 Corinthians 10:13 (WEB)",
                    text: "No temptation has taken you except what is common to man. God is faithful, who will not allow you to be tempted above what you are able, but will with the temptation also make the way of escape, that you may be able to endure it.",
                    prompt: "What is the way of escape you need to take before the pressure grows?"
                ),
                VersePackVerse(
                    reference: "2 Timothy 2:22 (WEB)",
                    text: "Flee from youthful lusts; but pursue righteousness, faith, love, and peace with those who call on the Lord out of a pure heart.",
                    prompt: "What do you need to flee, and what better pursuit replaces it?"
                ),
                VersePackVerse(
                    reference: "Psalm 51:10 (WEB)",
                    text: "Create in me a clean heart, O God. Renew a right spirit within me.",
                    prompt: "What would a clean next step look like today?"
                )
            ]
        ),
        VersePack(
            id: "prayer-rhythm",
            title: "Return to Prayer",
            subtitle: "Verses for honest prayer before pressure takes over.",
            symbol: "hands.sparkles",
            focus: .prayer,
            verses: [
                VersePackVerse(
                    reference: "1 Thessalonians 5:17 (WEB)",
                    text: "Pray without ceasing.",
                    prompt: "What pressure can become prayer before it becomes anxiety?"
                ),
                VersePackVerse(
                    reference: "Philippians 4:6 (WEB)",
                    text: "In nothing be anxious, but in everything, by prayer and petition with thanksgiving, let your requests be made known to God.",
                    prompt: "What request have you been carrying instead of naming?"
                ),
                VersePackVerse(
                    reference: "Jeremiah 33:3 (WEB)",
                    text: "Call to me, and I will answer you, and will show you great things, and difficult, which you don't know.",
                    prompt: "Where do you need to ask instead of assuming you are alone?"
                )
            ]
        ),
        VersePack(
            id: "scripture-rooted",
            title: "Rooted in the Word",
            subtitle: "Verses for scripture hunger, memory, and daily obedience.",
            symbol: "book.closed",
            focus: .scripture,
            verses: [
                VersePackVerse(
                    reference: "Psalm 119:105 (WEB)",
                    text: "Your word is a lamp to my feet, and a light for my path.",
                    prompt: "What decision needs light from scripture today?"
                ),
                VersePackVerse(
                    reference: "Joshua 1:8 (WEB)",
                    text: "This book of the law shall not depart out of your mouth, but you shall meditate on it day and night, that you may observe to do according to all that is written in it; for then you shall make your way prosperous, and then you shall have good success.",
                    prompt: "What would it mean to meditate before you react?"
                ),
                VersePackVerse(
                    reference: "Psalm 119:11 (WEB)",
                    text: "I have hidden your word in my heart, that I might not sin against you.",
                    prompt: "What verse needs to be hidden in your heart before the next trigger?"
                )
            ]
        ),
        VersePack(
            id: "approval-courage",
            title: "Courage Over Approval",
            subtitle: "Verses for social pressure, fear, and public obedience.",
            symbol: "person.line.dotted.person",
            focus: .socialPressure,
            verses: [
                VersePackVerse(
                    reference: "Romans 12:2 (WEB)",
                    text: "Don't be conformed to this world, but be transformed by the renewing of your mind, so that you may prove what is the good, well-pleasing, and perfect will of God.",
                    prompt: "Where are you conforming because it feels safer?"
                ),
                VersePackVerse(
                    reference: "Proverbs 29:25 (WEB)",
                    text: "The fear of man proves to be a snare, but whoever puts his trust in Yahweh is kept safe.",
                    prompt: "Whose opinion feels too powerful today?"
                ),
                VersePackVerse(
                    reference: "Galatians 1:10 (WEB)",
                    text: "For am I now seeking the favor of men, or of God? Or am I striving to please men? For if I were still pleasing men, I wouldn't be a servant of Christ.",
                    prompt: "What action would you take if pleasing God mattered most here?"
                )
            ]
        )
    ]
}

private struct VersePackVerse: Identifiable, Equatable {
    let id = UUID()
    let reference: String
    let text: String
    let prompt: String
}

private struct VersePackDetailSheet: View {
    let pack: VersePack
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            ClimbScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 42, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(pack.title, systemImage: pack.symbol)
                            .font(ClimbTypography.sans(13, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(Color.climbGreen)
                        Text(pack.subtitle)
                            .font(ClimbTypography.serif(31))
                            .foregroundStyle(Color.climbMist)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(pack.verses) { verse in
                        VersePracticeCard(
                            verse: verse,
                            isSaved: viewModel.isVerseMemorized(reference: verse.reference)
                        ) {
                            Task {
                                await viewModel.memorizeVerse(
                                    reference: verse.reference,
                                    text: verse.text,
                                    sourceTitle: pack.title,
                                    struggle: pack.focus
                                )
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct VersePracticeCard: View {
    let verse: VersePackVerse
    let isSaved: Bool
    let onMemorize: () -> Void

    var body: some View {
        ClimbCard(padding: 19, cornerRadius: 23) {
            Text(verse.reference)
                .font(ClimbTypography.sans(12, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
            Text("“\(verse.text)”")
                .font(ClimbTypography.serif(25))
                .foregroundStyle(Color.climbWarm)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            ScriptureAttributionText(reference: verse.reference)

            Divider().overlay(Color.white.opacity(0.08))

            Text(verse.prompt)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: onMemorize) {
                    Label(isSaved ? "Saved" : "Memorize", systemImage: isSaved ? "checkmark.seal.fill" : "plus.circle")
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(isSaved ? Color.climbGreen : Color.climbMist)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.climbBackgroundLifted.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isSaved ? Color.climbGreen.opacity(0.25) : Color.white.opacity(0.065), lineWidth: 0.7)
                        )
                }
                .buttonStyle(ScaleButtonStyle())

                ShareLink(item: "\(verse.reference)\n\(verse.text)\n\n\(verse.prompt)") {
                    Image(systemName: "square.and.arrow.up")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .foregroundStyle(Color.climbGreen)
                        .frame(width: 44, height: 44)
                        .background(Color.climbGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.climbGreen.opacity(0.18), lineWidth: 0.7)
                        )
                        .accessibilityLabel("Share verse")
                }
            }
        }
    }
}

private struct VerseMemoryReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    let verse: MemorizedVerse
    @State private var recallText = ""
    @State private var isRevealed = false

    var body: some View {
        ZStack {
            ClimbScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 42, height: 4)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("VERSE REVIEW")
                            .font(ClimbTypography.sans(11, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(Color.climbGreen.opacity(0.86))
                        Text(verse.reference)
                            .font(ClimbTypography.serif(34))
                            .foregroundStyle(Color.climbMist)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Try writing or saying it from memory before revealing the text.")
                            .font(ClimbTypography.sans(14, weight: .semibold))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(3)
                    }

                    TextField("Type what you remember", text: $recallText, axis: .vertical)
                        .lineLimit(4...8)
                        .formFieldStyle()

                    if isRevealed {
                        ClimbCard(padding: 18, cornerRadius: 22, isProminent: true) {
                            Text("“\(verse.text)”")
                                .font(ClimbTypography.serif(27))
                                .foregroundStyle(Color.climbWarm)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                            ScriptureAttributionText(reference: verse.reference)
                        }
                        .transition(.climbScreen)
                    } else {
                        PrimaryActionButton(title: "Reveal verse", systemImage: "eye") {
                            withAnimation(ClimbMotion.focus) {
                                isRevealed = true
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        SecondaryActionButton(title: "Review again", systemImage: "arrow.counterclockwise") {
                            Task {
                                await viewModel.reviewMemorizedVerse(verse.id, remembered: false)
                                dismiss()
                            }
                        }

                        PrimaryActionButton(title: "Remembered", systemImage: "checkmark.seal.fill") {
                            Task {
                                await viewModel.reviewMemorizedVerse(verse.id, remembered: true)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isRevealed)
                    .opacity(isRevealed ? 1 : 0.48)

                    Button(role: .destructive) {
                        Task {
                            await viewModel.archiveMemorizedVerse(verse.id)
                            dismiss()
                        }
                    } label: {
                        Label("Remove from memory", systemImage: "archivebox")
                            .font(ClimbTypography.sans(13, weight: .semibold))
                            .foregroundStyle(Color.climbMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(20)
                .padding(.bottom, 30)
            }
        }
        .animation(ClimbMotion.focus, value: isRevealed)
    }
}

private struct PrayerDurationPicker: View {
    @Binding var selectedMinutes: Int
    let isDisabled: Bool

    private let options = [2, 5, 10, 15]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { minutes in
                Button {
                    HapticFeedback.selection()
                    withAnimation(ClimbMotion.quick) {
                        selectedMinutes = minutes
                    }
                } label: {
                    Text("\(minutes)m")
                        .font(ClimbTypography.sans(13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(selectedMinutes == minutes ? Color.climbInk : Color.climbTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedMinutes == minutes ? Color.climbGreen : Color.climbBackgroundLifted.opacity(0.64),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selectedMinutes == minutes ? Color.climbGreen.opacity(0.36) : Color.white.opacity(0.06), lineWidth: 0.7)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isDisabled)
                .opacity(isDisabled && selectedMinutes != minutes ? 0.46 : 1)
            }
        }
    }
}

private struct PrayerTimerRing: View {
    let progress: Double
    let remainingSeconds: Int
    let isRunning: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    LinearGradient(colors: [.climbGreen, .climbSage], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.climbGreen.opacity(isRunning ? 0.32 : 0.12), radius: isRunning ? 12 : 5)

            VStack(spacing: 2) {
                Text(formattedTime)
                    .font(ClimbTypography.sans(18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.climbMist)
                Text(isRunning ? "live" : "ready")
                    .font(ClimbTypography.sans(9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(isRunning ? Color.climbGreen : Color.climbMuted)
                    .textCase(.uppercase)
            }
        }
        .frame(width: 92, height: 92)
        .animation(ClimbMotion.standard, value: progress)
        .animation(ClimbMotion.quick, value: isRunning)
    }

    private var formattedTime: String {
        let minutes = max(remainingSeconds, 0) / 60
        let seconds = max(remainingSeconds, 0) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct PrayerMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(ClimbTypography.sans(18, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.climbBackgroundLifted.opacity(0.52), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HabitSummaryCard: View {
    let completed: Int
    let total: Int
    let progress: Double

    var body: some View {
        ClimbQuietPanel(padding: 20, cornerRadius: 22, isProminent: true) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Habit check-in")
                        .font(ClimbTypography.sans(11, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Color.climbTextSecondary)
                        .textCase(.uppercase)
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
        .background(Color.climbBackgroundLifted.opacity(habit.isEnabled ? 0.48 : 0.28), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isDoneToday ? Color.climbGreen.opacity(0.24) : Color.climbHairline.opacity(0.70), lineWidth: 0.75)
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
    @State private var isStartingFocus = false
    @State private var focusErrorMessage: String?

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

                    SecondaryActionButton(
                        title: isStartingFocus
                            ? "Starting protection"
                            : "Protect 15 Minutes",
                        systemImage: "shield.lefthalf.filled"
                    ) {
                        startHabitFocus(habit)
                    }
                    .disabled(isStartingFocus || !habit.isEnabled)
                    .opacity(isStartingFocus || !habit.isEnabled ? 0.55 : 1)

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
        .alert(
            "Focus protection needs setup",
            isPresented: Binding(
                get: { focusErrorMessage != nil },
                set: { if !$0 { focusErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(focusErrorMessage ?? "")
        }
    }

    private func startHabitFocus(_ habit: GrowthHabit) {
        guard !isStartingFocus else { return }
        isStartingFocus = true
        let request = FocusSessionRequest(
            purpose: .personalGrowth,
            customPurposeName: habit.title,
            plannedDuration: 15 * 60,
            strictness: .intentional,
            selectionReference: FocusSelectionReference(
                rawValue: ScreenTimeSelectionReference.defaultSelection
            ),
            essentialAppsReference: nil,
            blocksAdultWebContent: FocusAdultContentFilterStore.isEnabled
        )
        Task {
            do {
                _ = try await FocusSessionRuntimeService().start(request)
                await MainActor.run {
                    isStartingFocus = false
                    HapticFeedback.success()
                }
            } catch {
                await MainActor.run {
                    isStartingFocus = false
                    focusErrorMessage = error.localizedDescription
                }
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
