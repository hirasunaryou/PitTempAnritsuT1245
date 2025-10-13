//
//  connectView.swift
//  PitTemp
import SwiftUI

struct ConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ble: BluetoothService
    @EnvironmentObject var registry: DeviceRegistry

    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            List {
                // 現在の接続
                if let name = ble.deviceName {
                    Section("Connected") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name).font(.headline)
                                if let rec = registry.record(forName: name) {
                                    let label = (rec.alias?.isEmpty == false) ? rec.alias! : rec.name
                                    Text(label).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Disconnect") { ble.disconnect() }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                // スキャン一覧
                Section(header: header) {
                    ForEach(sortedScanned()) { dev in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: dev)).font(.body)
                                HStack(spacing: 8) {
                                    Text(dev.name).foregroundStyle(.secondary)
                                    Text("RSSI \(dev.rssi) dBm").foregroundStyle(.secondary)
                                    Text(rel(dev.lastSeenAt)).foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                            Spacer()
                            Button("Connect") {
                                ble.autoConnectOnDiscover = false // 明示接続なのでOFF推奨
                                ble.connect(deviceID: dev.id)
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
                    if isScanning {
                        Button("Stop") { ble.stopScan(); isScanning = false }
                    } else {
                        Button("Scan") { ble.startScan(); isScanning = true }
                    }
                }
            }
            .onAppear {
                isScanning = (ble.connectionState == .scanning)
            }
        }
    }

    private func sortedScanned() -> [ScannedDevice] {
        ble.scanned.sorted { a, b in
            if a.rssi != b.rssi { return a.rssi > b.rssi }
            return a.name < b.name
        }
    }

    private func displayName(for dev: ScannedDevice) -> String {
        // スキャンで得た表示名（dev.name）に対して、レジストリ側に alias があれば併記
        if let rec = registry.record(forName: dev.name), let alias = rec.alias, !alias.isEmpty {
            return "\(alias) (\(dev.name))"
        }
        return dev.name
    }

    private func rel(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 2 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        return "\(m)m ago"
    }

    private var header: some View {
        HStack {
            Text("Nearby")
            Spacer()
            Toggle("Auto-connect", isOn: Binding(
                get: { ble.autoConnectOnDiscover },
                set: { ble.autoConnectOnDiscover = $0 }
            ))
            .labelsHidden()
            .help("Connect automatically to the first matching device")
        }
    }
}
