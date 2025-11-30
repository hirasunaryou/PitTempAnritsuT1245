import SwiftUI

/// BLE-DEBUG カテゴリのログをアプリ内で確認するビュー。
struct BLELogView: View {
    @EnvironmentObject var uiLog: UILogStore

    var body: some View {
        List(filteredEntries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.message)
                        .font(.footnote)
                    Spacer()
                    Text(entry.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("BLE Log")
    }

    private var filteredEntries: [UILogEntry] {
        Array(uiLog.entries.filter { $0.category == .ble }.suffix(500))
    }
}
