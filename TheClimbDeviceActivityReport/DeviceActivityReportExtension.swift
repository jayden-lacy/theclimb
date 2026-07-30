import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct TheClimbDeviceActivityReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        AttentionSummaryReportScene()
    }
}
