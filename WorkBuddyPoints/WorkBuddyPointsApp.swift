import SwiftUI

@main
struct WorkBuddyPointsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var credentialStore = CredentialStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(credentialStore)
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        handleActive()
                    case .background:
                        handleBackground()
                    default:
                        break
                    }
                }
        }
    }

    /// 回到前台：刷新后台任务排期；今日未成功执行过则自动补跑
    private func handleActive() {
        let credential = credentialStore.credential
        if credential.autoRunEnabled {
            BackgroundTaskManager.shared.scheduleAppRefresh(hour: credential.runHour,
                                                            minute: credential.runMinute)
        }
        if HistoryStore.shared.shouldAutoRunNow(credential: credential) {
            Task { @MainActor in
                _ = await CheckinEngine.shared.runDaily(
                    includeTravel: credential.travelEnabled,
                    source: "foreground"
                )
            }
        }
    }

    /// 进入后台：排定下次后台刷新与每日本地提醒
    private func handleBackground() {
        let credential = credentialStore.credential
        if credential.autoRunEnabled {
            BackgroundTaskManager.shared.scheduleAppRefresh(hour: credential.runHour,
                                                            minute: credential.runMinute)
        }
        if credential.notificationsEnabled {
            NotificationService.shared.scheduleDailyReminder(hour: credential.runHour,
                                                             minute: credential.runMinute)
        } else {
            NotificationService.shared.cancelDailyReminder()
        }
    }
}
