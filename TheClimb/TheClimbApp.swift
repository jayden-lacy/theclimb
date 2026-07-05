import FirebaseAppCheck
import FirebaseCore
import FirebaseCrashlytics
import GoogleSignIn
import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        AppAnalytics.record(.appLaunch)
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }

        return url.scheme?.lowercased() == "theclimb"
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

enum AppAnalyticsEvent: String {
    case appLaunch = "app_launch"
    case missionStarted = "mission_started"
    case missionCompleted = "mission_completed"
    case missionFailed = "mission_failed"
    case missionRecovered = "mission_recovered"
    case focusPermissionRequested = "focus_permission_requested"
    case notificationPermissionRequested = "notification_permission_requested"
    case growSectionChanged = "grow_section_changed"
    case versePackOpened = "verse_pack_opened"
    case verseMemorized = "verse_memorized"
    case verseReviewed = "verse_reviewed"
    case prayerSessionCompleted = "prayer_session_completed"
    case dailyWordFeedback = "daily_word_feedback"
    case dailyContentFeedback = "daily_content_feedback"
    case dailyPlanRegenerated = "daily_plan_regenerated"
    case communityPostCreated = "community_post_created"
    case communityPostReported = "community_post_reported"
    case communityUserBlocked = "community_user_blocked"
    case groupJoined = "group_joined"
    case groupLeft = "group_left"
    case groupCreated = "group_created"
    case partnerInviteCreated = "partner_invite_created"
    case partnerInviteAccepted = "partner_invite_accepted"
    case partnerCheckIn = "partner_check_in"
    case partnerNudge = "partner_nudge"
    case partnerEncouragement = "partner_encouragement"
    case habitUpdated = "habit_updated"
    case profileUpdated = "profile_updated"
    case signOut = "sign_out"
    case onboardingRestarted = "onboarding_restarted"
    case accountDeleted = "account_deleted"
}

enum AppAnalytics {
    static func record(_ event: AppAnalyticsEvent, properties: [String: String] = [:]) {
        let payload = properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let suffix = payload.isEmpty ? "" : " \(payload)"
        Crashlytics.crashlytics().log("[analytics] \(event.rawValue)\(suffix)")
    }
}

@main
struct TheClimbApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
