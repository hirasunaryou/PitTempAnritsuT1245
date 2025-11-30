import SwiftUI

/// BLE-DEBUG カテゴリの UILog を一覧表示するビュー。
struct BLEDebugLogView: View {
    @EnvironmentObject var uiLog: UILogStore

    var filtered: [UILogEntry] {
        uiLog.entries.filter { $0.category == .ble }
    }

    var body: some View {
        List(filtered.reversed()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: entry.level.iconName)
                        .foregroundStyle(entry.level.tintColor)
                    Text(entry.createdAt.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(entry.message)
                    .font(.body.monospaced())
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("BLE Debug Log")
        .toolbar { Button("Clear") { uiLog.clear() } }
    }
}

