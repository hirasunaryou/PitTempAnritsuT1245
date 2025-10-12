//
//  ConnectView.swift
//  PitTemp
import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var ble: BluetoothService

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("State: \(stateText)")
                Spacer()
                if let name = ble.deviceName { Text(name).font(.callout).foregroundStyle(.secondary) }
            }
            HStack {
                Button(action: scanOrDisconnect) { Text(buttonTitle) }
                    .buttonStyle(.borderedProminent)
                Button("DATA") { ble.requestOnce() }
                Button("TIME") { ble.setDeviceTime() }
                Button("Poll 5Hz") { ble.startPolling(hz: 5) }
                Button("Stop") { ble.stopPolling() }
            }
        }
    }

    private var stateText: String {
        switch ble.connectionState {
        case .idle: "idle"
        case .scanning: "scanning"
        case .connecting: "connecting"
        case .ready: "ready"
        case .failed(let m): "failed: \(m)"
        }
    }
    private var buttonTitle: String {
        switch ble.connectionState {
        case .idle, .failed: "Scan"
        default: "Disconnect"
        }
    }
    private func scanOrDisconnect() {
        switch ble.connectionState {
        case .idle, .failed: ble.startScan()
        default: ble.disconnect()
        }
    }
}

