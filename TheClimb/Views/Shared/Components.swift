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

    static let climbBackgroundDeep = Color(hex: 0x050507)
    static let climbBackground = Color(hex: 0x050507)
    static let climbBackgroundLifted = Color(hex: 0x0B0B0F)
    static let climbSurface = Color(hex: 0x121216)
    static let climbSurfaceRaised = Color(hex: 0x1A1A20)
    static let climbSurfaceGlass = Color(hex: 0x15151B, alpha: 0.66)
    static let climbDivider = Color(hex: 0x2A292F)
    static let climbTextSecondary = Color(hex: 0xB6B0A6)
    static let climbMuted = Color(hex: 0x74706A)
    static let climbGreen = Color(hex: 0x22C55E)
    static let climbGold = Color(hex: 0xF59E0B)
    static let climbRed = Color(hex: 0xEF4444)
    static let climbBlue = Color(hex: 0x8FB8FF)
    static let climbInk = Color(hex: 0x0B0B0F)
    static let climbMist = Color(hex: 0xFFFFFF)
    static let climbSage = Color(hex: 0x9AA891)
    static let climbWarm = Color(hex: 0xD8D0C4)
}

enum ClimbTypography {
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("DM Sans", size: size, relativeTo: relativeTextStyle(for: size)).weight(weight)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("DM Serif Display", size: size, relativeTo: relativeTextStyle(for: size)).weight(weight)
    }

    private static func relativeTextStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<13:
            .caption
        case ..<17:
            .body
        case ..<23:
            .title3
        case ..<30:
            .title2
        default:
            .largeTitle
        }
    }
}

enum ClimbMotion {
    static let quick = Animation.interpolatingSpring(stiffness: 170, damping: 20)
    static let standard = Animation.interpolatingSpring(stiffness: 120, damping: 18)
    static let slow = Animation.interpolatingSpring(stiffness: 92, damping: 18)
    static let focus = Animation.interpolatingSpring(stiffness: 120, damping: 18)

    static func staggered(_ index: Int) -> Animation {
        standard.delay(Double(min(max(index, 0), 8)) * 0.045)
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
                LazyVStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(showsScrollIndicators ? .visible : .hidden)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: bottomSafeAreaSpacing)
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
                    Color.climbGreen.opacity(0.12),
                    Color.climbSage.opacity(0.035),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 8,
                endRadius: 520
            )
            RadialGradient(
                colors: [
                    Color.climbWarm.opacity(0.055),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 460
            )
            AmbientCanvasBackground()
        }
        .ignoresSafeArea()
    }
}

struct ClimbCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 26
    var isProminent = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isProminent ? Color.climbSurface.opacity(0.86) : Color.climbSurfaceGlass)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isProminent ? 0.105 : 0.065),
                            Color.clear,
                            Color.black.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isProminent ? 0.18 : 0.11),
                            Color.climbDivider.opacity(0.64),
                            Color.black.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(isProminent ? 0.44 : 0.30), radius: isProminent ? 30 : 22, x: 0, y: isProminent ? 22 : 14)
        .shadow(color: Color.climbGreen.opacity(isProminent ? 0.055 : 0.018), radius: isProminent ? 32 : 16, x: 0, y: 0)
        .climbEntrance()
    }
}

private struct AmbientCanvasBackground: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<8 {
                var line = Path()
                let y = size.height * (0.10 + CGFloat(index) * 0.105)
                line.move(to: CGPoint(x: -40, y: y))
                line.addLine(to: CGPoint(x: size.width + 40, y: y - 16))
                context.stroke(line, with: .color(Color.white.opacity(index.isMultiple(of: 2) ? 0.009 : 0.005)), lineWidth: 0.5)
            }
        }
        .opacity(0.62)
        .allowsHitTesting(false)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ClimbTypography.sans(19, weight: .bold))
                .foregroundStyle(Color.climbMist)
            if let subtitle {
                Text(subtitle)
                    .font(ClimbTypography.sans(13, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
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
        ClimbCard(cornerRadius: 24) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(ClimbTypography.sans(16, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(ClimbTypography.sans(12, weight: .medium))
                    .foregroundStyle(Color.climbTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(ClimbTypography.sans(26, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .climbGreen
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.medium)
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(ClimbTypography.sans(17, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
        }
        .buttonStyle(ScaleButtonStyle())
        .foregroundStyle(isDisabled ? Color.climbMuted : Color.climbBackground)
        .background(isDisabled ? Color.climbDivider : tint)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(isDisabled ? 0.04 : 0.22), lineWidth: 0.8)
        )
        .shadow(color: isDisabled ? .clear : tint.opacity(0.22), radius: 22, x: 0, y: 13)
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
                .font(ClimbTypography.sans(15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(ScaleButtonStyle())
        .foregroundStyle(.white)
        .background(Color.climbSurfaceRaised.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }
}

struct StatusBadge: View {
    let text: String
    var color: Color = .climbBlue

    var body: some View {
        Text(text)
            .font(ClimbTypography.sans(12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.11))
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.22), lineWidth: 0.8)
            )
            .clipShape(Capsule())
            .transition(.climbToast)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        ClimbCard {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.climbMuted)
            Text(title)
                .font(ClimbTypography.sans(18, weight: .semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(ClimbTypography.sans(14))
                .foregroundStyle(Color.climbTextSecondary)
        }
    }
}

struct ProgressBar: View {
    let value: Double
    var height: CGFloat = 6
    var tint: Color = .climbGreen

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.climbDivider)
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

    private var daysRemaining: Int {
        max(goal - streak, 0)
    }

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(streak) / Double(goal), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(streak)")
                        .font(ClimbTypography.sans(32, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(streak == 1 ? "day streak" : "day streak")
                        .font(ClimbTypography.sans(14, weight: .semibold))
                        .foregroundStyle(Color.climbTextSecondary)
                }
                Spacer()
                Text(daysRemaining == 0 ? "Goal reached" : "\(daysRemaining) days to goal")
                    .font(ClimbTypography.sans(13, weight: .bold))
                    .foregroundStyle(Color.climbGreen)
            }
            ProgressBar(value: progress, height: 5, tint: .climbGreen)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.climbSurfaceGlass, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .climbEntrance()
    }
}

struct OVRScoreCard: View {
    let score: Int
    let delta: Int

    var body: some View {
        ClimbCard(padding: 22, cornerRadius: 30, isProminent: true) {
            HStack(alignment: .center, spacing: 18) {
                ScoreRing(value: Double(score) / 100, text: "\(score)")

                VStack(alignment: .leading, spacing: 10) {
                    Text("OVR Score")
                        .font(ClimbTypography.sans(18, weight: .semibold))
                        .foregroundStyle(Color.climbMist)
                    ProgressBar(value: Double(score) / 100, height: 6, tint: .climbGreen)
                    Text(deltaText)
                        .font(ClimbTypography.sans(13, weight: .bold))
                        .foregroundStyle(delta == 0 ? Color.climbMuted : (delta > 0 ? Color.climbGreen : Color.climbRed))
                }
            }
        }
    }

    private var deltaText: String {
        if delta > 0 {
            "+\(delta) today"
        } else if delta < 0 {
            "\(delta) today"
        } else {
            "No change today"
        }
    }
}

struct ScoreRing: View {
    let value: Double
    let text: String
    var size: CGFloat = 82
    var tint: Color = .climbGreen

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(ClimbMotion.standard, value: value)
                .shadow(color: tint.opacity(0.35), radius: 12, x: 0, y: 0)
            Text(text)
                .font(ClimbTypography.sans(30, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.climbMist)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.interpolatingSpring(stiffness: 120, damping: 18), value: configuration.isPressed)
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
            .scaleEffect(reduceMotion || isVisible ? 1 : 0.985)
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
                                    colors: [
                                        Color.clear,
                                        Color.white.opacity(0.16),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(proxy.size.width * 0.28, 80), height: proxy.size.height * 1.6)
                            .rotationEffect(.degrees(18))
                            .offset(
                                x: isMoving ? proxy.size.width * 1.15 : -proxy.size.width * 0.55,
                                y: -proxy.size.height * 0.3
                            )
                            .blendMode(.screen)
                            .onAppear {
                                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
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
            insertion: .opacity.combined(with: .scale(scale: 0.985)),
            removal: .opacity.combined(with: .scale(scale: 0.995))
        )
    }

    static var climbToast: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        )
    }
}

extension View {
    func climbEntrance(index: Int = 0, yOffset: CGFloat = 12) -> some View {
        modifier(ClimbEntranceModifier(index: index, yOffset: yOffset))
    }

    func formFieldStyle() -> some View {
        font(ClimbTypography.sans(15))
            .padding(15)
            .foregroundStyle(.white)
            .background(Color.climbSurfaceRaised.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
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

    var sections: [(String, String)] {
        switch self {
        case .privacyPolicy:
            [
                ("What We Collect", "The Climb stores account details, onboarding choices, missions, devotionals, reflections, progress, community posts, reports, and app settings needed to run the app."),
                ("How We Use Data", "Data is used to personalize missions and devotionals, sync progress across devices, support accountability features, improve safety, and respond to support requests."),
                ("AI Features", "When AI generation is enabled, profile context and recent reflection history may be sent to the secure Firebase Cloud Function to generate a daily plan. API keys are not stored in the app."),
                ("Community Safety", "Posts can be reported, blocked, or deleted by the post owner. Reports are used to review abuse, harassment, or unsafe content."),
                ("Deleting Data", "You can delete your account in Profile. This removes your account and synced app data tied to your user ID."),
                ("Contact", "Questions or privacy requests can be sent to support@jointheclimb.app.")
            ]
        case .termsOfService:
            [
                ("Use of The Climb", "The Climb is a faith-based discipline and self-improvement app. Use it respectfully and only for lawful purposes."),
                ("Community Rules", "Do not post harassment, threats, hate, sexual content, spam, or abusive language. We may remove content or restrict access when safety rules are violated."),
                ("Health and Spiritual Guidance", "The app provides encouragement, reflection, and habit support. It is not medical, mental health, legal, or pastoral counseling."),
                ("Your Content", "You are responsible for posts and reflections you create. You can delete your own community posts from the feed."),
                ("Account Deletion", "You can sign out or delete your account in Profile. Deleting your account is permanent."),
                ("Contact", "Support questions can be sent to support@jointheclimb.app.")
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
                            .font(ClimbTypography.sans(18, weight: .bold))
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
