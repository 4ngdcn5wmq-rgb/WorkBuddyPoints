import Foundation

/// 执行记录存储（documents/checkin-history.json，最多保留 300 条）
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = directory.appendingPathComponent("checkin-history.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    func add(_ outcome: RunOutcome) {
        let entry = HistoryEntry(
            date: outcome.date,
            source: outcome.source,
            status: outcome.status.rawValue,
            message: outcome.message,
            credit: outcome.credit,
            streakDays: outcome.streakDays,
            balance: outcome.balance,
            travel: outcome.travel
        )
        entries.insert(entry, at: 0)
        if entries.count > 300 {
            entries = Array(entries.prefix(300))
        }
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    func entry(on day: Date) -> HistoryEntry? {
        let calendar = Calendar.current
        return entries.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// 今日是否需要自动补跑（没跑过，或最近一次失败了）
    func shouldAutoRunNow(credential: Credential) -> Bool {
        guard credential.autoRunEnabled, credential.isConfigured else { return false }
        guard let today = entry(on: Date()) else { return true }
        return today.status == RunStatus.failed.rawValue
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
