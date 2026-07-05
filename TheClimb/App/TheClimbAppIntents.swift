#if os(iOS)
import AppIntents
import Foundation

enum ClimbShortcutDestination: String, AppEnum {
    case home
    case grow
    case community
    case progress
    case profile

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "The Climb Destination")
    static var caseDisplayRepresentations: [ClimbShortcutDestination: DisplayRepresentation] = [
        .home: DisplayRepresentation(title: "Home"),
        .grow: DisplayRepresentation(title: "Daily Word"),
        .community: DisplayRepresentation(title: "Community"),
        .progress: DisplayRepresentation(title: "Progress"),
        .profile: DisplayRepresentation(title: "Profile")
    ]

    var appTab: AppTab {
        switch self {
        case .home:
            .home
        case .grow:
            .grow
        case .community:
            .community
        case .progress:
            .progress
        case .profile:
            .profile
        }
    }
}

enum ClimbShortcutHandoffStore {
    private static let destinationKey = "the-climb.shortcut.destination"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: LocalAppRepository.appGroupID) ?? .standard
    }

    static func save(destination: ClimbShortcutDestination) {
        defaults.set(destination.rawValue, forKey: destinationKey)
    }

    static func consumeDestination() -> AppTab? {
        guard let rawValue = defaults.string(forKey: destinationKey),
              let destination = ClimbShortcutDestination(rawValue: rawValue) else {
            return nil
        }
        defaults.removeObject(forKey: destinationKey)
        return destination.appTab
    }
}

struct OpenClimbDestinationIntent: AppIntent {
    static let title: LocalizedStringResource = "Open The Climb"
    static let description = IntentDescription("Open The Climb to a specific part of your daily path.")
    static let openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: ClimbShortcutDestination

    init() {
        destination = .home
    }

    init(destination: ClimbShortcutDestination) {
        self.destination = destination
    }

    func perform() async throws -> some IntentResult {
        ClimbShortcutHandoffStore.save(destination: destination)
        return .result()
    }
}

struct StartTodayMissionShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Today’s Mission"
    static let description = IntentDescription("Open The Climb to begin today’s focus mission.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ClimbShortcutHandoffStore.save(destination: .home)
        return .result()
    }
}

struct OpenDailyWordShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Daily Word"
    static let description = IntentDescription("Open today’s scripture and devotional in The Climb.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ClimbShortcutHandoffStore.save(destination: .grow)
        return .result()
    }
}

struct StartQuickPrayerShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Quick Prayer"
    static let description = IntentDescription("Open The Climb to start a short prayer session.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ClimbShortcutHandoffStore.save(destination: .grow)
        return .result()
    }
}

struct ReflectNowShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Reflect Now"
    static let description = IntentDescription("Open The Climb to complete today’s reflection.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ClimbShortcutHandoffStore.save(destination: .home)
        return .result()
    }
}

struct TheClimbAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTodayMissionShortcutIntent(),
            phrases: [
                "Start my mission in \(.applicationName)",
                "Begin my climb in \(.applicationName)"
            ],
            shortTitle: "Start Mission",
            systemImageName: "target"
        )

        AppShortcut(
            intent: OpenDailyWordShortcutIntent(),
            phrases: [
                "Open Daily Word in \(.applicationName)",
                "Read scripture in \(.applicationName)"
            ],
            shortTitle: "Daily Word",
            systemImageName: "book.closed"
        )

        AppShortcut(
            intent: StartQuickPrayerShortcutIntent(),
            phrases: [
                "Start prayer in \(.applicationName)",
                "Pray with \(.applicationName)"
            ],
            shortTitle: "Pray",
            systemImageName: "hands.sparkles"
        )

        AppShortcut(
            intent: ReflectNowShortcutIntent(),
            phrases: [
                "Reflect in \(.applicationName)",
                "Complete my reflection in \(.applicationName)"
            ],
            shortTitle: "Reflect",
            systemImageName: "square.and.pencil"
        )
    }
}
#endif
