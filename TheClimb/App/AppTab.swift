import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case grow = "Grow"
    case community = "Community"
    case progress = "Progress"
    case profile = "Profile"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
        case .grow: "leaf"
        case .community: "person.3"
        case .progress: "chart.line.uptrend.xyaxis"
        case .profile: "person.crop.circle"
        }
    }
}

