import SwiftUI

#if os(iOS)
import UIKit
#endif

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }

    static let climbBackgroundDeep = Color(hex: 0x020302)
    static let climbBackground = Color(hex: 0x050705)
    static let climbBackgroundLifted = Color(hex: 0x090C09)
    static let climbSurface = Color(hex: 0x0D110D)
    static let climbSurfaceRaised = Color(hex: 0x131812)
    static let climbSurfaceGlass = Color(hex: 0x10150F, alpha: 0.86)
    static let climbDivider = Color(hex: 0x242B24)
    static let climbTextSecondary = Color(hex: 0xB7B1A7)
    static let climbMuted = Color(hex: 0x777269)
    static let climbGreen = Color(hex: 0x38D978)
    static let climbGold = Color(hex: 0xDCA64A)
    static let climbRed = Color(hex: 0xE85B5B)
    static let climbBlue = Color(hex: 0x78A6E8)
    static let climbInk = Color(hex: 0x070807)
    static let climbMist = Color(hex: 0xF8F7F2)
    static let climbSage = Color(hex: 0x8CDBA2)
    static let climbWarm = Color(hex: 0xE8DDCA)
    static let climbAction = Color(hex: 0x38D978)
    static let climbHairline = Color.white.opacity(0.075)
}

enum ClimbTypography {
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("DM Sans", size: size, relativeTo: relativeTextStyle(for: size)).weight(weight)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("DM Serif Display", size: size, relativeTo: relativeTextStyle(for: size)).weight(weight)
    }

    static let eyebrowTracking: CGFloat = 1.65

    private static func relativeTextStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<13:
            .caption
        case ..<17:
            .body
        case ..<22:
            .title3
        case ..<30:
            .title2
        default:
            .largeTitle
        }
    }
}

enum ClimbMotion {
    static let quick = Animation.interpolatingSpring(stiffness: 260, damping: 30)
    static let standard = Animation.interpolatingSpring(stiffness: 170, damping: 24)
    static let slow = Animation.interpolatingSpring(stiffness: 118, damping: 22)
    static let focus = Animation.interpolatingSpring(stiffness: 132, damping: 20)

    static func staggered(_ index: Int) -> Animation {
        standard.delay(Double(min(max(index, 0), 8)) * 0.035)
    }
}

enum HapticFeedback {
    static func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }

    static func impact(_ style: HapticImpactStyle = .light) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style.uiKitStyle)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

enum HapticImpactStyle {
    case light
    case medium

    #if os(iOS)
    var uiKitStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light:
            .light
        case .medium:
            .medium
        }
    }
    #endif
}

struct ScreenContainer<Content: View>: View {
    let title: String
    var titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline
    var hidesNavigationBar = false
    var showsScrollIndicators = true
    var bottomSafeAreaSpacing: CGFloat = 126
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .scrollIndicators(showsScrollIndicators ? .visible : .hidden)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: bottomSafeAreaSpacing)
            }
            .background(ClimbScreenBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(titleDisplayMode)
            .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
        }
    }
}

struct ClimbScreenBackground: View {
    var body: some View {
        ZStack {
            Color.climbBackgroundDeep
            RadialGradient(
                colors: [
                    Color.climbAction.opacity(0.095),
                    Color.climbBackgroundLifted.opacity(0.28),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
            LinearGradient(
                colors: [
                    Color.white.opacity(0.020),
                    Color.clear,
                    Color.black.opacity(0.30)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            AmbientCanvasBackground()
        }
        .ignoresSafeArea()
    }
}

struct ClimbCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 20
    var isProminent = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isProminent ? Color.climbSurfaceRaised.opacity(0.94) : Color.climbSurfaceGlass)
                .overlay(alignment: .topLeading) {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isProminent ? 0.055 : 0.035),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(isProminent ? 0.115 : 0.075), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(isProminent ? 0.30 : 0.18), radius: isProminent ? 18 : 10, x: 0, y: isProminent ? 14 : 7)
        .climbEntrance()
    }
}

private struct AmbientCanvasBackground: View {
    var body: some View {
        Canvas { context, size in
            let hairline = Color.white.opacity(0.007)
            for index in 0..<7 {
                var line = Path()
                let y = size.height * (0.13 + CGFloat(index) * 0.12)
                line.move(to: CGPoint(x: -24, y: y))
                line.addLine(to: CGPoint(x: size.width + 24, y: y - 10))
                context.stroke(line, with: .color(hairline), lineWidth: 0.5)
            }
        }
        .opacity(0.70)
        .allowsHitTesting(false)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ClimbTypography.sans(20, weight: .semibold))
                .foregroundStyle(Color.climbMist)
                .tracking(-0.25)
            if let subtitle {
                Text(subtitle)
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .climbGold

    var body: some View {
        ClimbCard(padding: 16, cornerRadius: 18) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(ClimbTypography.sans(14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(ClimbTypography.sans(28, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .climbAction
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.medium)
            action()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(ClimbTypography.sans(15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
        .frame(maxWidth: .infinity)
        .foregroundStyle(isDisabled ? Color.climbMuted : Color.climbInk)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(isDisabled ? Color.climbDivider.opacity(0.72) : tint)
                .overlay(alignment: .top) {
                    Color.white.opacity(isDisabled ? 0.02 : 0.14)
                        .frame(height: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(isDisabled ? 0.035 : 0.18), lineWidth: 0.8)
        }
        .shadow(color: isDisabled ? .clear : tint.opacity(0.12), radius: 10, x: 0, y: 6)
        .disabled(isDisabled)
        .animation(ClimbMotion.quick, value: isDisabled)
    }
}

struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var action: () -> Void

    var body: some View {
        Button(role: role) {
            HapticFeedback.impact(.light)
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(ClimbTypography.sans(14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(ScaleButtonStyle())
        .foregroundStyle(role == .destructive ? Color.climbRed : Color.climbMist)
        .background(Color.climbSurfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 0.8)
        }
    }
}

struct ScriptureAttributionText: View {
    let reference: String

    var body: some View {
        if reference.localizedCaseInsensitiveContains("(NLT)") {
            Text("New Living Translation (NLT)")
                .font(ClimbTypography.sans(10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Color.climbMuted)
                .textCase(.uppercase)
        }
    }
}

struct StatusBadge: View {
    let text: String
    var color: Color = .climbBlue

    var body: some View {
        Text(text)
            .font(ClimbTypography.sans(11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.7))
            .transition(.climbToast)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: systemImage)
                .font(ClimbTypography.sans(18, weight: .semibold))
                .foregroundStyle(Color.climbSage)
                .frame(width: 40, height: 40)
                .background(Color.climbSage.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.climbSage.opacity(0.14), lineWidth: 0.7))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(ClimbTypography.sans(19, weight: .semibold))
                    .foregroundStyle(Color.climbMist)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(ClimbTypography.sans(14, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.climbSurfaceGlass.opacity(0.62), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.065), lineWidth: 0.7))
        .climbEntrance()
    }
}

struct ProgressBar: View {
    let value: Double
    var height: CGFloat = 6
    var tint: Color = .climbGreen

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.climbDivider.opacity(0.70))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
                    .animation(ClimbMotion.standard, value: value)
            }
        }
        .frame(height: height)
    }
}

struct StreakPill: View {
    let streak: Int
    let goal: Int

    private var daysRemaining: Int { max(goal - streak, 0) }
    private var progress: Double { goal > 0 ? min(Double(streak) / Double(goal), 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(streak)")
                    .font(ClimbTypography.sans(31, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.climbMist)
                    .contentTransition(.numericText())
                Text("day streak")
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                Spacer(minLength: 0)
                Text(daysRemaining == 0 ? "Goal reached" : "\(daysRemaining) left")
                    .font(ClimbTypography.sans(12, weight: .semibold))
                    .foregroundStyle(Color.climbSage)
            }
            ProgressBar(value: progress, height: 5, tint: .climbSage)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color.climbSurfaceGlass.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.7))
        .climbEntrance()
    }
}

struct OVRScoreCard: View {
    let score: Int
    let delta: Int

    var body: some View {
        ClimbCard(padding: 20, cornerRadius: 22, isProminent: true) {
            HStack(alignment: .center, spacing: 18) {
                ScoreRing(value: Double(score) / 100, text: "\(score)")
                VStack(alignment: .leading, spacing: 10) {
                    Text("OVR Score")
                        .font(ClimbTypography.sans(18, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    ProgressBar(value: Double(score) / 100, height: 5, tint: .climbSage)
                    Text(deltaText)
                        .font(ClimbTypography.sans(12, weight: .semibold))
                        .foregroundStyle(delta == 0 ? Color.climbMuted : (delta > 0 ? Color.climbSage : Color.climbRed))
                }
            }
        }
    }

    private var deltaText: String {
        if delta > 0 { return "+\(delta) today" }
        if delta < 0 { return "\(delta) today" }
        return "No change today"
    }
}

struct ScoreRing: View {
    let value: Double
    let text: String
    var size: CGFloat = 82
    var tint: Color = .climbSage

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.075), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(ClimbMotion.standard, value: value)
            Text(text)
                .font(ClimbTypography.sans(size > 70 ? 29 : 21, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .opacity(configuration.isPressed ? 0.91 : 1)
            .animation(ClimbMotion.quick, value: configuration.isPressed)
    }
}

private struct ClimbEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    let index: Int
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : yOffset)
            .scaleEffect(reduceMotion || isVisible ? 1 : 0.992)
            .onAppear {
                guard !isVisible else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : ClimbMotion.staggered(index)) {
                    isVisible = true
                }
            }
    }
}

private struct ActiveShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMoving = false

    let isActive: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive && !reduceMotion {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear, Color.white.opacity(0.11), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(proxy.size.width * 0.20, 70), height: proxy.size.height * 1.45)
                            .rotationEffect(.degrees(16))
                            .offset(x: isMoving ? proxy.size.width * 1.05 : -proxy.size.width * 0.45, y: -proxy.size.height * 0.22)
                            .blendMode(.screen)
                            .onAppear {
                                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                                    isMoving = true
                                }
                            }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
    }
}

extension AnyTransition {
    static var climbScreen: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.992)),
            removal: .opacity.combined(with: .scale(scale: 0.996))
        )
    }

    static var climbStep: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .scale(scale: 0.992)),
            removal: .opacity.combined(with: .move(edge: .leading)).combined(with: .scale(scale: 0.996))
        )
    }

    static var climbToast: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .scale(scale: 0.985))
        )
    }
}

extension View {
    func climbEntrance(index: Int = 0, yOffset: CGFloat = 10) -> some View {
        modifier(ClimbEntranceModifier(index: index, yOffset: yOffset))
    }

    func formFieldStyle() -> some View {
        font(ClimbTypography.sans(15))
            .padding(15)
            .foregroundStyle(Color.climbMist)
            .background(Color.climbSurfaceRaised.opacity(0.68), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.075), lineWidth: 0.8))
    }

    func activeShimmer(_ isActive: Bool, cornerRadius: CGFloat = 12) -> some View {
        modifier(ActiveShimmerModifier(isActive: isActive, cornerRadius: cornerRadius))
    }
}

enum LegalDocument: Identifiable {
    case privacyPolicy
    case termsOfService

    var id: String {
        title
    }

    var title: String {
        switch self {
        case .privacyPolicy:
            "Privacy Policy"
        case .termsOfService:
            "Terms of Service"
        }
    }

    var updatedText: String {
        "Last updated May 18, 2026"
    }

    var onlineURL: URL {
        switch self {
        case .privacyPolicy:
            URL(string: "https://theclimbapp.org/privacy.html")!
        case .termsOfService:
            URL(string: "https://theclimbapp.org/terms.html")!
        }
    }

    var sections: [(String, String)] {
        switch self {
        case .privacyPolicy:
            [
                ("What We Collect", "The Climb stores account details, onboarding choices, missions, devotionals, reflections, progress, community posts, reports, and app settings needed to run the app."),
                ("How We Use Data", "Data is used to personalize missions and devotionals, sync progress across devices, support accountability features, improve safety, and respond to support requests."),
                ("AI Features", "When AI generation is enabled, profile context and recent reflection history may be sent to the secure Firebase Cloud Function to generate a daily plan. API keys are not stored in the app."),
                ("Community Safety", "Posts can be reported, blocked, or deleted by the post owner. Reports are used to review abuse, harassment, or unsafe content."),
                ("Deleting Data", "You can delete your account in Profile. This removes your account and synced app data tied to your user ID."),
                ("Contact", "Questions or privacy requests can be sent to support@theclimbapp.org.")
            ]
        case .termsOfService:
            [
                ("Use of The Climb", "The Climb is a faith-based discipline and self-improvement app. Use it respectfully and only for lawful purposes."),
                ("Community Rules", "Do not post harassment, threats, hate, sexual content, spam, or abusive language. We may remove content or restrict access when safety rules are violated."),
                ("Health and Spiritual Guidance", "The app provides encouragement, reflection, and habit support. It is not medical, mental health, legal, or pastoral counseling."),
                ("Scripture Attribution", "Scripture quotations marked (NLT) are taken from the Holy Bible, New Living Translation, copyright © 1996, 2004, 2015 by Tyndale House Foundation. Used by permission of Tyndale House Publishers. All rights reserved."),
                ("Your Content", "You are responsible for posts and reflections you create. You can delete your own community posts from the feed."),
                ("Account Deletion", "You can sign out or delete your account in Profile. Deleting your account is permanent."),
                ("Contact", "Support questions can be sent to support@theclimbapp.org.")
            ]
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(document.updatedText)
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbMuted)

                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    ClimbCard(cornerRadius: 24) {
                        Text(section.0)
                            .font(ClimbTypography.sans(18, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(section.1)
                            .font(ClimbTypography.sans(14, weight: .medium))
                            .foregroundStyle(Color.climbTextSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(ClimbScreenBackground())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
