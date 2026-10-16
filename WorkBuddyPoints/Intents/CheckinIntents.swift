import AppIntents
import Foundation

/// 快捷指令意图：执行每日签到 + 派猫猫闭环。
/// 在「快捷指令」App 里创建个人自动化（如每天 09:00 运行本意图），可获得精确到分的定时执行，
/// 且不需要打开 App（openAppWhenRun = false）。
struct WorkBuddyDailyCheckinIntent: AppIntent {
    static var title: LocalizedStringResource = "WorkBuddy 每日签到"
    static var description = IntentDescription("执行签到、领取积分，并按设置完成派猫猫旅行闭环")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let credential = await CredentialStore.shared.snapshot()
        let outcome = await CheckinEngine.shared.runDaily(
            includeTravel: credential.travelEnabled,
            source: "shortcut"
        )
        NotificationService.shared.sendResult(outcome, enabled: credential.notificationsEnabled)
        return .result(value: outcome.message)
    }
}

/// 快捷指令意图：只读查询今日签到状态 / 连续天数 / 积分余额
struct WorkBuddyStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "查询 WorkBuddy 积分状态"
    static var description = IntentDescription("查询今日签到状态、连续签到天数与积分余额")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let credential = await CredentialStore.shared.snapshot()
        guard credential.isConfigured else {
            return .result(value: "未配置凭据，请先在 App 设置中填写")
        }
        do {
            let auth = try await CheckinEngine.resolveAuth(credential)
            let domain = credential.checkinDomain.trimmed.isEmpty
                ? "www.codebuddy.cn"
                : credential.checkinDomain.trimmed
            let snapshot = try await APIClient.shared.checkinStatus(domain: domain, auth: auth)
            let balance = snapshot.balance.map { String($0) } ?? "未知"
            return .result(value: "今日\(snapshot.todayCheckedIn ? "已签到" : "未签到")，"
                           + "连续 \(snapshot.streakDays ?? 0) 天，积分余额 \(balance)")
        } catch {
            return .result(value: "查询失败：\(((error as? LocalizedError)?.errorDescription ?? "\(error)"))")
        }
    }
}

/// 桌面 / 系统搜索里可用的快捷入口
struct WorkBuddyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WorkBuddyDailyCheckinIntent(),
            phrases: ["用\(.applicationName)签到", "\(.applicationName)每日签到"],
            shortTitle: "每日签到",
            systemImageName: "checkmark.seal.fill"
        )
        AppShortcut(
            intent: WorkBuddyStatusIntent(),
            phrases: ["查\(.applicationName)积分", "\(.applicationName)积分状态"],
            shortTitle: "查积分",
            systemImageName: "chart.bar.fill"
        )
    }
}
