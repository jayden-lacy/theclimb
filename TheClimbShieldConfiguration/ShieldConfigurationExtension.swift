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
            subtitle: ShieldConfiguration.Label(text: subtitle, color: Palette.secondaryText),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Stay Focused", color: .white),
            primaryButtonBackgroundColor: Palette.green
        )
    }

    private static var icon: UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 64, weight: .semibold)
        return UIImage(systemName: "mountain.2.fill", withConfiguration: configuration)?
            .withTintColor(Palette.green, renderingMode: .alwaysOriginal)
    }
}

private enum Palette {
    static let background = UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1.0)
    static let primaryText = UIColor.white
    static let secondaryText = UIColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1.0)
    static let green = UIColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1.0)
}
