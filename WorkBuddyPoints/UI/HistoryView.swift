import SwiftUI

struct HistoryView: View {
    @StateObject private var store = HistoryStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableCompat(
                        title: "还没有记录",
                        message: "配置凭据后，签到结果会自动记录在这里"
                    )
                } else {
                    List {
                        ForEach(store.entries) { entry in
                            row(entry)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("执行记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空", role: .destructive) {
                        store.clear()
                    }
                    .disabled(store.entries.isEmpty)
                }
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: entry.statusSymbol)
                    .foregroundStyle(tint(for: entry.status))
                Text(entry.status)
                    .font(.headline)
                Spacer()
                Text("\(entry.sourceText) · \(Fmt.dateTime.string(from: entry.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let travel = entry.travel, !travel.isEmpty {
                Text(travel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let credit = entry.credit {
                    Text("积分 +\(credit)")
                        .foregroundStyle(.green)
                }
                if let streak = entry.streakDays {
                    Text("连续 \(streak) 天")
                }
                if let balance = entry.balance {
                    Text("余额 \(balance)")
                }
            }
            .font(.caption.weight(.medium))
        }
        .padding(.vertical, 2)
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

/// iOS 16 兼容的空状态视图（不依赖 iOS 17 的 ContentUnavailableView）
struct ContentUnavailableCompat: View {
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
