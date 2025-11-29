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
    @State private var intervalText: String = "2"
    @State private var actionMessage: String?
    @State private var showingActionAlert = false

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

                if bluetooth.isTR4AConnected {
                    tr4aControlSection
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
            .alert("TR45 control", isPresented: $showingActionAlert, actions: { Button("OK", role: .cancel) { } }, message: {
                Text(actionMessage ?? "")
            })
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

    private var tr4aControlSection: some View {
        Section("TR45 controls") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sampling interval (seconds)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("2", text: $intervalText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 80)
                    Button("Apply") {
                        let seconds = UInt16(intervalText) ?? 2
                        bluetooth.updateTR4ARecordInterval(seconds: seconds) { result in
                            actionMessage = resultMessage(result, success: "記録間隔を\(seconds)sに更新しました")
                            showingActionAlert = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("TR45は本体にボタンが無いため、BLE経由で記録間隔を変更します。設定テーブルを読み出してから書き戻す安全策を入れています。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("Record stop / power save") {
                bluetooth.powerOffTR4A { result in
                    actionMessage = resultMessage(result, success: "記録を停止しました（ソフト電源OFF）")
                    showingActionAlert = true
                }
            }
            .buttonStyle(.bordered)
            Text("TR45には物理スイッチが無いので、0x32 記録停止コマンドを電源OFF代わりに送信します。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func resultMessage(_ result: Result<Void, Error>, success: String) -> String {
        switch result {
        case .success: return success
        case .failure(let err): return err.localizedDescription
        }
    }
}
