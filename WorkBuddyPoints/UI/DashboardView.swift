import SwiftUI

extension RunStatus {
    var tint: Color {
        switch self {
        case .success: return .green
        case .alreadyCheckedIn: return .blue
        case .failed: return .red
        case .noCredential: return .orange
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var credentialStore: CredentialStore
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var history = HistoryStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !credentialStore.credential.isConfigured {
                        setupPromptCard
                    }
                    if credentialStore.authInvalid {
                        authInvalidBanner
                    }
                    checkinCard
                    if credentialStore.credential.travelEnabled {
                        travelCard
                    }
                    automationCard
                    lastRunCard
                }
                .padding()
            }
            .navigationTitle("WorkBuddy 积分助手")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isRefreshing)
                }
            }
            .task {
                await viewModel.refresh()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .alert("执行失败", isPresented: $viewModel.showError) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "未知错误")
            }
        }
    }

    // MARK: - 卡片

    private var setupPromptCard: some View {
        NavigationLink {
            SettingsView()
        } label: {
            card {
                Label("先去「设置」填写凭据，才能自动签到", systemImage: "key.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .buttonStyle(.plain)
    }

    private var authInvalidBanner: some View {
        card {
            Label("凭据已失效，请到「设置」重新填写", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
        }
    }

    private var checkinCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("今日签到")
                        .font(.headline)
                    Spacer()
                    if let status = viewModel.status {
                        Text(status.todayCheckedIn ? "已完成" : "待领取")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                (status.todayCheckedIn ? Color.green : Color.orange).opacity(0.16),
                                in: Capsule()
                            )
                            .foregroundStyle(status.todayCheckedIn ? Color.green : Color.orange)
                    }
                }
                if viewModel.isRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在执行签到闭环…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 24) {
                        metric(title: "连续天数", value: Fmt.int(viewModel.status?.streakDays))
                        metric(title: "每日可得", value: Fmt.int(viewModel.status?.dailyCredit))
                        metric(title: "积分余额", value: Fmt.int(viewModel.status?.balance))
                    }
                }
                Button {
                    Task { await viewModel.runNow() }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text(viewModel.status?.todayCheckedIn == true ? "再跑一次闭环" : "立即签到领积分")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isRunning || !credentialStore.credential.isConfigured)
            }
        }
    }

    private var travelCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("派猫猫旅行")
                    .font(.headline)
                if let travel = viewModel.travel {
                    HStack {
                        Label(travel.stateText, systemImage: icon(for: travel.state))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if let credit = travel.rewardCredit {
                            Text("奖励 \(credit) 积分")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let name = travel.locationName, !name.isEmpty {
                        Text("当前地点：\(name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let remaining = travel.remainingSeconds, travel.state == .traveling {
                        Text(Fmt.countdown(from: remaining))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if travel.dailyLimitReached {
                        Text("今日派遣次数已用完")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("无法获取旅行状态（可能未在客户端激活旅行，或未配置凭据）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var automationCard: some View {
        let credential = credentialStore.credential
        return card {
            VStack(alignment: .leading, spacing: 8) {
                Text("自动执行")
                    .font(.headline)
                Label(credential.autoRunEnabled
                      ? "已开启：\(credential.runTimeText) 自动执行"
                      : "已关闭，只手动执行",
                      systemImage: credential.autoRunEnabled ? "clock.badge.checkmark" : "clock.badge.xmark")
                    .font(.subheadline)
                Label("后台任务 + 本地通知提醒 + 打开 App 补跑，三层保障",
                      systemImage: "shield.checkerboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("精确到分的定时可在「快捷指令」App 创建个人自动化，运行「WorkBuddy 每日签到」意图")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var lastRunCard: some View {
        if let entry = history.entries.first {
            card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近一次执行")
                        .font(.headline)
                    HStack {
                        Image(systemName: entry.statusSymbol)
                            .foregroundStyle(tint(for: entry.status))
                        Text(entry.status)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(entry.sourceText) · \(Fmt.dateTime.string(from: entry.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 组件

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.red)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func icon(for state: TravelSnapshot.State) -> String {
        switch state {
        case .idle: return "figure.walk"
        case .traveling: return "airplane"
        case .arrived: return "gift.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func tint(for status: String) -> Color {
        switch status {
        case RunStatus.success.rawValue: return .green
        case RunStatus.alreadyCheckedIn.rawValue: return .blue
        case RunStatus.failed.rawValue: return .red
        default: return .orange
        }
    }
}
