import Foundation

/// 凭据与偏好设置的单一数据源（UI 与后台任务都从这里读写）
@MainActor
final class CredentialStore: ObservableObject {
    static let shared = CredentialStore()

    @Published private(set) var credential: Credential = .default
    /// 最近一次请求是否因凭据失效而失败
    @Published private(set) var authInvalid = false
    /// 最近一次保存是否失败（Keychain 异常时提示）
    @Published private(set) var lastSaveError: String?

    private let keychain = KeychainStore(service: "com.wbpoints.daily.credential")
    private let account = "credential-v1"

    private init() {
        if let data = keychain.load(account: account),
           let decoded = try? JSONDecoder().decode(Credential.self, from: data) {
            credential = decoded
        }
    }

    var isConfigured: Bool { credential.isConfigured }

    func save(_ updated: Credential) {
        var value = updated
        value.updatedAt = Date()
        credential = value
        persist()
    }

    /// 长效令牌轮换后回写（刷新接口每次都会返回新令牌）
    func updateRefreshToken(_ token: String) {
        guard !token.isEmpty, token != credential.refreshToken else { return }
        credential.refreshToken = token
        credential.updatedAt = Date()
        persist()
    }

    func markAuthFailed() { authInvalid = true }
    func markAuthOK() { authInvalid = false }

    func clear() {
        credential = .default
        authInvalid = false
        keychain.delete(account: account)
    }

    /// 供非 MainActor 环境（后台任务 / 快捷指令）await 读取
    func snapshot() -> Credential { credential }

    private func persist() {
        guard let data = try? JSONEncoder().encode(credential) else { return }
        if keychain.save(data, account: account) {
            lastSaveError = nil
        } else {
            lastSaveError = "凭据保存到钥匙串失败，请重试"
        }
    }
}
