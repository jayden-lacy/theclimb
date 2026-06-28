import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = AppViewModel()
    @State private var selectedTab: AppTab = .home

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(Color.climbBackground.opacity(0.92))
        appearance.shadowColor = UIColor(Color.white.opacity(0.08))

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
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
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
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, viewModel.profile != nil else { return }
            Task {
                await viewModel.refreshActiveSession()
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
