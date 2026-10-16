import Foundation

extension String {
    /// 去除首尾空白（含全角空格）
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 凭据模式：对应自动签到的三种授权通道
enum CredentialMode: String, Codable, CaseIterable, Identifiable {
    /// 长效令牌：App 自行换取接口令牌并轮换保存，客户端不开也能签（推荐）
    case refreshToken
    /// 接口令牌（accessToken / JWT）
    case bearer
    /// 网页端已登录会话 Cookie（需回放原始 User-Agent）
    case cookie

    var id: String { rawValue }

    var title: String {
        switch self {
        case .refreshToken: return "长效令牌（推荐）"
        case .bearer: return "Bearer 令牌"
        case .cookie: return "网页 Cookie"
        }
    }

    var hint: String {
        switch self {
        case .refreshToken:
            return "客户端登录态里的长效令牌。App 每次运行会自动换取新的接口令牌并保存轮换结果，长期有效、不依赖客户端在线。"
        case .bearer:
            return "PC 客户端登录态里的 accessToken（JWT）。有效期较短，过期后需要重新填写。"
        case .cookie:
            return "网页端已登录会话的 Cookie。网关把会话与 User-Agent 绑定，必须同时填写取到该 Cookie 时浏览器的 User-Agent。"
        }
    }
}

/// 全部凭据与偏好设置，整体以 JSON 存入本机 Keychain
struct Credential: Codable, Equatable {
    var mode: CredentialMode = .refreshToken
    var refreshToken: String = ""
    var bearerToken: String = ""
    var cookie: String = ""
    var userAgent: String = ""
    var checkinDomain: String = "www.codebuddy.cn"
    var travelDomain: String = "www.workbuddy.cn"
    /// 每日自动执行
    var autoRunEnabled: Bool = true
    /// 自动执行时间（时 / 分）
    var runHour: Int = 9
    var runMinute: Int = 0
    /// 签到时顺带完成派猫猫旅行闭环
    var travelEnabled: Bool = true
    /// 执行后发送本地通知
    var notificationsEnabled: Bool = true
    var updatedAt: Date = .distantPast

    static let `default` = Credential()

    var isConfigured: Bool {
        switch mode {
        case .refreshToken: return !refreshToken.trimmed.isEmpty
        case .bearer: return !bearerToken.trimmed.isEmpty
        case .cookie: return !cookie.trimmed.isEmpty
        }
    }

    var runTimeText: String {
        String(format: "每天 %02d:%02d", max(0, min(23, runHour)), max(0, min(59, runMinute)))
    }
}
