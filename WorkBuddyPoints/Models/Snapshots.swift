import Foundation

/// 签到状态快照（来自 /v2/billing/meter/checkin-activity-status）
struct CheckinStatusSnapshot {
    var todayCheckedIn: Bool
    var streakDays: Int?
    var dailyCredit: Int?
    var balance: Int?
}

/// 派猫猫旅行状态快照（来自 /activity/growth/buddy/travel/status）
struct TravelSnapshot {
    enum State: String {
        case idle
        case traveling
        case arrived
        case unknown

        init(raw: String?) {
            self = State(rawValue: raw ?? "") ?? .unknown
        }
    }

    var state: State
    var locationName: String?
    var rewardCredit: Int?
    /// 到达时间（Unix 秒）
    var arriveAtSeconds: TimeInterval?
    var dailyLimitReached: Bool

    var stateText: String {
        switch state {
        case .idle: return "空闲中"
        case .traveling: return "旅行中"
        case .arrived: return "已到达，待领取"
        case .unknown: return "状态未知"
        }
    }

    /// 距到达剩余秒数（按本机时钟估算）
    var remainingSeconds: TimeInterval? {
        guard let arrive = arriveAtSeconds else { return nil }
        return arrive - Date().timeIntervalSince1970
    }
}

/// 一次执行的结论
enum RunStatus: String {
    case success = "签到成功"
    case alreadyCheckedIn = "今日已签到"
    case failed = "执行失败"
    case noCredential = "未配置凭据"

    var systemImage: String {
        switch self {
        case .success: return "checkmark.seal.fill"
        case .alreadyCheckedIn: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .noCredential: return "key.slash.fill"
        }
    }

    var colorName: String {
        switch self {
        case .success: return "green"
        case .alreadyCheckedIn: return "blue"
        case .failed: return "red"
        case .noCredential: return "orange"
        }
    }
}

/// 一次签到闭环的完整结果
struct RunOutcome {
    var date: Date = Date()
    var status: RunStatus
    var message: String
    var credit: Int?
    var streakDays: Int?
    var balance: Int?
    var travel: String?
    var source: String
}
