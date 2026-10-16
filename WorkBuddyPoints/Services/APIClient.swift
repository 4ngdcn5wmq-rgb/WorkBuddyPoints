import Foundation

enum APIError: LocalizedError {
    case invalidURL(String)
    case transport(String)
    case http(status: Int, body: String)
    case api(code: Int, msg: String)
    case authFailed(String)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "无效的接口地址：\(value)"
        case .transport(let value):
            return "网络错误：\(value)"
        case .http(let status, let body):
            let snippet = String(body.prefix(120))
            return "服务端返回 HTTP \(status)：\(snippet)"
        case .api(let code, let msg):
            return "接口返回错误 [\(code)]：\(msg)"
        case .authFailed(let msg):
            return "凭据已失效：\(msg)"
        case .malformed(let msg):
            return "响应解析失败：\(msg)"
        }
    }

    var isAuthFailure: Bool {
        switch self {
        case .authFailed:
            return true
        case .http(let status, _):
            return status == 401 || status == 403
        default:
            return false
        }
    }
}

/// 鉴权方式：Bearer 令牌或网页 Cookie（Cookie 模式需回放原始 UA）
enum AuthAttachment {
    case bearer(String)
    case cookie(String, userAgent: String)

    func apply(to request: inout URLRequest, origin: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        request.setValue("web", forHTTPHeaderField: "X-Client-Platform")
        switch self {
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .cookie(let value, let userAgent):
            request.setValue(value, forHTTPHeaderField: "Cookie")
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(origin, forHTTPHeaderField: "Origin")
            request.setValue("\(origin)/", forHTTPHeaderField: "Referer")
        }
    }
}

/// 领取签到结果
enum CheckinClaimResult {
    case claimed(credit: Int?, streakDays: Int?)
    case alreadySigned
}

/// WorkBuddy 签到 / 旅行 / 令牌刷新接口
final class APIClient {
    static let shared = APIClient()
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 40
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - 签到（域名以登录态 auth.domain 为准，勿硬编码其他域名）

    /// 今日签到状态（只读）
    func checkinStatus(domain: String, auth: AuthAttachment) async throws -> CheckinStatusSnapshot {
        let data = try await post(path: "/v2/billing/meter/checkin-activity-status",
                                  body: [:], domain: domain, auth: auth)
        let fields = try unwrap(data)
        func intField(_ names: [String]) -> Int? {
            for name in names {
                if let value = fields[name] as? Int { return value }
                if let text = fields[name] as? String, let value = Int(text) { return value }
            }
            return nil
        }
        return CheckinStatusSnapshot(
            todayCheckedIn: (fields["today_checked_in"] as? Bool) ?? false,
            streakDays: intField(["streak_days", "continuous_days"]),
            dailyCredit: intField(["daily_credit"]),
            balance: intField(["total_credits", "balance", "credit", "total_credit", "credits"])
        )
    }

    /// 领取今日签到（幂等：重复调用不会重复发积分）
    func dailyCheckin(domain: String, auth: AuthAttachment) async throws -> CheckinClaimResult {
        do {
            let data = try await post(path: "/v2/billing/meter/daily-checkin",
                                      body: [:], domain: domain, auth: auth)
            let fields = try unwrap(data)
            return .claimed(
                credit: (fields["credit"] as? Int) ?? (fields["add_credit"] as? Int),
                streakDays: fields["streak_days"] as? Int
            )
        } catch let error as APIError {
            // 已签到：HTTP 400 + code 10001，视为正常结果
            if case .http(let status, let body) = error,
               status == 400, body.contains("10001") {
                return .alreadySigned
            }
            if case .api(let code, _) = error, code == 10001 {
                return .alreadySigned
            }
            throw error
        }
    }

    // MARK: - 派猫猫旅行（域名不同、无 /v2 前缀）

    /// 旅行状态（只读）
    func travelStatus(domain: String, auth: AuthAttachment) async throws -> TravelSnapshot {
        let data = try await get(path: "/activity/growth/buddy/travel/status",
                                 domain: domain, auth: auth)
        let fields = try unwrap(data)
        let location = fields["location"] as? [String: Any]
        return TravelSnapshot(
            state: .init(raw: fields["state"] as? String),
            locationName: (location?["name"] as? String) ?? (fields["location_name"] as? String),
            rewardCredit: fields["reward_credit"] as? Int,
            arriveAtSeconds: Self.unixSeconds(fields["arrive_at"]),
            dailyLimitReached: (fields["daily_limit_reached"] as? Bool) ?? false
        )
    }

    /// 领取旅行积分（仅 arrived 状态可领）
    func travelClaim(domain: String, auth: AuthAttachment) async throws -> Int? {
        let data = try await post(path: "/activity/growth/buddy/travel/claim",
                                  body: [:], domain: domain, auth: auth)
        let fields = try unwrap(data)
        return (fields["credit"] as? Int) ?? (fields["reward_credit"] as? Int)
    }

    /// 派出 Buddy（locationId 1~4，收益完全相同；缺省随机）
    func travelDepart(domain: String, auth: AuthAttachment, locationId: Int? = nil) async throws {
        var body: [String: Any] = [:]
        if let locationId { body["location_id"] = locationId }
        _ = try await post(path: "/activity/growth/buddy/travel/depart",
                           body: body, domain: domain, auth: auth)
    }

    // MARK: - 长效令牌刷新（走官方插件网关）

    /// 用长效令牌换取新的接口令牌；返回 (新接口令牌, 轮换后的新长效令牌)
    func refreshAccessToken(refreshToken: String) async throws -> (accessToken: String, refreshToken: String) {
        guard let url = URL(string: "https://copilot.tencent.com/v2/plugin/auth/token/refresh") else {
            throw APIError.invalidURL("token/refresh")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(refreshToken, forHTTPHeaderField: "X-Refresh-Token")
        request.setValue("plugin", forHTTPHeaderField: "X-Auth-Refresh-Source")
        request.setValue("copilot.tencent.com", forHTTPHeaderField: "X-Domain")
        request.httpBody = try JSONSerialization.data(withJSONObject: [String: Any]())
        let (data, _) = try await perform(request, origin: "https://copilot.tencent.com")
        let fields = try unwrap(data)
        guard let accessToken = fields["accessToken"] as? String, !accessToken.isEmpty else {
            throw APIError.malformed("刷新响应缺少 accessToken")
        }
        let nextRefresh = (fields["refreshToken"] as? String) ?? refreshToken
        return (accessToken, nextRefresh)
    }

    // MARK: - 底层请求

    private func get(path: String, domain: String, auth: AuthAttachment) async throws -> Data {
        guard let url = URL(string: "https://\(domain)\(path)") else {
            throw APIError.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        auth.apply(to: &request, origin: "https://\(domain)")
        return try await perform(request, origin: "https://\(domain)")
    }

    private func post(path: String, body: [String: Any], domain: String,
                      auth: AuthAttachment) async throws -> Data {
        guard let url = URL(string: "https://\(domain)\(path)") else {
            throw APIError.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        auth.apply(to: &request, origin: "https://\(domain)")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request, origin: "https://\(domain)")
    }

    private func perform(_ request: URLRequest, origin: String) async throws -> Data {
        var request = request
        if request.value(forHTTPHeaderField: "Origin") == nil {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// 解析 {code, msg, data} 信封，校验业务码并返回 data 字段
    private func unwrap(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw APIError.malformed("响应不是 JSON 对象")
        }
        if let code = root["code"] as? Int, code != 0 {
            let msg = (root["msg"] as? String) ?? (root["message"] as? String) ?? "未知错误"
            if code == 401 || code == 10004 || msg.contains("登录") || msg.contains("token") {
                throw APIError.authFailed(msg)
            }
            throw APIError.api(code: code, msg: msg)
        }
        return (root["data"] as? [String: Any]) ?? [:]
    }

    private static func unixSeconds(_ value: Any?) -> TimeInterval? {
        if let number = value as? TimeInterval {
            return number > 1_000_000_000_000 ? number / 1000 : number
        }
        if let text = value as? String, let number = TimeInterval(text) {
            return number > 1_000_000_000_000 ? number / 1000 : number
        }
        return nil
    }
}
