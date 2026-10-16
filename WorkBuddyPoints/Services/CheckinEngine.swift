import Foundation

/// 每日签到闭环：解析凭据 → 查状态 → 领签到 → 派猫猫旅行闭环 → 记录。
/// 全部接口均为幂等操作，重复执行不会重复发积分。
@MainActor
final class CheckinEngine {
    static let shared = CheckinEngine()

    private let api = APIClient.shared

    private init() {}

    /// 触发来源：manual / foreground / background / shortcut
    func runDaily(includeTravel: Bool, source: String) async -> RunOutcome {
        let credential = await CredentialStore.shared.snapshot()

        guard credential.isConfigured else {
            let outcome = RunOutcome(
                status: .noCredential,
                message: "尚未配置凭据，请先在「设置」里填写",
                credit: nil, streakDays: nil, balance: nil, travel: nil, source: source
            )
            await HistoryStore.shared.add(outcome)
            return outcome
        }

        do {
            let auth = try Self.authAttachment(for: credential)
            let domain = normalizedDomain(credential.checkinDomain, fallback: "www.codebuddy.cn")

            let status = try await api.checkinStatus(domain: domain, auth: auth)
            CredentialStore.shared.markAuthOK()
            var travelMessage: String?

            let outcome: RunOutcome
            if status.todayCheckedIn {
                outcome = RunOutcome(
                    status: .alreadyCheckedIn,
                    message: "今天已签到，明天再来",
                    credit: nil, streakDays: status.streakDays, balance: status.balance,
                    travel: nil, source: source
                )
            } else {
                switch try await api.dailyCheckin(domain: domain, auth: auth) {
                case .alreadySigned:
                    outcome = RunOutcome(
                        status: .alreadyCheckedIn,
                        message: "今天已签到，明天再来",
                        credit: nil, streakDays: status.streakDays, balance: status.balance,
                        travel: nil, source: source
                    )
                case .claimed(let credit, let streak):
                    var message = "签到成功" + (credit.map { "，积分 +\($0)" } ?? "")
                    if let streak { message += "，已连续 \(streak) 天" }
                    outcome = RunOutcome(
                        status: .success,
                        message: message,
                        credit: credit, streakDays: streak, balance: status.balance,
                        travel: nil, source: source
                    )
                }
            }

            if includeTravel {
                travelMessage = await runTravelLoop(domain: credential.travelDomain, auth: auth)
            }

            var final = outcome
            final.travel = travelMessage
            await HistoryStore.shared.add(final)
            return final
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if (error as? APIError)?.isAuthFailure == true {
                CredentialStore.shared.markAuthFailed()
            }
            let outcome = RunOutcome(
                status: .failed,
                message: message,
                credit: nil, streakDays: nil, balance: nil, travel: nil, source: source
            )
            await HistoryStore.shared.add(outcome)
            return outcome
        }
    }

    /// 旅行闭环：arrived 先领 → idle 且未达上限再派出。不会丢积分（arrived 会一直保留）。
    private func runTravelLoop(domain: String, auth: AuthAttachment) async -> String? {
        let travelDomain = normalizedDomain(domain, fallback: "www.workbuddy.cn")
        guard let snapshot = try? await api.travelStatus(domain: travelDomain, auth: auth),
              snapshot.state != .unknown else {
            return nil
        }

        var messages: [String] = []
        do {
            if snapshot.state == .arrived {
                if let credit = try await api.travelClaim(domain: travelDomain, auth: auth) {
                    messages.append("旅行积分 +\(credit)")
                } else {
                    messages.append("已领取旅行积分")
                }
            }
            let current = snapshot.state == .arrived
                ? (try? await api.travelStatus(domain: travelDomain, auth: auth)) ?? snapshot
                : snapshot
            if current.state == .idle, !current.dailyLimitReached {
                try await api.travelDepart(domain: travelDomain, auth: auth)
                messages.append("已派出 Buddy 旅行")
            }
        } catch {
            // 旅行失败不影响签到结果，仅记录
            messages.append("旅行环节跳过（\(((error as? LocalizedError)?.errorDescription ?? "\(error)"))）")
        }
        return messages.isEmpty ? nil : messages.joined(separator: "；")
    }

    // MARK: - 工具

    static func authAttachment(for credential: Credential) throws -> AuthAttachment {
        switch credential.mode {
        case .refreshToken:
            throw APIError.authFailed("长效令牌需先刷新，请重试一次签到")
        case .bearer:
            let token = credential.bearerToken.trimmed
            guard !token.isEmpty else { throw APIError.authFailed("缺少 Bearer 令牌") }
            return .bearer(token)
        case .cookie:
            let cookie = credential.cookie.trimmed
            guard !cookie.isEmpty else { throw APIError.authFailed("缺少 Cookie") }
            let ua = credential.userAgent.trimmed.isEmpty
                ? AuthCodeParser.fallbackUserAgent
                : credential.userAgent.trimmed
            return .cookie(cookie, userAgent: ua)
        }
    }

    /// 解析凭据（必要时先刷新长效令牌换取接口令牌）
    static func resolveAuth(_ credential: Credential) async throws -> AuthAttachment {
        if credential.mode == .refreshToken {
            let token = credential.refreshToken.trimmed
            guard !token.isEmpty else { throw APIError.authFailed("缺少长效令牌") }
            let refreshed = try await APIClient.shared.refreshAccessToken(refreshToken: token)
            await CredentialStore.shared.updateRefreshToken(refreshed.refreshToken)
            return .bearer(refreshed.accessToken)
        }
        return try authAttachment(for: credential)
    }

    private func normalizedDomain(_ value: String, fallback: String) -> String {
        let text = AuthCodeParser.host(fromOrigin: value)
        return text.isEmpty ? fallback : text
    }
}
