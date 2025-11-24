//
//  ConnectView.swift
//  PitTemp
//
//  役割: BLE デバイス一覧と接続・切断ボタンをまとめた1つの画面定義。
//  初学者メモ: 同名ファイルが複数あるとビルドエラーや混乱の原因になるため、
//  このファイルを唯一の ConnectView として残し、責務をここに集約します。
import SwiftUI

struct ConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bluetooth: BluetoothViewModel

    var body: some View {
        NavigationStack {
            List {
                // 現在の接続
                if let name = bluetooth.deviceName {
                    Section("Connected") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name).font(.headline)
                                if let label = bluetooth.connectedLabel(for: name) {
                                    Text(label).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Disconnect") { bluetooth.disconnect() }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                // スキャン一覧
                Section(header: header) {
                    ForEach(bluetooth.sortedScannedDevices()) { dev in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bluetooth.displayName(for: dev)).font(.body)
                                HStack(spacing: 8) {
                                    Text(dev.name).foregroundStyle(.secondary)
                                    Text("RSSI \(dev.rssi) dBm").foregroundStyle(.secondary)
                                    Text(bluetooth.relativeTimeDescription(since: dev.lastSeenAt)).foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                            Spacer()
                            Button("Connect") {
                                bluetooth.connect(to: dev.id)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if bluetooth.isScanning {
                        Button("Stop") { bluetooth.stopScan() }
                    } else {
                        Button("Scan") { bluetooth.startScan() }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Nearby")
            Spacer()
            Toggle("Auto-connect", isOn: Binding(
                get: { bluetooth.autoConnectOnDiscover },
                set: { bluetooth.updateAutoConnect(isEnabled: $0) }
            ))
            .labelsHidden()
            .help("Connect automatically to the first matching device")
        }
    }
}
