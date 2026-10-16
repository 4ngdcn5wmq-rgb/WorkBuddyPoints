import Foundation

/// 仪表盘视图模型：状态查询、手动执行、结果展示
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var status: CheckinStatusSnapshot?
    @Published var travel: TravelSnapshot?
    @Published var isRunning = false
    @Published var isRefreshing = false
    @Published var lastOutcome: RunOutcome?
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var showError = false

    private let engine = CheckinEngine.shared

    /// 查询当前状态（只读，不领取）
    func refresh() async {
        let credential = CredentialStore.shared.credential
        guard credential.isConfigured else {
            status = nil
            travel = nil
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let auth = try await CheckinEngine.resolveAuth(credential)
            let domain = credential.checkinDomain.trimmed.isEmpty
                ? "www.codebuddy.cn"
                : credential.checkinDomain.trimmed
            status = try await APIClient.shared.checkinStatus(domain: domain, auth: auth)
            CredentialStore.shared.markAuthOK()
            if credential.travelEnabled {
                let travelDomain = credential.travelDomain.trimmed.isEmpty
                    ? "www.workbuddy.cn"
                    : credential.travelDomain.trimmed
                travel = try? await APIClient.shared.travelStatus(domain: travelDomain, auth: auth)
            } else {
                travel = nil
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            if (error as? APIError)?.isAuthFailure == true {
                CredentialStore.shared.markAuthFailed()
            }
        }
    }

    /// 手动立即执行一次完整闭环
    func runNow() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let credential = CredentialStore.shared.credential
        let outcome = await engine.runDaily(
            includeTravel: credential.travelEnabled,
            source: "manual"
        )
        lastOutcome = outcome
        if outcome.status == .failed {
            errorMessage = outcome.message
            showError = true
        }
        NotificationService.shared.sendResult(outcome, enabled: credential.notificationsEnabled)
        await refresh()
    }
}
