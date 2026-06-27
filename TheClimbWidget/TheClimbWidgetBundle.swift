#if os(iOS)
import SwiftUI
import WidgetKit

@main
struct TheClimbWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        TheClimbWidget()
        if #available(iOSApplicationExtension 16.1, *) {
            TheClimbMissionLiveActivity()
        }
    }
}
#endif
