import SwiftUI

struct CommunityView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var newPost = ""
    @State private var isPosting = false
    @State private var feedbackMessage: String?
    @State private var selectedPartner: AccountabilityPartner?
    @State private var checkedInPartnerID: String?
    @FocusState private var isComposeFocused: Bool

    var body: some View {
        ScreenContainer(title: "Community") {
            communityHeader
            if let feedbackMessage {
                StatusBadge(text: feedbackMessage, color: .climbGreen)
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
    }

    private var communityHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Accountability")
                .font(ClimbTypography.sans(13, weight: .bold))
                .foregroundStyle(Color.climbGreen)
                .tracking(1.3)
                .textCase(.uppercase)
            Text("Don’t climb unseen.")
                .font(ClimbTypography.sans(32, weight: .bold))
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
        if viewModel.partners.isEmpty {
            EmptyState(title: "No partner yet", detail: "Invite a friend or finish onboarding to start accountability.", systemImage: "person.2")
        } else if let partner = primaryPartner {
            primaryPartnerCard(partner)
        }
    }

    private func primaryPartnerCard(_ partner: AccountabilityPartner) -> some View {
        let hasCheckedIn = checkedInPartnerID == partner.id

        return ClimbCard(padding: 24, cornerRadius: 32, isProminent: true) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Color.climbGreen.opacity(0.13))
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(Color.climbGreen.opacity(0.23), lineWidth: 1))
                    .overlay(
                        Text(String(partner.name.prefix(1)))
                            .font(ClimbTypography.sans(21, weight: .bold))
                            .foregroundStyle(Color.climbGreen)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(partner.name)
                        .font(ClimbTypography.sans(24, weight: .bold))
                        .foregroundStyle(Color.climbMist)
                    Text(partner.focus.shortLabel + " partner")
                        .font(ClimbTypography.sans(13, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                }

                Spacer(minLength: 0)

                Text(hasCheckedIn ? "Partner's turn" : "Your move")
                    .font(ClimbTypography.sans(11, weight: .bold))
                    .foregroundStyle(hasCheckedIn ? Color.climbGreen : Color.climbGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((hasCheckedIn ? Color.climbGreen : Color.climbGold).opacity(0.14), in: Capsule())
            }

            Text(hasCheckedIn ? "You checked in. Keep the shared streak alive tomorrow." : "Don't leave \(partner.name) waiting. One honest check-in keeps the pressure personal.")
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
                isDisabled: hasCheckedIn
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
        ClimbCard(padding: 15, cornerRadius: 28) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(ClimbTypography.sans(16, weight: .bold))
                    .foregroundStyle(Color.climbGreen)
                    .frame(width: 36, height: 36)
                    .background(Color.climbGreen.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite a friend")
                        .font(ClimbTypography.sans(15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Start another accountability pair.")
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                }

                Spacer(minLength: 0)

                ShareLink(item: inviteMessage, subject: Text("Join me on The Climb")) {
                    Text("Invite")
                        .font(ClimbTypography.sans(13, weight: .bold))
                        .foregroundStyle(Color.climbBackground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.climbGreen, in: Capsule())
                }
                .buttonStyle(ScaleButtonStyle())
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
                        .font(ClimbTypography.sans(15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(partnerStatusSummary)
                        .font(ClimbTypography.sans(12, weight: .medium))
                        .foregroundStyle(Color.climbTextSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(ClimbTypography.sans(12, weight: .bold))
                    .foregroundStyle(Color.climbMuted)
            }
            .padding(14)
            .background(Color.climbSurfaceRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var secondaryCommunityLinks: some View {
        ClimbCard(padding: 18, cornerRadius: 30) {
            SectionTitle(title: "More community", subtitle: "Secondary tools when you need them")

            VStack(spacing: 0) {
                NavigationLink {
                    GlobalLeaderboardView(entries: sortedLeaderboard, currentUserID: viewModel.profile?.id)
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
                        subtitle: "\(viewModel.visiblePosts.count) posts",
                        systemImage: "text.bubble.fill",
                        tint: .climbGreen
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
                EmptyState(title: "No partners yet", detail: "Partners are assigned after onboarding.", systemImage: "person.2")
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
                                .font(ClimbTypography.sans(13, weight: .bold))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(ClimbTypography.sans(12, weight: .bold))
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
                            .font(ClimbTypography.sans(17, weight: .bold))
                            .foregroundStyle(Color.climbGreen)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(partner.name)
                        .font(ClimbTypography.sans(19, weight: .bold))
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
                        .font(ClimbTypography.sans(14, weight: .bold))
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
                        .font(ClimbTypography.sans(14, weight: .bold))
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
                        .font(ClimbTypography.sans(15, weight: .bold))
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
                            .font(ClimbTypography.sans(14, weight: .bold))
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
                        .font(ClimbTypography.sans(13, weight: .bold))
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
                        .font(ClimbTypography.sans(13, weight: .bold))
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
                EmptyState(title: "No groups yet", detail: "Create your plan to see accountability groups.", systemImage: "person.3")
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
                                        await viewModel.joinGroup(group.id)
                                        if !group.isJoined {
                                            showFeedback("Joined \(group.name)")
                                        }
                                    }
                                } label: {
                                    Label(group.isJoined ? "Joined" : "Join Group", systemImage: group.isJoined ? "checkmark.circle.fill" : "plus.circle")
                                        .font(ClimbTypography.sans(13, weight: .bold))
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
                EmptyState(title: "No encouragement yet", detail: "Posts from your groups will appear here.", systemImage: "text.bubble")
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
                    GlobalLeaderboardView(entries: sortedLeaderboard, currentUserID: viewModel.profile?.id)
                } label: {
                    Label("View all", systemImage: "chevron.right")
                        .font(ClimbTypography.sans(12, weight: .bold))
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
        viewModel.partners.first
    }

    private var sortedLeaderboard: [LeaderboardEntry] {
        viewModel.leaderboard.sorted {
            if $0.ovrScore == $1.ovrScore {
                return $0.streak > $1.streak
            }
            return $0.ovrScore > $1.ovrScore
        }
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

    private var inviteMessage: String {
        "Join me on The Climb. It is a daily discipline app with devotionals, missions, reflection, accountability, and progress tracking."
    }

    private var partnerStatusSummary: String {
        guard !viewModel.partners.isEmpty else { return "No partners yet" }
        let activeCount = viewModel.partners.filter { $0.lastCheckIn == "Just now" || $0.lastCheckIn == "Today" }.count
        return "\(activeCount) active today - \(viewModel.partners.count) total"
    }

    private func sharedStreak(for partner: AccountabilityPartner) -> Int {
        min(14, max(1, partner.checkInCount + 2))
    }

    private func weeklyCompletionText(for partner: AccountabilityPartner) -> String {
        "\(min(7, max(3, partner.checkInCount + 3)))/7"
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
                .font(ClimbTypography.sans(16, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(ClimbTypography.sans(10, weight: .bold))
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
                            .font(ClimbTypography.sans(12, weight: .bold))
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
                .font(ClimbTypography.sans(15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ClimbTypography.sans(15, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(ClimbTypography.sans(12, weight: .bold))
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
                        .font(ClimbTypography.sans(14, weight: .bold))
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
                .font(ClimbTypography.sans(18, weight: .bold).monospacedDigit())
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
                .font(ClimbTypography.sans(15, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(ClimbTypography.sans(20, weight: .bold))
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
                .font(ClimbTypography.sans(13, weight: .bold).monospacedDigit())
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
                .font(ClimbTypography.sans(17, weight: .bold))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Status dots show who has checked in today.")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .padding(.horizontal, 2)

                ForEach(viewModel.partners) { partner in
                    ClimbCard(padding: 17, cornerRadius: 26) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.climbGreen.opacity(0.14))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(partner.name.prefix(1)))
                                        .font(ClimbTypography.sans(16, weight: .bold))
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
                                    .font(ClimbTypography.sans(17, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("\(partner.focus.shortLabel) partner - \(partner.lastCheckIn)")
                                    .font(ClimbTypography.sans(12, weight: .medium))
                                    .foregroundStyle(Color.climbTextSecondary)
                            }

                            Spacer(minLength: 0)

                            Button {
                                selectedPartner = partner
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(ClimbTypography.sans(13, weight: .bold))
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
    }
}

private struct GroupsBrowserView: View {
    @ObservedObject var viewModel: AppViewModel
    let onFeedback: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Join a challenge when you need more external pressure.")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .padding(.horizontal, 2)

                ForEach(viewModel.groups) { group in
                    ClimbCard(padding: 20, cornerRadius: 28) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(ClimbTypography.sans(18, weight: .bold))
                                .foregroundStyle(Color.climbBlue)
                                .frame(width: 42, height: 42)
                                .background(Color.climbBlue.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.name)
                                    .font(ClimbTypography.sans(18, weight: .bold))
                                    .foregroundStyle(.white)
                                Text(group.subtitle)
                                    .font(ClimbTypography.sans(13, weight: .medium))
                                    .foregroundStyle(Color.climbTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack {
                            Text("\(group.members) members")
                            Spacer()
                            Text(group.activeChallenge)
                        }
                        .font(ClimbTypography.sans(12, weight: .bold))
                        .foregroundStyle(Color.climbMuted)

                        Button {
                            Task {
                                await viewModel.joinGroup(group.id)
                                if !group.isJoined {
                                    await MainActor.run {
                                        onFeedback("Joined \(group.name)")
                                    }
                                }
                            }
                        } label: {
                            Label(group.isJoined ? "Joined" : "Join Group", systemImage: group.isJoined ? "checkmark.circle.fill" : "plus.circle")
                                .font(ClimbTypography.sans(14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .foregroundStyle(group.isJoined ? Color.climbGreen : Color.climbBackground)
                        .background(group.isJoined ? Color.climbGreen.opacity(0.14) : Color.climbGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(ClimbScreenBackground())
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
                    EmptyState(title: "No encouragement yet", detail: "Posts from your groups will appear here.", systemImage: "text.bubble")
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
        .background(ClimbScreenBackground())
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
                                            .font(ClimbTypography.sans(20, weight: .bold))
                                            .foregroundStyle(Color.climbGreen)
                                    )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(partner.name)
                                        .font(ClimbTypography.sans(24, weight: .bold))
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
        }
    }
}

private struct GlobalLeaderboardView: View {
    let entries: [LeaderboardEntry]
    let currentUserID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Global rankings update from OVR first, then streak.")
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .padding(.horizontal, 2)

                ClimbCard(padding: 20, cornerRadius: 30, isProminent: true) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(
                            rank: index + 1,
                            entry: entry,
                            isCurrentUser: entry.id == currentUserID
                        )
                        if index < entries.count - 1 {
                            Divider().overlay(Color.climbDivider)
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
        .navigationTitle("Global Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(ClimbTypography.sans(15, weight: .bold))
                .foregroundStyle(rank == 1 ? Color.climbGold : Color.climbMuted)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(ClimbTypography.sans(15, weight: .semibold))
                        .foregroundStyle(.white)
                    if isCurrentUser {
                        Text("You")
                            .font(ClimbTypography.sans(10, weight: .bold))
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
                    .font(ClimbTypography.sans(17, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("OVR")
                    .font(ClimbTypography.sans(10, weight: .bold))
                    .foregroundStyle(Color.climbMuted)
            }
        }
        .padding(.vertical, 4)
    }
}
