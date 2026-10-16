import Foundation
import BackgroundTasks

/// 后台每日任务调度（BGAppRefreshTask）。
///
/// iOS 对后台执行时机有最终决定权，系统会在设置时间之后择机执行；
/// 因此 App 同时提供「本地通知提醒 + 打开 App 自动补跑」作为兜底，
/// 需要精确到分的定时可配合「快捷指令」个人自动化（见设置页说明）。
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()

    let refreshIdentifier = "com.wbpoints.daily.refresh"

    private init() {}

    /// 必须在 App 启动早期（didFinishLaunching）调用
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { [weak self] task in
            self?.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    /// 提交下一次后台刷新（每次前后台切换、每次任务触发后都会重新排期）
    func scheduleAppRefresh(hour: Int, minute: Int) {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = nextRunDate(hour: hour, minute: minute)
        try? BGTaskScheduler.shared.submit(request)
    }

    func cancelPendingRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // 先排下一次，保证每日循环不断
        let work = Task { @MainActor in
            let credential = await CredentialStore.shared.snapshot()
            if credential.autoRunEnabled {
                scheduleAppRefresh(hour: credential.runHour, minute: credential.runMinute)
            }
            let outcome = await CheckinEngine.shared.runDaily(
                includeTravel: credential.travelEnabled,
                source: "background"
            )
            NotificationService.shared.sendResult(outcome, enabled: credential.notificationsEnabled)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// 下一个执行时间点（今天已过则排明天）
    private func nextRunDate(hour: Int, minute: Int) -> Date? {
        var components = DateComponents()
        components.hour = max(0, min(23, hour))
        components.minute = max(0, min(59, minute))
        return Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)
    }
}
