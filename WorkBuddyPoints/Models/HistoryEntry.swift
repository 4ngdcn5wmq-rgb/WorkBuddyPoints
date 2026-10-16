import Foundation

/// 一条执行记录（持久化为 documents/checkin-history.json）
struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var source: String
    var status: String
    var message: String
    var credit: Int?
    var streakDays: Int?
    var balance: Int?
    var travel: String?

    var sourceText: String {
        switch source {
        case "manual": return "手动"
        case "foreground": return "打开 App"
        case "background": return "后台任务"
        case "shortcut": return "快捷指令"
        default: return source
        }
    }

    var statusSymbol: String {
        switch status {
        case RunStatus.success.rawValue: return "checkmark.seal.fill"
        case RunStatus.alreadyCheckedIn.rawValue: return "clock.fill"
        case RunStatus.failed.rawValue: return "exclamationmark.triangle.fill"
        default: return "key.slash.fill"
        }
    }
}
