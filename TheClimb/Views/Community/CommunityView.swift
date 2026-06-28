import SwiftUI
#if os(iOS)
import UIKit
#endif

private struct PartnerInviteShare: Identifiable, Equatable {
    let code: String

    var id: String { code }
    var joinLink: String { "https://theclimbapp.org/invite?code=\(code)" }

    var message: String {
        Self.message(for: code)
    }

    static func message(for code: String) -> String {
        "Join my accountability pair on The Climb. Use code \(code) in Community > Enter Invite Code.\n\nShare link: https://theclimbapp.org/invite?code=\(code)"
    }
}

struct CommunityView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var newPost = ""
    @State private var isPosting = false
    @State private var feedbackMessage: String?
    @State private var selectedPartner: AccountabilityPartner?
    @State private var checkedInPartnerID: String?
    @State private var inviteCode: String?
    @State private var partnerInviteShare: PartnerInviteShare?
    @State private var showAcceptPartnerInvite = false
    @State private var isCreatingPartnerInvite = false
    @FocusState private var isComposeFocused: Bool

    var body: some View {
        ScreenContainer(title: "Community") {
            communityHeader
            if let feedbackMessage {
                StatusBadge(text: feedbackMessage, color: .climbSage)
                    .transition(.climbToast)
            }
            primaryPartnerSection
            inviteFriendStrip
            viewAllPartnersLink
            secondaryCommunityLinks
        }
        .sheet(item: $selectedPartner) { partner in
            PartnerDetailSheet(
                viewModel: viewModel,
                partnerID: partner.id,
                onFeedback: showFeedback
            )
        }
        .sheet(isPresented: $showAcceptPartnerInvite) {
            AcceptPartnerInviteSheet(viewModel: viewModel, onFeedback: showFeedback)
                .presentationDetents([.medium])
        }
        .sheet(item: $partnerInviteShare) { invite in
            PartnerInviteShareSheet(invite: invite, onFeedback: showFeedback)
                .presentationDetents([.medium])
        }
        .task {
            await viewModel.refreshGlobalLeaderboard()
            await viewModel.refreshCommunityFeed()
            await viewModel.refreshAccountabilityPartners()
        }
    }

    private var communityHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Accountability")
                .font(ClimbTypography.sans(13, weight: .semibold))
                .foregroundStyle(Color.climbGreen.opacity(0.86))
                .tracking(1.3)
                .textCase(.uppercase)
            Text("Close circle.")
                .font(ClimbTypography.sans(32, weight: .semibold))
                .foregroundStyle(Color.climbMist)
                .fixedSize(horizontal: false, vertical: true)
            Text(primaryPartner.map { "\($0.name) is your pressure point today. Keep it personal, honest, and small." } ?? "Invite someone to climb with you.")
                .font(ClimbTypography.sans(14, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var primaryPartnerSection: some View {
        if let partner = primaryPartner {
            primaryPartnerCard(partner)
        } else {
            ClimbCard(padding: 22, cornerRadius: 26, isProminent: true) {
                SectionTitle(
                    title: currentPartnerInviteCode == nil ? "No partner yet" : "Invite ready",
                    subtitle: currentPartnerInviteCode == nil ? "Create an invite or accept one from a friend." : "Share the code with one person you trust."
                )
                PrimaryActionButton(
                    title: isCreatingPartnerInvite ? "Creating Invite" : (currentPartnerInviteCode == nil ? "Create Partner Invite" : "View Invite Code"),
                    systemImage: "person.badge.plus",
                    isDisabled: isCreatingPartnerInvite
                ) {
                    showOrCreatePartnerInvite()
                }
                SecondaryActionButton(title: "Enter Invite Code", systemImage: "number") {
                    showAcceptPartnerInvite = true
                }
            }
        }
    }

    private func primaryPartnerCard(_ partner: AccountabilityPartner) -> some View {
        let hasCheckedIn = checkedInPartnerID == partner.id || partner.lastCheckIn == "Just now" || partner.lastCheckIn == "Today"
        let isPending = partner.isPending

        return ClimbCard(padding: 24, cornerRadius: 26, isProminent: true) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Color.climbSage.opacity(0.11))
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(Color.climbSage.opacity(0.20), lineWidth: 1))
                    .overlay(
                        Text(String(partner.name.prefix(1)))
                            .font(ClimbTypography.sans(21, weight: .semibold))
                            .foregroundStyle(Color.climbAction)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(partner.name)
                        .font(ClimbTypography.sans(24, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    Text(partner.focus.shortLabel + " partner")
                        .font(ClimbTypography.sans(13, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                }

                Spacer(minLength: 0)

                Text(isPending ? "Pending" : (hasCheckedIn ? "Partner's turn" : "Your move"))
                    .font(ClimbTypography.sans(11, weight: .semibold))
                    .foregroundStyle(isPending ? Color.climbMuted : (hasCheckedIn ? Color.climbSage : Color.climbGold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isPending ? Color.climbMuted : (hasCheckedIn ? Color.climbSage : Color.climbGold)).opacity(0.10), in: Capsule())
            }

            Text(primaryPartnerMessage(for: partner, hasCheckedIn: hasCheckedIn))
                .font(ClimbTypography.sans(15, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                AccountabilityMetric(value: "\(sharedStreak(for: partner)) days", label: "Shared streak")
                AccountabilityMetric(value: weeklyCompletionText(for: partner), label: "Last 7 days")
                AccountabilityMetric(value: partner.lastCheckIn, label: "Last check-in")
            }

            PrimaryActionButton(
                title: hasCheckedIn ? "Checked in today" : "Check in now",
                systemImage: hasCheckedIn ? "checkmark.circle.fill" : "checkmark.message.fill",
                isDisabled: hasCheckedIn || isPending
            ) {
                Task {
                    await viewModel.checkIn(with: partner.id)
                    await MainActor.run {
                        checkedInPartnerID = partner.id
                        showFeedback("Checked in with \(partner.name)")
                    }
                }
            }
        }
    }

    private var inviteFriendStrip: some View {
        ClimbCard(padding: 15, cornerRadius: 22) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(ClimbTypography.sans(16, weight: .semibold))
                    .foregroundStyle(Color.climbSage)
                    .frame(width: 36, height: 36)
                    .background(Color.climbSage.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite a friend")
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Start another accountability pair.")
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        showOrCreatePartnerInvite()
                    } label: {
                        Label(isCreatingPartnerInvite ? "Creating" : "Invite", systemImage: "person.badge.plus")
                            .font(ClimbTypography.sans(13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(Color.climbBackground)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(Color.climbAction, in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isCreatingPartnerInvite)

                    Button {
                        showAcceptPartnerInvite = true
                    } label: {
                        Label("Enter", systemImage: "number")
                            .font(ClimbTypography.sans(13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(Color.climbTextSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.climbSurfaceRaised, in: Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }

    private var viewAllPartnersLink: some View {
        NavigationLink {
            PartnersListView(viewModel: viewModel, onFeedback: showFeedback)
        } label: {
            HStack(spacing: 12) {
                MiniAvatarStack(partners: Array(viewModel.partners.prefix(3)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("View all partners")
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(partnerStatusSummary)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
            }
            .padding(14)
            .background(Color.climbSurfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var secondaryCommunityLinks: some View {
        ClimbCard(padding: 18, cornerRadius: 22) {
            SectionTitle(title: "More community", subtitle: "Secondary tools when you need them")

            VStack(spacing: 0) {
                NavigationLink {
                    GlobalLeaderboardView(viewModel: viewModel)
                } label: {
                    CommunityDestinationRow(
                        title: "Global leaderboard",
                        subtitle: "\(userRankText) current rank",
                        systemImage: "trophy.fill",
                        tint: .climbGold
                    )
                }
                .buttonStyle(.plain)

                Divider().overlay(Color.climbDivider)

                NavigationLink {
                    GroupsBrowserView(viewModel: viewModel, onFeedback: showFeedback)
                } label: {
                    CommunityDestinationRow(
                        title: "Groups",
                        subtitle: "\(joinedGroupCount) joined",
                        systemImage: "person.3.fill",
                        tint: .climbBlue
                    )
                }
                .buttonStyle(.plain)

                Divider().overlay(Color.climbDivider)

                NavigationLink {
                    CommunityFeedView(viewModel: viewModel, onFeedback: showFeedback)
                } label: {
                    CommunityDestinationRow(
                        title: "Encouragement feed",
                        subtitle: "\(viewModel.visiblePosts.count) recent posts",
                        systemImage: "text.bubble.fill",
                        tint: .climbSage
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var composeCard: some View {
        ClimbCard {
            SectionTitle(title: "Encouragement")
            TextField("Share an honest win or encouragement", text: $newPost, axis: .vertical)
                .lineLimit(2...5)
                .formFieldStyle()
                .focused($isComposeFocused)
            PrimaryActionButton(
                title: isPosting ? "Posting" : "Post",
                systemImage: isPosting ? "clock" : "paperplane.fill",
                isDisabled: trimmedPost.isEmpty || isPosting
            ) {
                submitPost()
            }
        }
    }

    private var partnerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Today's Partner", subtitle: "Keep the action personal")
            if viewModel.partners.isEmpty {
                EmptyState(title: "No partners yet", detail: "Invite someone you trust. Partner activity appears here after they join.", systemImage: "person.2")
            } else if let featuredPartner = viewModel.partners.first {
                featuredPartnerCard(featuredPartner)
                
                if viewModel.partners.count > 1 {
                    Button {
                        selectedPartner = viewModel.partners[1]
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(Color.climbGreen)
                            Text("\(viewModel.partners.count - 1) more partner")
                                .font(ClimbTypography.sans(13, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(ClimbTypography.sans(12, weight: .semibold))
                                .foregroundStyle(Color.climbMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.climbSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }

    private func featuredPartnerCard(_ partner: AccountabilityPartner) -> some View {
        ClimbCard(padding: 18, cornerRadius: 22) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.climbGreen.opacity(0.16))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String(partner.name.prefix(1)))
                            .font(ClimbTypography.sans(17, weight: .semibold))
                            .foregroundStyle(Color.climbGreen)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(partner.name)
                        .font(ClimbTypography.sans(19, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(partner.focus.shortLabel) partner - \(partner.lastCheckIn)")
                        .font(ClimbTypography.sans(13, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                }
                
                Spacer(minLength: 0)
                
                Button {
                    selectedPartner = partner
                } label: {
                    Image(systemName: "chevron.right")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                        .frame(width: 36, height: 36)
                        .background(Color.climbSurfaceRaised, in: Circle())
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Open \(partner.name) accountability details")
            }

            Text(partner.lastInteraction)
                .font(ClimbTypography.sans(14, weight: .medium))
                .foregroundStyle(Color.climbTextSecondary)
                .lineLimit(2)

            HStack(spacing: 10) {
                Button {
                    Task {
                        await viewModel.checkIn(with: partner.id)
                        showFeedback("Checked in with \(partner.name)")
                    }
                } label: {
                    Label("Check in", systemImage: "checkmark.message.fill")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(Color.climbBackground)
                        .background(Color.climbGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    Task {
                        await viewModel.nudgePartner(partner.id)
                        showFeedback("Nudged \(partner.name)")
                    }
                } label: {
                    Image(systemName: "bell.fill")
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(Color.climbGreen)
                        .frame(width: 48, height: 48)
                        .background(Color.climbGreen.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Nudge \(partner.name)")
            }
        }
    }

    private func compactPartnerRow(_ partner: AccountabilityPartner) -> some View {
        ClimbCard(padding: 14, cornerRadius: 18) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.climbGreen.opacity(0.14))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(String(partner.name.prefix(1)))
                            .font(ClimbTypography.sans(14, weight: .semibold))
                            .foregroundStyle(Color.climbGreen)
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(partner.name)
                        .font(ClimbTypography.sans(16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(partner.lastInteraction)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                Button {
                    Task {
                        await viewModel.checkIn(with: partner.id)
                        showFeedback("Checked in with \(partner.name)")
                    }
                } label: {
                    Image(systemName: "checkmark.message.fill")
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(Color.climbBackground)
                        .frame(width: 36, height: 36)
                        .background(Color.climbGreen, in: Circle())
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Check in with \(partner.name)")
                
                Button {
                    selectedPartner = partner
                } label: {
                    Image(systemName: "chevron.right")
                        .font(ClimbTypography.sans(13, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                        .frame(width: 34, height: 34)
                        .background(Color.climbSurfaceRaised, in: Circle())
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Open \(partner.name) accountability details")
            }
        }
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Groups")
            if viewModel.groups.isEmpty {
                EmptyState(title: "No groups yet", detail: "Groups will appear when real community circles are available.", systemImage: "person.3")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.groups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "person.3.fill")
                                    .font(ClimbTypography.sans(20, weight: .semibold))
                                    .foregroundStyle(Color.climbGreen)
                                Text(group.name)
                                    .font(ClimbTypography.sans(17, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(group.subtitle)
                                    .font(ClimbTypography.sans(13))
                                    .foregroundStyle(Color.climbTextSecondary)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                HStack {
                                    Text("\(group.members) members")
                                    Spacer()
                                    Text(group.activeChallenge)
                                }
                                .font(ClimbTypography.sans(12, weight: .semibold))
                                .foregroundStyle(Color.climbMuted)

                                Button {
                                    Task {
                                        let joined = await viewModel.joinGroup(group.id)
                                        await MainActor.run {
                                            if joined, !group.isJoined {
                                                showFeedback("Joined \(group.name)")
                                            } else if !joined {
                                                showFeedback("Unable to join group")
                                            }
                                        }
                                    }
                                } label: {
                                    Label(group.isJoined ? "Joined" : "Join Group", systemImage: group.isJoined ? "checkmark.circle.fill" : "plus.circle")
                                        .font(ClimbTypography.sans(13, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .foregroundStyle(group.isJoined ? Color.climbGreen : Color.climbBackground)
                                .background(group.isJoined ? Color.climbGreen.opacity(0.14) : Color.climbGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .frame(width: 230, alignment: .topLeading)
                            .frame(minHeight: 150, alignment: .topLeading)
                            .padding(18)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .background(Color.climbSurfaceGlass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Feed")
            if viewModel.visiblePosts.isEmpty {
                EmptyState(title: "No encouragement yet", detail: "Recent community encouragement appears here after someone posts.", systemImage: "text.bubble")
            } else {
                ForEach(viewModel.visiblePosts) { post in
                    CommunityPostCard(
                        post: post,
                        canDelete: viewModel.isOwnPost(post),
                        canBlock: !viewModel.isOwnPost(post),
                        onAmen: {
                            Task {
                                await viewModel.addAmen(to: post.id)
                                showFeedback("Amen added")
                            }
                        },
                        onReport: {
                            Task {
                                let didReport = await viewModel.reportPost(post.id, reason: "Inappropriate or unsafe content")
                                showFeedback(didReport ? "Post reported" : "Unable to report post")
                            }
                        },
                        onBlock: {
                            Task {
                                let didBlock = await viewModel.blockUser(post.authorID)
                                showFeedback(didBlock ? "\(post.author) blocked" : "Unable to block user")
                            }
                        },
                        onDelete: {
                            Task {
                                let didDelete = await viewModel.deletePost(post.id)
                                showFeedback(didDelete ? "Post deleted" : "Unable to delete post")
                            }
                        }
                    )
                }
            }
        }
    }

    private var globalLeaderboardSection: some View {
        ClimbCard(padding: 20, cornerRadius: 22) {
            HStack(alignment: .top) {
                SectionTitle(title: "Global Leaderboard", subtitle: "OVR and streak consistency")
                Spacer()
                NavigationLink {
                    GlobalLeaderboardView(viewModel: viewModel)
                } label: {
                    Label("View all", systemImage: "chevron.right")
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .foregroundStyle(Color.climbGreen)
                }
                .buttonStyle(.plain)
            }

            if viewModel.leaderboard.isEmpty {
                Text("Global ranks appear after your profile is created.")
                    .font(ClimbTypography.sans(14))
                    .foregroundStyle(Color.climbTextSecondary)
            } else {
                ForEach(Array(sortedLeaderboard.prefix(5).enumerated()), id: \.element.id) { index, entry in
                    LeaderboardRow(
                        rank: index + 1,
                        entry: entry,
                        isCurrentUser: entry.id == viewModel.profile?.id
                    )
                    if index < min(sortedLeaderboard.count, 5) - 1 {
                        Divider().overlay(Color.climbDivider)
                    }
                }
            }
        }
    }

    private func showFeedback(_ message: String) {
        withAnimation(ClimbMotion.quick) {
            feedbackMessage = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                withAnimation(ClimbMotion.quick) {
                    feedbackMessage = nil
                }
            }
        }
    }

    private var trimmedPost: String {
        newPost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var primaryPartner: AccountabilityPartner? {
        viewModel.partners.first { !$0.isPending }
    }

    private var currentPartnerInviteCode: String? {
        inviteCode
            ?? viewModel.latestPartnerInviteCode
            ?? viewModel.partners.first(where: { $0.isPending })?.inviteCode
    }

    private var sortedLeaderboard: [LeaderboardEntry] {
        viewModel.leaderboard.sortedForGlobalRank
    }

    private var userRankText: String {
        guard let profileID = viewModel.profile?.id,
              let index = sortedLeaderboard.firstIndex(where: { $0.id == profileID }) else {
            return "--"
        }
        return "#\(index + 1)"
    }

    private var joinedGroupCount: Int {
        viewModel.groups.filter(\.isJoined).count
    }

    private func inviteMessage(code: String) -> String {
        PartnerInviteShare.message(for: code)
    }

    private var partnerStatusSummary: String {
        guard !viewModel.partners.isEmpty else { return "No partners yet" }
        let activeCount = viewModel.partners.filter { !$0.isPending && ($0.lastCheckIn == "Just now" || $0.lastCheckIn == "Today") }.count
        let pendingCount = viewModel.partners.filter(\.isPending).count
        if pendingCount > 0 {
            return "\(activeCount) active today - \(pendingCount) pending"
        }
        return "\(activeCount) active today - \(viewModel.partners.count) total"
    }

    private func sharedStreak(for partner: AccountabilityPartner) -> Int {
        partner.isPending ? 0 : partner.sharedStreak
    }

    private func weeklyCompletionText(for partner: AccountabilityPartner) -> String {
        "\(partner.weeklyCompletions)/7"
    }

    private func primaryPartnerMessage(for partner: AccountabilityPartner, hasCheckedIn: Bool) -> String {
        if partner.isPending, let code = partner.inviteCode {
            return "Share code \(code). This becomes active when your friend accepts it."
        }
        if hasCheckedIn {
            return "You checked in. Keep the shared streak alive tomorrow."
        }
        return "Don't leave \(partner.name) waiting. One honest check-in keeps the pressure personal."
    }

    private func createPartnerInvite() {
        guard !isCreatingPartnerInvite else { return }
        isCreatingPartnerInvite = true
        Task {
            let code = await viewModel.createPartnerInvite()
            await MainActor.run {
                isCreatingPartnerInvite = false
                if let code {
                    inviteCode = code
                    partnerInviteShare = PartnerInviteShare(code: code)
                } else {
                    showFeedback("Unable to create invite")
                }
            }
        }
    }

    private func showOrCreatePartnerInvite() {
        if let code = currentPartnerInviteCode {
            partnerInviteShare = PartnerInviteShare(code: code)
        } else {
            createPartnerInvite()
        }
    }

    private func submitPost() {
        let body = trimmedPost
        guard !body.isEmpty, !isPosting else { return }
        isPosting = true
        isComposeFocused = false

        Task {
            let didPost = await viewModel.addEncouragementPost(body)
            await MainActor.run {
                isPosting = false
                switch didPost {
                case .posted:
                    newPost = ""
                    showFeedback("Posted to the feed")
                case .rejected(let reason):
                    showFeedback(reason)
                }
            }
        }
    }
}

private struct AccountabilityMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ClimbTypography.sans(16, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.climbSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct MiniAvatarStack: View {
    let partners: [AccountabilityPartner]

    var body: some View {
        ZStack {
            ForEach(Array(partners.enumerated()), id: \.element.id) { index, partner in
                Circle()
                    .fill(Color.climbSurfaceRaised)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(partner.name.prefix(1)))
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .foregroundStyle(Color.climbGreen)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.climbBackground, lineWidth: 2)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(partner.lastCheckIn == "Just now" || partner.lastCheckIn == "Today" ? Color.climbGreen : Color.climbMuted)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.climbBackground, lineWidth: 1))
                    }
                    .offset(x: CGFloat(index) * 18)
            }
        }
        .frame(width: 68, height: 34, alignment: .leading)
    }
}

private struct CommunityDestinationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(ClimbTypography.sans(12, weight: .semibold))
                .foregroundStyle(Color.climbMuted)
        }
        .padding(.vertical, 12)
    }
}

private struct CommunityPostCard: View {
    let post: EncouragementPost
    let canDelete: Bool
    let canBlock: Bool
    let onAmen: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ClimbCard(cornerRadius: 28) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.author)
                        .font(ClimbTypography.sans(16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(post.createdAt, style: .relative)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbMuted)
                }

                Spacer(minLength: 0)

                Menu {
                    if canDelete {
                        Button("Delete my post", role: .destructive, action: onDelete)
                    }
                    if canBlock {
                        Button("Report post", role: .destructive, action: onReport)
                        Button("Block user", role: .destructive, action: onBlock)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                        .frame(width: 34, height: 34)
                        .background(Color.climbSurfaceRaised, in: Circle())
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Post safety options")
            }

            Text(post.body)
                .font(ClimbTypography.sans(15))
                .foregroundStyle(Color.climbTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAmen) {
                Label("\(post.amenCount) Amen", systemImage: "hands.clap")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.climbGreen.opacity(0.12), in: Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }
}

private struct CommunitySummaryMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ClimbTypography.sans(18, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(ClimbTypography.sans(11, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct CommunityStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(ClimbTypography.sans(20, weight: .semibold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(ClimbTypography.sans(11, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.climbSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct PartnerActivityChip: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(ClimbTypography.sans(13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(ClimbTypography.sans(11, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.climbSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PartnerMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(ClimbTypography.sans(17, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .semibold))
                .foregroundStyle(Color.climbTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.climbSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PartnersListView: View {
    @ObservedObject var viewModel: AppViewModel
    let onFeedback: (String) -> Void
    @State private var selectedPartner: AccountabilityPartner?
    @State private var showAcceptInvite = false
    @State private var inviteCode: String?
    @State private var partnerInviteShare: PartnerInviteShare?
    @State private var isCreatingInvite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Status dots show who has checked in today.")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .padding(.horizontal, 2)

                ClimbCard(padding: 16, cornerRadius: 26) {
                    HStack(spacing: 10) {
                        PrimaryActionButton(
                            title: isCreatingInvite ? "Creating" : (currentPartnerInviteCode == nil ? "Create Invite" : "View Invite"),
                            systemImage: "person.badge.plus",
                            isDisabled: isCreatingInvite
                        ) {
                            showOrCreateInvite()
                        }
                        SecondaryActionButton(title: "Enter Code", systemImage: "number") {
                            showAcceptInvite = true
                        }
                    }
                    if currentPartnerInviteCode != nil {
                        Text("Your invite is ready. Tap View Invite to copy it or share the join link.")
                            .font(ClimbTypography.sans(13, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if activePartners.isEmpty {
                    EmptyState(title: "No active partners yet", detail: "Create an invite or enter a code from someone you trust.", systemImage: "person.badge.plus")
                } else {
                    ForEach(activePartners) { partner in
                        ClimbCard(padding: 17, cornerRadius: 26) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.climbGreen.opacity(0.14))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Text(String(partner.name.prefix(1)))
                                            .font(ClimbTypography.sans(16, weight: .semibold))
                                            .foregroundStyle(Color.climbGreen)
                                    )
                                    .overlay(alignment: .bottomTrailing) {
                                        Circle()
                                            .fill(partner.lastCheckIn == "Just now" || partner.lastCheckIn == "Today" ? Color.climbGreen : Color.climbMuted)
                                            .frame(width: 10, height: 10)
                                            .overlay(Circle().stroke(Color.climbSurfaceRaised, lineWidth: 2))
                                    }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(partner.name)
                                        .font(ClimbTypography.sans(17, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text(partner.isPending ? "Waiting for invite acceptance" : "\(partner.focus.shortLabel) partner - \(partner.lastCheckIn)")
                                        .font(ClimbTypography.sans(12, weight: .medium))
                                        .foregroundStyle(Color.climbTextSecondary)
                                }

                                Spacer(minLength: 0)

                                Button {
                                    selectedPartner = partner
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(ClimbTypography.sans(13, weight: .semibold))
                                        .foregroundStyle(Color.climbMuted)
                                        .frame(width: 34, height: 34)
                                        .background(Color.climbSurface, in: Circle())
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }

                            HStack(spacing: 8) {
                                PartnerActivityChip(value: "\(partner.checkInCount)", label: "checks")
                                PartnerActivityChip(value: "\(partner.nudgeCount)", label: "nudges")
                                PartnerActivityChip(value: "\(partner.encouragementCount)", label: "sent")
                            }

                            PrimaryActionButton(title: "Check in", systemImage: "checkmark.message.fill") {
                                Task {
                                    await viewModel.checkIn(with: partner.id)
                                    await MainActor.run {
                                        onFeedback("Checked in with \(partner.name)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(ClimbScreenBackground())
        .navigationTitle("Partners")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $selectedPartner) { partner in
            PartnerDetailSheet(viewModel: viewModel, partnerID: partner.id, onFeedback: onFeedback)
        }
        .sheet(isPresented: $showAcceptInvite) {
            AcceptPartnerInviteSheet(viewModel: viewModel, onFeedback: onFeedback)
                .presentationDetents([.medium])
        }
        .sheet(item: $partnerInviteShare) { invite in
            PartnerInviteShareSheet(invite: invite, onFeedback: onFeedback)
                .presentationDetents([.medium])
        }
        .task {
            await viewModel.refreshAccountabilityPartners()
        }
    }

    private var activePartners: [AccountabilityPartner] {
        viewModel.partners.filter { !$0.isPending }
    }

    private var currentPartnerInviteCode: String? {
        inviteCode
            ?? viewModel.latestPartnerInviteCode
            ?? viewModel.partners.first(where: { $0.isPending })?.inviteCode
    }

    private func createInvite() {
        guard !isCreatingInvite else { return }
        isCreatingInvite = true
        Task {
            let code = await viewModel.createPartnerInvite()
            await MainActor.run {
                isCreatingInvite = false
                if let code {
                    inviteCode = code
                    partnerInviteShare = PartnerInviteShare(code: code)
                } else {
                    onFeedback("Unable to create invite")
                }
            }
        }
    }

    private func showOrCreateInvite() {
        if let code = currentPartnerInviteCode {
            partnerInviteShare = PartnerInviteShare(code: code)
        } else {
            createInvite()
        }
    }

    private func inviteMessage(code: String) -> String {
        PartnerInviteShare.message(for: code)
    }
}

private struct PartnerInviteShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let invite: PartnerInviteShare
    let onFeedback: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                ClimbScreenBackground()

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Invite partner")
                            .font(ClimbTypography.sans(29, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Send this to one person you trust. Code entry connects inside the app; the link is a shareable invite page.")
                            .font(ClimbTypography.sans(14, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(3)
                    }

                    ClimbCard(padding: 22, cornerRadius: 28, isProminent: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Invite code")
                                .font(ClimbTypography.sans(12, weight: .semibold))
                                .foregroundStyle(Color.climbMuted)
                                .tracking(1.1)
                                .textCase(.uppercase)

                            Text(invite.code)
                                .font(.system(size: 38, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.climbMist)
                                .lineLimit(1)
                                .minimumScaleFactor(0.58)
                                .allowsTightening(true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }

                        Text(invite.joinLink)
                            .font(ClimbTypography.sans(12, weight: .semibold))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .truncationMode(.middle)
                    }

                    ShareLink(item: invite.message, subject: Text("Join my accountability pair")) {
                        Label("Share Link + Code", systemImage: "square.and.arrow.up")
                            .font(ClimbTypography.sans(17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .foregroundStyle(Color.climbBackground)
                            .background(Color.climbAction, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())

                    SecondaryActionButton(title: "Copy Code", systemImage: "doc.on.doc") {
                        copyCode()
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("Partner Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.climbGreen)
                }
            }
        }
    }

    private func copyCode() {
        #if os(iOS)
        UIPasteboard.general.string = invite.code
        #endif
        HapticFeedback.selection()
        onFeedback("Invite code copied")
    }
}

private struct AcceptPartnerInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    let onFeedback: (String) -> Void
    @State private var code = ""
    @State private var isAccepting = false

    private var normalizedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ClimbScreenBackground()
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Accept invite")
                            .font(ClimbTypography.sans(28, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Enter the code your friend shared. Codes connect inside the app even when the invite link opens the web page.")
                            .font(ClimbTypography.sans(14, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(3)
                    }

                    ClimbCard(padding: 20, cornerRadius: 28) {
                        TextField("Invite code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .formFieldStyle()

                        PrimaryActionButton(
                            title: isAccepting ? "Connecting" : "Connect Partner",
                            systemImage: "person.2.fill",
                            isDisabled: normalizedCode.count < 4 || isAccepting
                        ) {
                            acceptInvite()
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("Invite Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func acceptInvite() {
        guard !isAccepting else { return }
        isAccepting = true
        Task {
            let didAccept = await viewModel.acceptPartnerInvite(code: normalizedCode)
            await MainActor.run {
                isAccepting = false
                onFeedback(didAccept ? "Partner connected" : "Invite code did not work")
                if didAccept {
                    dismiss()
                }
            }
        }
    }
}

private struct GroupsBrowserView: View {
    @ObservedObject var viewModel: AppViewModel
    let onFeedback: (String) -> Void
    @State private var showCreateGroup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create a real circle or join one someone else has made.")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .padding(.horizontal, 2)

                GroupsSummaryCard(groups: viewModel.groups)

                PrimaryActionButton(title: "Create Group", systemImage: "person.3.fill") {
                    showCreateGroup = true
                }

                if viewModel.groups.isEmpty {
                    EmptyState(title: "No groups yet", detail: "Create the first circle when you are ready to make accountability shared.", systemImage: "person.3")
                } else {
                    ForEach(viewModel.groups) { group in
                        GroupCard(
                            group: group,
                            currentUserID: viewModel.profile?.id,
                            destination: GroupDetailView(
                                viewModel: viewModel,
                                groupID: group.id,
                                onFeedback: onFeedback
                            ),
                            onJoinLeave: {
                                Task {
                                    if group.isJoined {
                                        let left = await viewModel.leaveGroup(group.id)
                                        await MainActor.run {
                                            onFeedback(left ? "Left \(group.name)" : "Unable to leave group")
                                        }
                                    } else {
                                        let joined = await viewModel.joinGroup(group.id)
                                        await MainActor.run {
                                            onFeedback(joined ? "Joined \(group.name)" : "Unable to join group")
                                        }
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.refreshCommunityGroups()
        }
        .task {
            await viewModel.refreshCommunityGroups()
        }
        .background(ClimbScreenBackground())
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.isRefreshingGroups {
                    SwiftUI.ProgressView()
                        .tint(.climbSage)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateGroup = true
                } label: {
                    Image(systemName: "plus")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                }
                .accessibilityLabel("Create group")
            }
        }
        .sheet(isPresented: $showCreateGroup) {
            CreateGroupSheet(viewModel: viewModel, onFeedback: onFeedback)
                .presentationDetents([.large])
        }
    }
}

private struct GroupsSummaryCard: View {
    let groups: [ClimbGroup]

    private var joinedCount: Int {
        groups.filter(\.isJoined).count
    }

    private var memberCount: Int {
        groups.filter(\.isJoined).map(\.members).reduce(0, +)
    }

    var body: some View {
        ClimbCard(padding: 18, cornerRadius: 22, isProminent: true) {
            SectionTitle(title: "Your circles", subtitle: joinedCount == 0 ? "Join one group to start building shared pressure." : "Stay visible where you joined.")

            HStack(spacing: 10) {
                CommunitySummaryMetric(title: "Joined", value: "\(joinedCount)", tint: .climbBlue)
                CommunitySummaryMetric(title: "People", value: "\(memberCount)", tint: .climbSage)
                CommunitySummaryMetric(title: "Open", value: "\(max(0, groups.count - joinedCount))", tint: .climbGold)
            }
        }
    }
}

private struct GroupCard<Destination: View>: View {
    let group: ClimbGroup
    let currentUserID: String?
    let destination: Destination
    let onJoinLeave: () -> Void

    private var roleText: String {
        if group.isOwner(currentUserID) { return "Owner" }
        if group.isAdmin(currentUserID) { return "Admin" }
        if group.isJoined { return "Joined" }
        return "Open"
    }

    private var roleColor: Color {
        if group.isOwner(currentUserID) || group.isAdmin(currentUserID) { return .climbBlue }
        return group.isJoined ? .climbSage : .climbGold
    }

    var body: some View {
        ClimbCard(padding: 20, cornerRadius: 22) {
            NavigationLink {
                destination
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: group.isJoined ? "checkmark.seal.fill" : "person.3.fill")
                        .font(ClimbTypography.sans(18, weight: .semibold))
                        .foregroundStyle(group.isJoined ? Color.climbSage : Color.climbBlue)
                        .frame(width: 42, height: 42)
                        .background((group.isJoined ? Color.climbSage : Color.climbBlue).opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(group.name)
                                .font(ClimbTypography.sans(18, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            StatusBadge(text: roleText, color: roleColor)
                        }
                        Text(group.subtitle)
                            .font(ClimbTypography.sans(13, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    GroupStatPill(text: "\(group.members) members", systemImage: "person.2.fill", color: .climbBlue)
                    GroupStatPill(text: group.isJoined ? "Active" : "Joinable", systemImage: group.isJoined ? "checkmark.circle.fill" : "plus.circle", color: group.isJoined ? .climbSage : .climbGold)
                }
                Label(group.activeChallenge, systemImage: "flag.fill")
                    .font(ClimbTypography.sans(13, weight: .semibold))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            if group.isOwner(currentUserID) {
                NavigationLink {
                    destination
                } label: {
                    Label("Manage Group", systemImage: "slider.horizontal.3")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(ScaleButtonStyle())
                .foregroundStyle(Color.climbBackground)
                .background(Color.climbAction)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Button(action: onJoinLeave) {
                    Label(group.isJoined ? "Leave Group" : "Join Group", systemImage: group.isJoined ? "xmark.circle" : "plus.circle")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(ScaleButtonStyle())
                .foregroundStyle(group.isJoined ? Color.climbRed : Color.climbBackground)
                .background(group.isJoined ? Color.climbRed.opacity(0.12) : Color.climbAction)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(group.isJoined ? Color.climbRed.opacity(0.22) : Color.clear, lineWidth: 1)
                )
            }
        }
    }
}

private struct GroupStatPill: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(ClimbTypography.sans(12, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(color.opacity(0.09), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.16), lineWidth: 0.8))
    }
}

private struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    let groupID: String
    let onFeedback: (String) -> Void
    @State private var showEditGroup = false
    @State private var showDeleteConfirmation = false

    private var group: ClimbGroup? {
        viewModel.groups.first { $0.id == groupID }
    }

    private var currentUserID: String? {
        viewModel.profile?.id
    }

    var body: some View {
        ScrollView {
            if let group {
                let isAdmin = group.isAdmin(currentUserID)
                VStack(alignment: .leading, spacing: 14) {
                    ClimbCard(padding: 24, cornerRadius: 24, isProminent: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            StatusBadge(
                                text: isAdmin ? "Admin" : (group.isJoined ? "Joined" : "Open group"),
                                color: isAdmin ? .climbBlue : (group.isJoined ? .climbSage : .climbGold)
                            )
                            Text(group.name)
                                .font(ClimbTypography.sans(31, weight: .semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(group.subtitle)
                                .font(ClimbTypography.sans(15, weight: .medium))
                                .foregroundStyle(Color.climbTextSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                GroupStatPill(text: "\(group.members) members", systemImage: "person.2.fill", color: .climbBlue)
                                GroupStatPill(text: isAdmin ? "Can manage" : (group.isJoined ? "Can post" : "View only"), systemImage: isAdmin ? "slider.horizontal.3" : "text.bubble.fill", color: isAdmin ? .climbBlue : .climbSage)
                            }
                        }
                    }

                    ClimbCard(padding: 20, cornerRadius: 22) {
                        SectionTitle(title: "Shared focus", subtitle: "Small shared pressure for this week.")
                        HStack(spacing: 12) {
                            Image(systemName: "flag.fill")
                                .font(ClimbTypography.sans(18, weight: .semibold))
                                .foregroundStyle(Color.climbWarm)
                                .frame(width: 42, height: 42)
                                .background(Color.climbWarm.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.activeChallenge)
                                    .font(ClimbTypography.sans(18, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("\(group.members) people in this circle")
                                    .font(ClimbTypography.sans(13, weight: .medium))
                                    .foregroundStyle(Color.climbTextSecondary)
                            }
                        }
                    }

                    if group.isJoined {
                        GroupMembersCard(
                            group: group,
                            currentUserID: currentUserID,
                            isAdmin: isAdmin,
                            onSetAdmin: { memberID, shouldBeAdmin in
                                Task {
                                    let updated = await viewModel.setGroupAdmin(
                                        groupID: group.id,
                                        memberID: memberID,
                                        isAdmin: shouldBeAdmin
                                    )
                                    await MainActor.run {
                                        onFeedback(updated ? (shouldBeAdmin ? "Admin added" : "Admin removed") : "Unable to update admin")
                                    }
                                }
                            },
                            onRemove: { memberID in
                                Task {
                                    let removed = await viewModel.removeGroupMember(groupID: group.id, memberID: memberID)
                                    await MainActor.run {
                                        onFeedback(removed ? "Member removed" : "Unable to remove member")
                                    }
                                }
                            }
                        )
                    }

                    ClimbCard(padding: 20, cornerRadius: 22) {
                        SectionTitle(title: "Group actions", subtitle: group.isJoined ? "Show up inside the circle today." : "Join before you can check in.")

                        PrimaryActionButton(
                            title: group.isJoined ? "Post Group Check-In" : "Join Group",
                            systemImage: group.isJoined ? "checkmark.message.fill" : "plus.circle.fill"
                        ) {
                            Task {
                                if group.isJoined {
                                    let didPost = await viewModel.checkInWithGroup(group.id)
                                    await MainActor.run {
                                        onFeedback(didPost ? "Group check-in posted" : "Unable to check in")
                                    }
                                } else {
                                    let joined = await viewModel.joinGroup(group.id)
                                    await MainActor.run {
                                        onFeedback(joined ? "Joined \(group.name)" : "Unable to join group")
                                    }
                                }
                            }
                        }

                        if group.isJoined, !group.isOwner(currentUserID) {
                            SecondaryActionButton(title: "Leave Group", systemImage: "xmark.circle", role: .destructive) {
                                Task {
                                    let left = await viewModel.leaveGroup(group.id)
                                    await MainActor.run {
                                        onFeedback(left ? "Left \(group.name)" : "Unable to leave group")
                                    }
                                }
                            }
                        }
                    }

                    if isAdmin {
                        ClimbCard(padding: 20, cornerRadius: 22) {
                            SectionTitle(title: "Admin tools", subtitle: "Manage the circle without adding noise.")
                            SecondaryActionButton(title: "Edit Group", systemImage: "slider.horizontal.3") {
                                showEditGroup = true
                            }
                            SecondaryActionButton(title: "Delete Group", systemImage: "trash", role: .destructive) {
                                showDeleteConfirmation = true
                            }
                        }
                    }

                    EmptyState(
                        title: group.isJoined ? "Group posts appear in the feed" : "Join to participate",
                        detail: group.isJoined ? "Your group check-ins and encouragement posts are visible in the community feed." : "Join this group to make the shared focus part of your community rhythm.",
                        systemImage: group.isJoined ? "text.bubble" : "person.badge.plus"
                    )
                }
            } else {
                EmptyState(title: "Group unavailable", detail: "This group could not be found.", systemImage: "person.3.sequence")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 18)
        }
        .scrollIndicators(.hidden)
        .background(ClimbScreenBackground())
        .navigationTitle(group?.name ?? "Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .overlay(alignment: .top) {
            Color.clear
        }
        .sheet(isPresented: $showEditGroup) {
            if let group {
                EditGroupSheet(viewModel: viewModel, group: group, onFeedback: onFeedback)
                    .presentationDetents([.large])
            }
        }
        .alert("Delete group?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    let deleted = await viewModel.deleteGroup(groupID)
                    await MainActor.run {
                        onFeedback(deleted ? "Group deleted" : "Unable to delete group")
                        if deleted {
                            dismiss()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the group for everyone. This cannot be undone.")
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .contentMargins(.top, 12, for: .scrollContent)
    }
}

private struct GroupMembersCard: View {
    let group: ClimbGroup
    let currentUserID: String?
    let isAdmin: Bool
    let onSetAdmin: (String, Bool) -> Void
    let onRemove: (String) -> Void

    private var memberIDs: [String] {
        group.normalizedMemberIDs.sorted { first, second in
            if group.isOwner(first) { return true }
            if group.isOwner(second) { return false }
            if group.isAdmin(first), !group.isAdmin(second) { return true }
            if !group.isAdmin(first), group.isAdmin(second) { return false }
            return group.displayName(for: first).localizedCaseInsensitiveCompare(group.displayName(for: second)) == .orderedAscending
        }
    }

    var body: some View {
        ClimbCard(padding: 20, cornerRadius: 22) {
            SectionTitle(title: "Members", subtitle: isAdmin ? "Admins can manage roles and remove members." : "People climbing with this circle.")

            VStack(spacing: 0) {
                ForEach(memberIDs, id: \.self) { memberID in
                    GroupMemberRow(
                        group: group,
                        memberID: memberID,
                        currentUserID: currentUserID,
                        isCurrentUserAdmin: isAdmin,
                        onSetAdmin: onSetAdmin,
                        onRemove: onRemove
                    )
                    if memberID != memberIDs.last {
                        Divider().overlay(Color.climbDivider)
                    }
                }
            }
        }
    }
}

private struct GroupMemberRow: View {
    let group: ClimbGroup
    let memberID: String
    let currentUserID: String?
    let isCurrentUserAdmin: Bool
    let onSetAdmin: (String, Bool) -> Void
    let onRemove: (String) -> Void

    private var isSelf: Bool {
        currentUserID == memberID
    }

    private var roleText: String {
        if group.isOwner(memberID) {
            return "Owner"
        }
        if group.isAdmin(memberID) {
            return "Admin"
        }
        return "Member"
    }

    private var canManage: Bool {
        isCurrentUserAdmin && !isSelf && !group.isOwner(memberID)
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill((group.isAdmin(memberID) ? Color.climbBlue : Color.climbSage).opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay(
                    Text(String(group.displayName(for: memberID).prefix(1)))
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .foregroundStyle(group.isAdmin(memberID) ? Color.climbBlue : Color.climbAction)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(isSelf ? "\(group.displayName(for: memberID)) (You)" : group.displayName(for: memberID))
                    .font(ClimbTypography.sans(15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(roleText)
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }

            Spacer(minLength: 0)

            if canManage {
                Menu {
                    if group.isAdmin(memberID) {
                        Button("Remove Admin") {
                            onSetAdmin(memberID, false)
                        }
                    } else {
                        Button("Make Admin") {
                            onSetAdmin(memberID, true)
                        }
                    }
                    Button("Remove From Group", role: .destructive) {
                        onRemove(memberID)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(Color.climbMuted)
                        .frame(width: 36, height: 36)
                        .background(Color.climbSurfaceRaised, in: Circle())
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.vertical, 11)
    }
}

private struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    let onFeedback: (String) -> Void

    @State private var name = ""
    @State private var subtitle = ""
    @State private var challenge = ""

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !challenge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ClimbScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Create a group")
                                .font(ClimbTypography.sans(28, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Keep it small, honest, and action-focused.")
                                .font(ClimbTypography.sans(14, weight: .medium))
                                .foregroundStyle(Color.climbTextSecondary)
                                .lineSpacing(3)
                        }

                        ClimbCard(padding: 20, cornerRadius: 28) {
                            TextField("Group name", text: $name)
                                .formFieldStyle()
                            TextField("What is this circle for?", text: $subtitle, axis: .vertical)
                                .lineLimit(2...4)
                                .formFieldStyle()
                            TextField("Shared focus", text: $challenge)
                                .formFieldStyle()
                        }

                        PrimaryActionButton(title: "Create Group", systemImage: "person.3.fill", isDisabled: !canCreate) {
                            Task {
                                let created = await viewModel.createGroup(name: name, subtitle: subtitle, challenge: challenge)
                                await MainActor.run {
                                    if created {
                                        onFeedback("Group created")
                                        dismiss()
                                    } else {
                                        onFeedback("Add group details and try again")
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct EditGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    let group: ClimbGroup
    let onFeedback: (String) -> Void

    @State private var name: String
    @State private var subtitle: String
    @State private var challenge: String

    init(viewModel: AppViewModel, group: ClimbGroup, onFeedback: @escaping (String) -> Void) {
        self.viewModel = viewModel
        self.group = group
        self.onFeedback = onFeedback
        _name = State(initialValue: group.name)
        _subtitle = State(initialValue: group.subtitle)
        _challenge = State(initialValue: group.activeChallenge)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !challenge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ClimbScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Edit group")
                                .font(ClimbTypography.sans(28, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Keep the purpose clear and the shared focus specific.")
                                .font(ClimbTypography.sans(14, weight: .medium))
                                .foregroundStyle(Color.climbTextSecondary)
                                .lineSpacing(3)
                        }

                        ClimbCard(padding: 20, cornerRadius: 28) {
                            TextField("Group name", text: $name)
                                .formFieldStyle()
                            TextField("What is this circle for?", text: $subtitle, axis: .vertical)
                                .lineLimit(2...4)
                                .formFieldStyle()
                            TextField("Shared focus", text: $challenge)
                                .formFieldStyle()
                        }

                        PrimaryActionButton(title: "Save Changes", systemImage: "checkmark.circle.fill", isDisabled: !canSave) {
                            Task {
                                let saved = await viewModel.updateGroupDetails(
                                    groupID: group.id,
                                    name: name,
                                    subtitle: subtitle,
                                    challenge: challenge
                                )
                                await MainActor.run {
                                    onFeedback(saved ? "Group updated" : "Unable to update group")
                                    if saved {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct CommunityFeedView: View {
    @ObservedObject var viewModel: AppViewModel
    let onFeedback: (String) -> Void
    @State private var newPost = ""
    @State private var isPosting = false
    @FocusState private var isComposeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Text(viewModel.isRefreshingPosts ? "Refreshing shared encouragement..." : "Pull down or tap refresh to load recent community posts.")
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .padding(.horizontal, 2)

                    Spacer(minLength: 0)

                    if viewModel.isRefreshingPosts {
                        SwiftUI.ProgressView()
                            .tint(.climbSage)
                    }
                }

                ClimbCard(cornerRadius: 28) {
                    SectionTitle(title: "Encouragement")
                    TextField("Share an honest win or encouragement", text: $newPost, axis: .vertical)
                        .lineLimit(2...5)
                        .formFieldStyle()
                        .focused($isComposeFocused)
                    PrimaryActionButton(
                        title: isPosting ? "Posting" : "Post",
                        systemImage: isPosting ? "clock" : "paperplane.fill",
                        isDisabled: trimmedPost.isEmpty || isPosting
                    ) {
                        submitPost()
                    }
                }

                if viewModel.visiblePosts.isEmpty {
                    EmptyState(title: "No encouragement yet", detail: "Recent community encouragement appears here after someone posts.", systemImage: "text.bubble")
                } else {
                    ForEach(viewModel.visiblePosts) { post in
                        CommunityPostCard(
                            post: post,
                            canDelete: viewModel.isOwnPost(post),
                            canBlock: !viewModel.isOwnPost(post),
                            onAmen: {
                                Task {
                                    await viewModel.addAmen(to: post.id)
                                    await MainActor.run {
                                        onFeedback("Amen added")
                                    }
                                }
                            },
                            onReport: {
                                Task {
                                    let didReport = await viewModel.reportPost(post.id, reason: "Inappropriate or unsafe content")
                                    await MainActor.run {
                                        onFeedback(didReport ? "Post reported" : "Unable to report post")
                                    }
                                }
                            },
                            onBlock: {
                                Task {
                                    let didBlock = await viewModel.blockUser(post.authorID)
                                    await MainActor.run {
                                        onFeedback(didBlock ? "\(post.author) blocked" : "Unable to block user")
                                    }
                                }
                            },
                            onDelete: {
                                Task {
                                    let didDelete = await viewModel.deletePost(post.id)
                                    await MainActor.run {
                                        onFeedback(didDelete ? "Post deleted" : "Unable to delete post")
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.refreshCommunityFeed()
        }
        .task {
            await viewModel.refreshCommunityFeed()
        }
        .background(ClimbScreenBackground())
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.refreshCommunityFeed()
                    }
                } label: {
                    Image(systemName: viewModel.isRefreshingPosts ? "hourglass" : "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshingPosts)
                .foregroundStyle(Color.climbSage)
                .accessibilityLabel("Refresh encouragement feed")
            }
        }
    }

    private var trimmedPost: String {
        newPost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitPost() {
        let body = trimmedPost
        guard !body.isEmpty, !isPosting else { return }
        isPosting = true
        isComposeFocused = false

        Task {
            let didPost = await viewModel.addEncouragementPost(body)
            await MainActor.run {
                isPosting = false
                switch didPost {
                case .posted:
                    newPost = ""
                    onFeedback("Posted to the feed")
                case .rejected(let reason):
                    onFeedback(reason)
                }
            }
        }
    }
}

private struct PartnerDetailSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let partnerID: String
    let onFeedback: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var encouragementNote = "I am praying for your next right step today. Keep going."
    @State private var partnerInviteShare: PartnerInviteShare?

    private var partner: AccountabilityPartner? {
        viewModel.partners.first { $0.id == partnerID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let partner {
                    VStack(alignment: .leading, spacing: 16) {
                        ClimbCard(padding: 24, cornerRadius: 32, isProminent: true) {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(Color.climbGreen.opacity(0.16))
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Text(String(partner.name.prefix(1)))
                                            .font(ClimbTypography.sans(20, weight: .semibold))
                                            .foregroundStyle(Color.climbGreen)
                                    )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(partner.name)
                                        .font(ClimbTypography.sans(24, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("\(partner.focus.shortLabel) partner")
                                        .font(ClimbTypography.sans(13, weight: .semibold))
                                        .foregroundStyle(Color.climbTextSecondary)
                                }
                            }

                            Text(partner.lastInteraction)
                                .font(ClimbTypography.sans(14, weight: .medium))
                                .foregroundStyle(Color.climbTextSecondary)

                            HStack(spacing: 8) {
                                PartnerMetric(value: "\(partner.checkInCount)", label: "Check-ins")
                                PartnerMetric(value: "\(partner.nudgeCount)", label: "Nudges")
                                PartnerMetric(value: "\(partner.encouragementCount)", label: "Encouraged")
                            }
                        }

                        ClimbCard(padding: 22, cornerRadius: 28) {
                            SectionTitle(title: "Quick Actions")
                            if partner.isPending, let code = partner.inviteCode {
                                PrimaryActionButton(title: "View Invite Code", systemImage: "square.and.arrow.up") {
                                    partnerInviteShare = PartnerInviteShare(code: code)
                                }
                            } else {
                                PrimaryActionButton(title: "Check In", systemImage: "checkmark.message.fill") {
                                    Task {
                                        await viewModel.checkIn(with: partner.id)
                                        await MainActor.run {
                                            onFeedback("Checked in with \(partner.name)")
                                        }
                                    }
                                }
                                SecondaryActionButton(title: "Send Nudge", systemImage: "bell.fill") {
                                    Task {
                                        await viewModel.nudgePartner(partner.id)
                                        await MainActor.run {
                                            onFeedback("Nudged \(partner.name)")
                                        }
                                    }
                                }
                            }
                        }

                        if !partner.isPending {
                            ClimbCard(padding: 22, cornerRadius: 28) {
                                SectionTitle(title: "Encouragement")
                                TextField("Write encouragement", text: $encouragementNote, axis: .vertical)
                                    .lineLimit(3...6)
                                    .formFieldStyle()
                                PrimaryActionButton(
                                    title: "Send Encouragement",
                                    systemImage: "paperplane.fill",
                                    isDisabled: encouragementNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ) {
                                    Task {
                                        await viewModel.encouragePartner(partner.id, message: encouragementNote)
                                        await MainActor.run {
                                            encouragementNote = ""
                                            onFeedback("Encouraged \(partner.name)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                } else {
                    EmptyState(title: "Partner unavailable", detail: "This partner could not be found.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .padding(20)
                }
            }
            .scrollIndicators(.hidden)
            .background(ClimbScreenBackground())
            .navigationTitle("Partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.climbGreen)
                }
            }
            .sheet(item: $partnerInviteShare) { invite in
                PartnerInviteShareSheet(invite: invite, onFeedback: onFeedback)
                    .presentationDetents([.medium])
            }
        }
    }

    private func inviteMessage(code: String) -> String {
        PartnerInviteShare.message(for: code)
    }
}

private struct GlobalLeaderboardView: View {
    @ObservedObject var viewModel: AppViewModel

    private var entries: [LeaderboardEntry] {
        viewModel.leaderboard.sortedForGlobalRank
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text(viewModel.isRefreshingLeaderboard ? "Refreshing live rankings..." : "Pull down or tap refresh to update live rankings.")
                        .font(ClimbTypography.sans(14, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                        .padding(.horizontal, 2)

                    Spacer(minLength: 0)

                    if viewModel.isRefreshingLeaderboard {
                        SwiftUI.ProgressView()
                            .tint(.climbGreen)
                    }
                }

                ClimbCard(padding: 20, cornerRadius: 30, isProminent: true) {
                    if entries.isEmpty {
                        EmptyState(title: "No rankings yet", detail: "Complete missions to create your first leaderboard entry.", systemImage: "trophy")
                    } else {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(
                                rank: index + 1,
                                entry: entry,
                                isCurrentUser: entry.id == viewModel.profile?.id
                            )
                            if index < entries.count - 1 {
                                Divider().overlay(Color.climbDivider)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.refreshGlobalLeaderboard()
        }
        .task {
            await viewModel.refreshGlobalLeaderboard()
        }
        .background(ClimbScreenBackground())
        .navigationTitle("Global Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.refreshGlobalLeaderboard()
                    }
                } label: {
                    Image(systemName: viewModel.isRefreshingLeaderboard ? "hourglass" : "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshingLeaderboard)
                .foregroundStyle(Color.climbGreen)
                .accessibilityLabel("Refresh leaderboard")
            }
        }
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(ClimbTypography.sans(15, weight: .semibold))
                .foregroundStyle(rank == 1 ? Color.climbGold : Color.climbMuted)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(.white)
                    if isCurrentUser {
                        Text("You")
                            .font(ClimbTypography.sans(10, weight: .semibold))
                            .foregroundStyle(Color.climbBackground)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.climbGreen, in: Capsule())
                    }
                }
                Text("\(entry.streak) day streak")
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.ovrScore)")
                    .font(ClimbTypography.sans(17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("OVR")
                    .font(ClimbTypography.sans(10, weight: .semibold))
                    .foregroundStyle(Color.climbMuted)
            }
        }
        .padding(.vertical, 4)
    }
}
