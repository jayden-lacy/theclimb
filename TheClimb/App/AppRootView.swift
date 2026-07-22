import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = AppViewModel()
    @State private var selectedTab: AppTab = .home
    @State private var pendingInviteLink: ClimbInviteLink?

    init() {
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
            if viewModel.isLoading {
                LaunchLoadingView()
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
        .animation(ClimbMotion.standard, value: viewModel.isLoading)
        .animation(ClimbMotion.standard, value: viewModel.profile?.id)
        .preferredColorScheme(.dark)
        .task {
            await viewModel.load()
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
            Task {
                handleShortcutDestinationIfPossible()
                await handlePendingInviteIfPossible()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, viewModel.profile != nil else { return }
            Task {
                handleShortcutDestinationIfPossible()
                await viewModel.refreshActiveSession()
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

    private static func tab(from value: String) -> AppTab? {
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
    var body: some View {
        ZStack {
            ClimbScreenBackground()
            VStack(spacing: 16) {
                SwiftUI.ProgressView()
                    .tint(.climbGreen)
                Text("Preparing your climb")
                    .font(ClimbTypography.sans(18, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
