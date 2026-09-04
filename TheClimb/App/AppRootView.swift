import SwiftUI
import UIKit

struct AppRootView: View {
    private static let screenTimeExperienceVersion = 1

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = AppViewModel()
    @State private var selectedTab: AppTab = .home
    @State private var pendingInviteLink: ClimbInviteLink?
    @State private var pendingScreenTimeUpgrade: ScreenTimeUpgradeProgress?
    @State private var loadingScripture = LoadingScriptureProvider.next()

    init() {
#if DEBUG
        if Self.debugPurityProtectionSetup {
            PurityProtectionPreferenceStore.setPersonalizationEnabled(true)
        }
#endif
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterialDark)
        appearance.backgroundColor = UIColor(Color.climbBackgroundDeep.opacity(0.98))
        appearance.shadowColor = UIColor(Color.white.opacity(0.10))

        let selectedColor = UIColor(Color.climbMist)
        let normalColor = UIColor(Color.climbMuted)
        [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance].forEach { itemAppearance in
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: selectedColor,
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
            ]
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: normalColor,
                .font: UIFont.systemFont(ofSize: 11, weight: .medium)
            ]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        Group {
#if DEBUG
            if Self.debugLoadingPreview {
                LaunchLoadingView(scripture: loadingScripture)
            } else if Self.debugPurityProtectionSetup {
                ScreenTimeUpgradeView(
                    viewModel: viewModel,
                    progress: Self.debugPurityProtectionProgress,
                    experienceVersion: 9_999,
                    persistsProgress: false,
                    onFinished: {}
                )
            } else if Self.debugFocusControlCenter {
                FocusControlCenterView(viewModel: viewModel)
            } else {
                appContent
            }
#else
            appContent
#endif
        }
        .animation(ClimbMotion.standard, value: viewModel.isLoading)
        .animation(ClimbMotion.standard, value: viewModel.profile?.id)
        .preferredColorScheme(.dark)
        .task {
#if DEBUG
            if Self.debugLoadingPreview || Self.debugFocusControlCenter || Self.debugPurityProtectionSetup {
                return
            }
#endif
            await viewModel.load()
            syncPersonalizedProtection()
            await ScreenTimeRuntimeBootstrapper().reconcile()
            await reconcileAttentionAssist()
            prepareScreenTimeUpgradeIfNeeded()
#if DEBUG
            if let screenshotTab = Self.debugScreenshotTab {
                selectedTab = screenshotTab
            }
#endif
            handleShortcutDestinationIfPossible()
            await handlePendingInviteIfPossible()
        }
        .onOpenURL { url in
            routeInviteURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            routeInviteURL(url)
        }
        .onChange(of: viewModel.profile?.id) { _, _ in
            prepareScreenTimeUpgradeIfNeeded()
            Task {
                handleShortcutDestinationIfPossible()
                await handlePendingInviteIfPossible()
            }
        }
        .onChange(of: viewModel.isLoading) { wasLoading, isLoading in
            guard isLoading, !wasLoading else { return }
            loadingScripture = LoadingScriptureProvider.next()
        }
        .onChange(of: viewModel.profile?.mainStruggle) { _, _ in
            syncPersonalizedProtection()
            Task {
                await ScreenTimeRuntimeBootstrapper().reconcile()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, viewModel.profile != nil else { return }
            Task {
                handleShortcutDestinationIfPossible()
                await viewModel.refreshActiveSession()
                await ScreenTimeRuntimeBootstrapper().reconcile()
                await reconcileAttentionAssist()
                await handlePendingInviteIfPossible()
            }
        }
        .alert("The Climb", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .fullScreenCover(item: $pendingScreenTimeUpgrade) { progress in
            ScreenTimeUpgradeView(
                viewModel: viewModel,
                progress: progress,
                experienceVersion: Self.screenTimeExperienceVersion
            ) {
                pendingScreenTimeUpgrade = nil
            }
        }
    }

    @ViewBuilder
    private var appContent: some View {
        if viewModel.isLoading {
            LaunchLoadingView(scripture: loadingScripture)
                .transition(.climbScreen)
        } else if viewModel.profile == nil {
            OnboardingView(viewModel: viewModel)
                .transition(.climbScreen)
        } else {
            TabView(selection: $selectedTab) {
                HomeView(viewModel: viewModel)
                    .tabItem { Label(AppTab.home.rawValue, systemImage: AppTab.home.symbol) }
                    .tag(AppTab.home)

                GrowView(viewModel: viewModel)
                    .tabItem { Label(AppTab.grow.rawValue, systemImage: AppTab.grow.symbol) }
                    .tag(AppTab.grow)

                CommunityView(viewModel: viewModel)
                    .tabItem { Label(AppTab.community.rawValue, systemImage: AppTab.community.symbol) }
                    .tag(AppTab.community)

                ProgressDashboardView(viewModel: viewModel)
                    .tabItem { Label(AppTab.progress.rawValue, systemImage: AppTab.progress.symbol) }
                    .tag(AppTab.progress)

                ProfileView(viewModel: viewModel)
                    .tabItem { Label(AppTab.profile.rawValue, systemImage: AppTab.profile.symbol) }
                    .tag(AppTab.profile)
            }
            .tint(.climbAction)
            .toolbarBackground(Color.climbBackgroundDeep.opacity(0.98), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .transition(.climbScreen)
            .animation(ClimbMotion.quick, value: selectedTab)
            .onChange(of: selectedTab) { _, _ in
                HapticFeedback.selection()
            }
        }
    }

    private func syncPersonalizedProtection() {
        PurityProtectionPreferenceStore.setPersonalizationEnabled(
            viewModel.profile?.mainStruggle == .purity
        )
        PurityProtectionPreferenceStore.setFocusFilterEnabled(
            FocusAdultContentFilterStore.isEnabled
        )
    }

    private func routeInviteURL(_ url: URL) {
        guard let link = ClimbInviteLink(url: url) else { return }
        pendingInviteLink = link
        if viewModel.profile != nil {
            switch link {
            case .open(let tab):
                selectedTab = tab
            case .partner, .group:
                selectedTab = .community
            }
        }
        Task {
            await handlePendingInviteIfPossible()
        }
    }

    private func handleShortcutDestinationIfPossible() {
        guard viewModel.profile != nil,
              let tab = ClimbShortcutHandoffStore.consumeDestination() else { return }
        selectedTab = tab
    }

    private func handlePendingInviteIfPossible() async {
        guard viewModel.profile != nil, let link = pendingInviteLink else { return }
        pendingInviteLink = nil

        switch link {
        case .open(let tab):
            selectedTab = tab
        case .partner(let code):
            selectedTab = .community
            let didAccept = await viewModel.acceptPartnerInvite(code: code)
            if !didAccept {
                viewModel.errorMessage = "That accountability invite could not be joined."
            }
        case .group(let groupID):
            selectedTab = .community
            await viewModel.refreshCommunityGroups()
            let didJoin = await viewModel.joinGroup(groupID)
            if !didJoin {
                viewModel.errorMessage = "That group invite could not be joined."
            }
        }
    }

    private func prepareScreenTimeUpgradeIfNeeded() {
#if DEBUG
        // Screenshot QA must open the requested destination deterministically.
        // Production launches continue to run the upgrade migration normally.
        if Self.debugScreenshotTab != nil {
            return
        }
#endif
        guard viewModel.profile != nil,
              pendingScreenTimeUpgrade == nil else {
            return
        }
        do {
            let store = AppGroupScreenTimeUpgradeStateStore()
            let result = try ScreenTimeUpgradeMigrationService(
                store: store
            ).run(
                input: ScreenTimeUpgradeMigrationInput(
                    profilePresence: .existing,
                    targetExperienceVersion: Self.screenTimeExperienceVersion
                )
            )
            guard result.shouldPresent,
                  let progress = result.state?.progress(
                    for: Self.screenTimeExperienceVersion
                  ) else {
                return
            }
            pendingScreenTimeUpgrade = progress
        } catch {
            // Setup migration is additive. A storage failure must not lock users
            // out of their existing profile and core app.
        }
    }

    private func reconcileAttentionAssist() async {
        let signals = AttentionAssistSignalSource().currentSignals()
        _ = try? await AttentionAssistRuntimeService().reconcileForLaunch(
            signals: signals
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

#if DEBUG
    private static var debugLoadingPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("-loadingPreview")
    }

    private static var debugFocusControlCenter: Bool {
        ProcessInfo.processInfo.arguments.contains("-focusControlsPreview")
    }

    private static var debugPurityProtectionSetup: Bool {
        ProcessInfo.processInfo.arguments.contains("-purityProtectionPreview")
    }

    private static var debugPurityProtectionProgress: ScreenTimeUpgradeProgress {
        ScreenTimeUpgradeProgress(
            experienceVersion: 9_999,
            flowKind: .existingUserShortUpgrade,
            status: .inProgress,
            completedSteps: [
                .upgradeIntroduction,
                .capabilityExplanation,
                .screenTimeAuthorization
            ],
            skippedSteps: [],
            deferredSteps: [],
            startedAt: Date(),
            lastPresentedAt: Date(),
            remindAfter: nil,
            acknowledgedAt: nil,
            completedAt: nil,
            updatedAt: Date()
        )
    }

    private static var debugScreenshotTab: AppTab? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-screenshotTab"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return ClimbInviteLink.tab(from: arguments[flagIndex + 1])
    }
#endif
}

private enum ClimbInviteLink: Equatable {
    case open(tab: AppTab)
    case partner(code: String)
    case group(id: String)

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = (components.scheme ?? "").lowercased()
        let host = (components.host ?? "").lowercased()
        let path = components.path.lowercased()

        if scheme == "theclimb" {
            if host == "open" || path == "/open" {
                self = .open(tab: Self.tabValue(in: components) ?? .home)
                return
            }

            if let tab = Self.tab(from: host), path.isEmpty {
                self = .open(tab: tab)
                return
            }

            if host == "invite" || path == "/invite" {
                guard let code = Self.queryValue("code", in: components) else { return nil }
                self = .partner(code: code)
                return
            }

            if host == "group" || path == "/group" {
                guard let id = Self.queryValue("id", in: components) ?? Self.queryValue("groupID", in: components) else { return nil }
                self = .group(id: id)
                return
            }
        }

        guard (scheme == "https" || scheme == "http"),
              host == "theclimbapp.org" || host == "www.theclimbapp.org" else {
            return nil
        }

        if path == "/open" {
            self = .open(tab: Self.tabValue(in: components) ?? .home)
            return
        }

        if path == "/invite" {
            guard let code = Self.queryValue("code", in: components) else { return nil }
            self = .partner(code: code)
            return
        }

        if path == "/group" {
            guard let id = Self.queryValue("id", in: components) ?? Self.queryValue("groupID", in: components) else { return nil }
            self = .group(id: id)
            return
        }

        return nil
    }

    private static func queryValue(_ name: String, in components: URLComponents) -> String? {
        guard let value = components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func tabValue(in components: URLComponents) -> AppTab? {
        guard let rawValue = queryValue("tab", in: components) else { return nil }
        return tab(from: rawValue)
    }

    fileprivate static func tab(from value: String) -> AppTab? {
        switch value.lowercased() {
        case "home", "mission", "focus", "block", "shield":
            .home
        case "grow", "dailyword", "word", "devotional":
            .grow
        case "community", "circle", "partner", "partners":
            .community
        case "progress", "insights", "report":
            .progress
        case "profile", "me", "settings":
            .profile
        default:
            nil
        }
    }
}

private struct LaunchLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scripture: LoadingScripture
    @State private var isPresented = false

    var body: some View {
        ZStack {
            ClimbScreenBackground()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 48)

                        Text("A WORD FOR THE CLIMB")
                            .font(ClimbTypography.sans(11, weight: .semibold))
                            .tracking(ClimbTypography.eyebrowTracking)
                            .foregroundStyle(Color.climbBlue)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("“\(scripture.text)”")
                            .font(ClimbTypography.serif(30))
                            .foregroundStyle(Color.climbMist)
                            .lineSpacing(7)
                            .padding(.top, 18)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Rectangle()
                                .fill(Color.climbViolet)
                                .frame(width: 28, height: 1)

                            Text(scripture.reference)
                                .font(ClimbTypography.sans(13, weight: .semibold))
                                .foregroundStyle(Color.climbTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 22)

                        ScriptureAttributionText(reference: scripture.reference)
                            .padding(.top, 9)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 48)

                        HStack(alignment: .firstTextBaseline, spacing: 11) {
                            SwiftUI.ProgressView()
                                .controlSize(.small)
                                .tint(.climbBlue)

                            Text("Preparing your climb")
                                .font(ClimbTypography.sans(13, weight: .medium))
                                .foregroundStyle(Color.climbTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 42)
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                    .padding(.horizontal, 32)
                }
                .scrollIndicators(.hidden)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .opacity(isPresented ? 1 : 0)
            .offset(y: reduceMotion || isPresented ? 0 : 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing your climb. \(scripture.text) \(scripture.reference)")
        .onAppear {
            if reduceMotion {
                isPresented = true
            } else {
                withAnimation(ClimbMotion.standard) {
                    isPresented = true
                }
            }
        }
    }
}

struct LoadingScripture: Identifiable, Equatable, Sendable {
    let id: String
    let reference: String
    let text: String
}

enum LoadingScriptureProvider {
    private static let lastScriptureIDKey = "climb.loadingScripture.lastID"

    static let scriptures: [LoadingScripture] = [
        LoadingScripture(
            id: "psalm-119-105",
            reference: "Psalm 119:105 (WEB)",
            text: "Your word is a lamp to my feet, and a light for my path."
        ),
        LoadingScripture(
            id: "james-4-8",
            reference: "James 4:8 (WEB)",
            text: "Draw near to God, and he will draw near to you."
        ),
        LoadingScripture(
            id: "galatians-6-9",
            reference: "Galatians 6:9 (WEB)",
            text: "Let us not be weary in doing good, for we will reap in due season, if we don’t give up."
        ),
        LoadingScripture(
            id: "psalm-51-10",
            reference: "Psalm 51:10 (WEB)",
            text: "Create in me a clean heart, O God. Renew a right spirit within me."
        ),
        LoadingScripture(
            id: "isaiah-26-3",
            reference: "Isaiah 26:3 (WEB)",
            text: "You will keep whoever’s mind is steadfast in perfect peace, because he trusts in you."
        ),
        LoadingScripture(
            id: "proverbs-4-25",
            reference: "Proverbs 4:25 (WEB)",
            text: "Let your eyes look straight ahead. Fix your gaze directly before you."
        ),
        LoadingScripture(
            id: "first-thessalonians-5-17",
            reference: "1 Thessalonians 5:17 (WEB)",
            text: "Pray without ceasing."
        ),
        LoadingScripture(
            id: "second-timothy-1-7",
            reference: "2 Timothy 1:7 (WEB)",
            text: "For God didn’t give us a spirit of fear, but of power, love, and self-control."
        )
    ]

    static func next(defaults: UserDefaults = .standard) -> LoadingScripture {
        guard let first = scriptures.first else {
            preconditionFailure("The loading scripture catalog must not be empty.")
        }

        let previousID = defaults.string(forKey: lastScriptureIDKey)
        let candidates = scriptures.filter { $0.id != previousID }
        let scripture = candidates.randomElement() ?? first
        defaults.set(scripture.id, forKey: lastScriptureIDKey)
        return scripture
    }
}
