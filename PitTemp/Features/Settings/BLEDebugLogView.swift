//
//  BLEDebugLogView.swift
//  PitTemp
//
//  TR45/TR4A向けに送受信したSOHフレームを確認するデバッグ画面。
//  UILogStore(Category.ble) を流用し、コピー＆クリア操作を用意。
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct BLEDebugLogView: View {
    @EnvironmentObject var uiLog: UILogStore

    private var bleEntries: [UILogEntry] {
        uiLog.entries.filter { $0.category == .ble }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if bleEntries.isEmpty {
                emptyState
            } else {
                List(bleEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: entry.level.iconName)
                                .foregroundStyle(entry.level.tintColor)
                            Text(entry.createdAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
            Spacer(minLength: 0)
            HStack {
                #if canImport(UIKit)
                Button {
                    UIPasteboard.general.string = bleEntries.map { "\($0.createdAt): \($0.message)" }.joined(separator: "\n")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(bleEntries.isEmpty)
                #endif

                Spacer()

                Button(role: .destructive) { uiLog.clear() } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(bleEntries.isEmpty)
            }
            .padding()
        }
        .navigationTitle("BLE Debug Log")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No BLE frames logged yet")
                .font(.headline)
            Text("Connect to a TR45/TR4A device to see 0x68/0x33/0x76 frames here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    let store = UILogStore()
    store.publish(UILogEntry(message: "[BLE] TX cmd=0x68 payload=0500", level: .info, category: .ble))
    store.publish(UILogEntry(message: "[BLE] RX cmd=0x68 status=06 payload=...", level: .success, category: .ble))
    return NavigationStack { BLEDebugLogView().environmentObject(store) }
}
