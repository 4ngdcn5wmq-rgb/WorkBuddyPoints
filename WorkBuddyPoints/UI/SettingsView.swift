import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: CredentialStore

    @State private var draft: Credential = .default
    @State private var pasteText: String = ""
    @State private var pasteMessage: String?
    @State private var testMessage: String?
    @State private var isTesting = false

    private var timeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(from: DateComponents(hour: draft.runHour,
                                                           minute: draft.runMinute)) ?? Date()
            },
            set: { value in
                let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                draft.runHour = components.hour ?? 9
                draft.runMinute = components.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                credentialSection
                smartPasteSection
                automationSection
                shortcutSection
                aboutSection
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .bold()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                }
            }
            .onAppear {
                draft = store.credential
            }
        }
    }

    // MARK: - 凭据

    private var credentialSection: some View {
        Section {
            Picker("凭据类型", selection: $draft.mode) {
                ForEach(CredentialMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Text(draft.mode.hint)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch draft.mode {
            case .refreshToken:
                SecureField("粘贴长效令牌", text: $draft.refreshToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .bearer:
                SecureField("粘贴 accessToken（JWT）", text: $draft.bearerToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .cookie:
                TextField("粘贴网页 Cookie 串", text: $draft.cookie, axis: .vertical)
                    .lineLimit(3...6)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("取到该 Cookie 时浏览器的 User-Agent", text: $draft.userAgent, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            TextField("签到域名（默认 www.codebuddy.cn）", text: $draft.checkinDomain)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            TextField("旅行域名（默认 www.workbuddy.cn）", text: $draft.travelDomain)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        } header: {
            Text("凭据")
        } footer: {
            Text("凭据只保存在本机钥匙串，不会上传到任何服务器。")
        }
    }

    private var smartPasteSection: some View {
        Section {
            TextField("把授权码 / 登录态 JSON / Cookie / 令牌粘贴到这里", text: $pasteText, axis: .vertical)
                .lineLimit(2...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                applyPaste()
            } label: {
                Label("智能识别并填充", systemImage: "wand.and.stars")
            }
            .disabled(pasteText.trimmed.isEmpty)
            if let pasteMessage {
                Text(pasteMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(isTesting ? "测试中…" : "测试连接（只查状态不领取）")
                }
            }
            .disabled(isTesting || !draft.isConfigured)
            if let testMessage {
                Text(testMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("清除本机凭据", role: .destructive) {
                store.clear()
                draft = .default
                pasteText = ""
            }
            .disabled(!store.isConfigured)
        } header: {
            Text("智能粘贴与测试")
        }
    }

    private var automationSection: some View {
        Section {
            Toggle("每日自动执行", isOn: $draft.autoRunEnabled)
            DatePicker("执行时间", selection: timeBinding, displayedComponents: .hourAndMinute)
                .disabled(!draft.autoRunEnabled)
            Toggle("签到时顺带跑旅行闭环", isOn: $draft.travelEnabled)
            Toggle("执行后发本地通知", isOn: $draft.notificationsEnabled)
        } header: {
            Text("每日自动化")
        } footer: {
            Text("iOS 的后台刷新由系统择机执行；配合「快捷指令」个人自动化可精确到分。")
        }
    }

    private var shortcutSection: some View {
        Section {
            Text("快捷指令 → 自动化 → 新建「App」→ 选择「运行「WorkBuddy 每日签到」意图」→ 设定每天时间，关闭「运行前询问」。")
                .font(.caption)
        } header: {
            Text("精确到分的定时")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: "1.0.0")
            LabeledContent("执行时间", value: draft.runTimeText)
        } header: {
            Text("关于")
        }
    }

    // MARK: - 动作

    private func applyPaste() {
        guard let parsed = AuthCodeParser.parse(pasteText) else {
            pasteMessage = "没识别出有效凭据"
            return
        }
        draft.mode = parsed.mode
        draft.refreshToken = parsed.refreshToken
        draft.bearerToken = parsed.bearerToken
        draft.cookie = parsed.cookie
        if !parsed.userAgent.isEmpty {
            draft.userAgent = parsed.userAgent
        }
        if let domain = parsed.checkinDomain, !domain.isEmpty {
            draft.checkinDomain = domain
        }
        pasteMessage = "已识别为「\(parsed.mode.title)」并填充，请点右上角保存"
        pasteText = ""
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let auth = try await CheckinEngine.resolveAuth(draft)
            let domain = draft.checkinDomain.trimmed.isEmpty
                ? "www.codebuddy.cn"
                : draft.checkinDomain.trimmed
            let snapshot = try await APIClient.shared.checkinStatus(domain: domain, auth: auth)
            testMessage = "连接成功：今日\(snapshot.todayCheckedIn ? "已签到" : "未签到")，"
                + "连续 \(snapshot.streakDays ?? 0) 天，余额 \(snapshot.balance.map(String.init) ?? "未知")"
        } catch {
            testMessage = "连接失败：\(((error as? LocalizedError)?.errorDescription ?? "\(error)"))"
        }
    }

    private func save() {
        store.save(draft)
        if draft.notificationsEnabled {
            Task {
                _ = await NotificationService.shared.requestAuthorization()
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
