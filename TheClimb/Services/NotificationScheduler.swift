import Foundation
import UserNotifications

enum NotificationPermissionState: Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

protocol NotificationScheduling {
    func authorizationState() async -> NotificationPermissionState
    func requestAuthorization() async -> NotificationPermissionState
    func scheduleDailyReminder(hour: Int, minute: Int) async
    func scheduleIncompleteMissionReminder(at date: Date) async
    func scheduleMissionTimerEnded(for mission: Mission, at date: Date) async
    func cancelMissionTimerEnded() async
    func cancelIncompleteMissionReminder() async
    func scheduleRecoveryPrompt() async
}

final class LocalNotificationScheduler: NotificationScheduling {
    private enum Identifier {
        static let dailyMissionReminder = "daily-mission-reminder"
        static let incompleteMissionReminder = "incomplete-mission-reminder"
        static let missionTimerEnded = "mission-timer-ended"
        static let recoveryPrompt = "recovery-prompt"
    }

    func authorizationState() async -> NotificationPermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.permissionState(from: settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationPermissionState {
        let center = UNUserNotificationCenter.current()
        do {
            let isAllowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard isAllowed else { return .denied }
            return await authorizationState()
        } catch {
            return .unavailable
        }
    }

    func scheduleDailyReminder(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        guard await ensureAuthorization() else {
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
        let request = UNNotificationRequest(identifier: Identifier.dailyMissionReminder, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.dailyMissionReminder])
        try? await center.add(request)
    }

    func scheduleIncompleteMissionReminder(at date: Date) async {
        let center = UNUserNotificationCenter.current()
        guard date > Date(), await ensureAuthorization() else {
            center.removePendingNotificationRequests(withIdentifiers: [Identifier.incompleteMissionReminder])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Don’t leave today unfinished"
        content.body = "Your mission is still open. Take the next honest step before the day closes."
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.incompleteMissionReminder, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.incompleteMissionReminder])
        try? await center.add(request)
    }

    func scheduleMissionTimerEnded(for mission: Mission, at date: Date) async {
        let center = UNUserNotificationCenter.current()
        guard date > Date(), await ensureAuthorization() else {
            center.removePendingNotificationRequests(withIdentifiers: [Identifier.missionTimerEnded])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Mission timer finished"
        content.body = "Reflect on \(mission.title) and close the loop."
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.missionTimerEnded, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.missionTimerEnded])
        try? await center.add(request)
    }

    func cancelMissionTimerEnded() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Identifier.missionTimerEnded])
    }

    func cancelIncompleteMissionReminder() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Identifier.incompleteMissionReminder])
    }

    func scheduleRecoveryPrompt() async {
        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recovery is still progress"
        content.body = "Take the fallback mission and finish the day honestly."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * 60, repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.recoveryPrompt, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.recoveryPrompt])
        try? await center.add(request)
    }

    private func ensureAuthorization() async -> Bool {
        switch await authorizationState() {
        case .authorized:
            return true
        case .notDetermined:
            return await requestAuthorization() == .authorized
        case .denied, .unavailable:
            return false
        }
    }

    private static func permissionState(from status: UNAuthorizationStatus) -> NotificationPermissionState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unavailable
        }
    }
}
