import Foundation
import UserNotifications

/// 本地通知：执行结果播报 + 每日定时提醒（后台任务之外的兜底）
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let reminderIdentifier = "com.wbpoints.daily.dailyReminder"

    private init() {}

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 发送一次执行结果通知
    func sendResult(_ outcome: RunOutcome, enabled: Bool) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "WorkBuddy \(outcome.status.rawValue)"
        var body = outcome.message
        if let travel = outcome.travel, !travel.isEmpty {
            body += "\n\(travel)"
        }
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "result-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        center.add(request)
    }

    /// 每日定时提醒：到点提醒用户打开 App 自动完成签到
    func scheduleDailyReminder(hour: Int, minute: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        var components = DateComponents()
        components.hour = max(0, min(23, hour))
        components.minute = max(0, min(59, minute))
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "WorkBuddy 积分助手"
        content.body = "该领今日积分啦，打开 App 自动完成签到"
        content.sound = .default
        let request = UNNotificationRequest(identifier: reminderIdentifier,
                                            content: content, trigger: trigger)
        center.add(request)
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }
}
