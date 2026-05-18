#if os(iOS)
import SwiftUI
import WidgetKit

@main
struct TheClimbWidgetBundle: WidgetBundle {
    var body: some Widget {
        TheClimbWidget()
    }
}
#endif
