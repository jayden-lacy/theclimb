import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Focus"
    case grow = "Word"
    case community = "Circle"
    case progress = "Insights"
    case profile = "Me"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "shield.lefthalf.filled"
        case .grow: "book.closed"
        case .community: "person.2"
        case .progress: "chart.line.uptrend.xyaxis"
        case .profile: "person.crop.circle"
        }
    }
}
