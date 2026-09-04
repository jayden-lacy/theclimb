import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration(
            title: "\(application.localizedDisplayName ?? "This app") is blocked",
            subtitle: "Your mission is active. Step away from the distraction and finish the next right thing."
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(
            title: "\(application.localizedDisplayName ?? category.localizedDisplayName ?? "This category") is blocked",
            subtitle: "This is part of the focus boundary you chose for today’s mission."
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(
            title: "\(webDomain.domain ?? "This site") is blocked",
            subtitle: "Stay with the mission. You can come back after the focus session is finished."
        )
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(
            title: "\(webDomain.domain ?? category.localizedDisplayName ?? "This site") is blocked",
            subtitle: "The Climb is protecting the focus boundary you set for this mission."
        )
    }

    private func configuration(title: String, subtitle: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Palette.background,
            icon: Self.icon,
            title: ShieldConfiguration.Label(text: title, color: Palette.primaryText),
            subtitle: ShieldConfiguration.Label(text: FocusShieldTimerStore.subtitle(fallback: subtitle), color: Palette.secondaryText),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Stay Focused", color: Palette.buttonText),
            primaryButtonBackgroundColor: Palette.periwinkle
        )
    }

    private static var icon: UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 64, weight: .semibold)
        return UIImage(systemName: "mountain.2.fill", withConfiguration: configuration)?
            .withTintColor(Palette.periwinkle, renderingMode: .alwaysOriginal)
    }
}

private enum FocusShieldTimerStore {
    private static let appGroupID = "group.com.jaydenlacy.theclimb"
    private static let titleKey = "the-climb.active-focus.title.v1"
    private static let endsAtKey = "the-climb.active-focus.ends-at.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func subtitle(fallback: String) -> String {
        let timestamp = defaults.double(forKey: endsAtKey)
        guard timestamp > 0 else { return fallback }

        let endDate = Date(timeIntervalSince1970: timestamp)
        let remainingSeconds = Int(ceil(endDate.timeIntervalSinceNow))
        guard remainingSeconds > 0 else {
            return "The focus timer has ended. Return to The Climb to reflect and clear this block."
        }

        let title = trimmedTitle(defaults.string(forKey: titleKey) ?? "Your mission")
        let remaining = formattedDuration(remainingSeconds)
        let endTime = DateFormatter.localizedString(from: endDate, dateStyle: .none, timeStyle: .short)
        return "\(title) - \(remaining) left. Ends at \(endTime)."
    }

    private static func trimmedTitle(_ title: String) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.count > 44 else { return cleanTitle.isEmpty ? "Your mission" : cleanTitle }
        return "\(cleanTitle.prefix(44))..."
    }

    private static func formattedDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "less than 1 min"
        }

        let minutes = Int(ceil(Double(seconds) / 60.0))
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(remainingMinutes) min"
    }
}

private enum Palette {
    static let background = UIColor(red: 7 / 255, green: 11 / 255, blue: 22 / 255, alpha: 1)
    static let primaryText = UIColor(red: 247 / 255, green: 247 / 255, blue: 245 / 255, alpha: 1)
    static let secondaryText = UIColor(red: 156 / 255, green: 166 / 255, blue: 181 / 255, alpha: 1)
    static let periwinkle = UIColor(red: 169 / 255, green: 203 / 255, blue: 255 / 255, alpha: 1)
    static let buttonText = UIColor(red: 7 / 255, green: 11 / 255, blue: 22 / 255, alpha: 1)
}
