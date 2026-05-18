import Foundation
import UserNotifications

protocol NotificationScheduling {
    func scheduleDailyReminder(hour: Int, minute: Int) async
    func scheduleRecoveryPrompt() async
}

final class LocalNotificationScheduler: NotificationScheduling {
    func scheduleDailyReminder(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional ||
              settings.authorizationStatus == .ephemeral else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Start today's climb"
        content.body = "Your devotional and mission are ready."
        content.sound = .default

        var date = DateComponents()
        date.hour = hour
        date.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-mission-reminder", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func scheduleRecoveryPrompt() async {
        let content = UNMutableNotificationContent()
        content.title = "Recovery is still progress"
        content.body = "Take the fallback mission and finish the day honestly."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60, repeats: false)
        let request = UNNotificationRequest(identifier: "recovery-prompt", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
