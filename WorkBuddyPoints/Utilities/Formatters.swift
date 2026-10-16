import Foundation

enum Fmt {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func int(_ value: Int?) -> String {
        value.map { String($0) } ?? "—"
    }

    static func clock(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", max(0, min(23, hour)), max(0, min(59, minute)))
    }

    static func countdown(from seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "即将到达" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "约 \(hours) 小时 \(minutes) 分后到达" }
        return "约 \(max(minutes, 1)) 分钟后到达"
    }
}
