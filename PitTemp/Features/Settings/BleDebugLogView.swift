import SwiftUI
import UIKit

/// BLE デバッグログをリアルタイムに眺めるビュー。
/// TR45/TR4A の SOH コマンド送受信や CRC エラーなどを確認できるようにし、
/// 学習の足場としても使えるようコメントを丁寧に残している。
struct BleDebugLogView: View {
    @EnvironmentObject var logStore: UILogStore

    private var bleEntries: [UILogEntry] {
        logStore.entries
            .filter { $0.category == .ble }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var clipboardText: String {
        bleEntries
            .map { entry in
                let time = DateFormatter.localizedString(from: entry.createdAt, dateStyle: .none, timeStyle: .medium)
                return "[\(time)] \(entry.level.rawValue.uppercased()) \(entry.message)"
            }
            .joined(separator: "\n")
    }

    var body: some View {
        List {
            if bleEntries.isEmpty {
                Label("No BLE log yet", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bleEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: entry.level.iconName)
                                .foregroundStyle(entry.level.tintColor)
                            Text(entry.createdAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // 実際のメッセージ。SOH フレームは 16進文字列で届くので、
                        // 次に何を送れば良いか学習しやすい形でそのまま表示する。
                        Text(entry.message)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("BLE Debug Log")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    logStore.clear(category: .ble)
                } label: {
                    Label("Clear", systemImage: "trash")
                }

                Button {
                    UIPasteboard.general.string = clipboardText
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(bleEntries.isEmpty)
            }
        }
    }
}

#Preview {
    let store = UILogStore()
    store.add(message: "Notify <- 01 33 00 04 00 06 aa bb cc dd", category: .ble)
    store.add(message: "Send TR4A current request: 00 01 33 00 04 00 00 00 00 00 7c 34", category: .ble)
    return NavigationStack { BleDebugLogView().environmentObject(store) }
}
