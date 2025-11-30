import SwiftUI

/// BLE の内部ログを一覧表示し、フィールド検証時に「どのUUIDが見えているか」「どこで切断したか」を把握する補助画面。
struct BLEDebugLogView: View {
    @EnvironmentObject var bluetoothVM: BluetoothViewModel

    private var reversedLog: [BLEDebugLogEntry] {
        bluetoothVM.bleDebugLog.reversed()
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Button(role: .destructive) {
                        bluetoothVM.clearDebugLog()
                    } label: {
                        Label("Clear log", systemImage: "trash")
                    }

                    Spacer()

                    if let text = exportText(), !text.isEmpty {
                        ShareLink(item: text) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .buttonStyle(.borderless)
                .listRowInsets(EdgeInsets())

                Text("接続が切れる・Notifyが届かないなどの再現時に、ここで UUID やプロパティの差分を確認できます。ログは最大200件で古いものから消えます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Latest events (newest first)") {
                ForEach(reversedLog) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.createdAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.level.rawValue.uppercased())
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(levelTint(entry.level).opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Text(entry.message)
                            .font(.body.monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("BLE Debug Log")
    }

    /// シェア用に単純なテキストへまとめる。現場でのスクショ代わりに使える。
    private func exportText() -> String? {
        guard !bluetoothVM.bleDebugLog.isEmpty else { return nil }
        return bluetoothVM.bleDebugLog
            .map { "\($0.createdAt): [\($0.level.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }

    private func levelTint(_ level: BLEDebugLogEntry.Level) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
