import SwiftUI

/// TR45 の簡易設定画面。記録間隔・モード・セキュリティ・開始/停止を SOH コマンドで送る。
struct TR45DeviceSettingsView: View {
    @EnvironmentObject var bluetoothVM: BluetoothViewModel

    @State private var intervalSec: Int = 1
    @State private var mode: TR4ARecordingMode = .endless
    @State private var securityOn: Bool = false
    @State private var startRecording: Bool = true

    var body: some View {
        Form {
            statusSection
            commandSection
            helpSection
        }
        .onAppear { seedFromSnapshot() }
        .navigationTitle("TR45 Device Settings")
    }

    private var statusSection: some View {
        Section("Current status") {
            if let snap = bluetoothVM.tr4aSnapshot {
                Label("Interval: \(snap.recordingIntervalSec.map { "\($0)s" } ?? "--")", systemImage: "timer")
                Label("Mode: \(snap.recordingMode?.label ?? "--")", systemImage: "repeat")
                Label("Recording: \((snap.isRecording ?? false) ? "ON" : "OFF")", systemImage: "record.circle")
                Label("Security: \((snap.securityOn ?? false) ? "ON" : "OFF")", systemImage: "lock")
                if let err = snap.lastError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("まだデバイスから設定を取得できていません。Refresh をタップしてください。")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Refresh") { bluetoothVM.refreshTR4AStatus() }
                Spacer()
                Button("Apply from UI") {
                    let request = TR4ADeviceSettingsRequest(recordingIntervalSec: intervalSec,
                                                            recordingMode: mode,
                                                            enableSecurity: securityOn,
                                                            startRecording: startRecording)
                    bluetoothVM.applyTR4A(settings: request)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var commandSection: some View {
        Section("Write settings") {
            Stepper(value: $intervalSec, in: 1...3600, step: 1) {
                Text("Recording interval: \(intervalSec) sec")
            }

            Picker("Recording mode", selection: $mode) {
                ForEach(TR4ARecordingMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }

            Toggle("Security ON", isOn: $securityOn)
            Toggle("Start recording after apply", isOn: $startRecording)
        }
    }

    private var helpSection: some View {
        Section {
            Text("設定を書き込むと、記録条件取得コマンドで読み直し UI を更新します。状態ビットやエラーは BLE ログ画面にも残るため、応答がない場合の切り分けに活用してください。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func seedFromSnapshot() {
        guard let snap = bluetoothVM.tr4aSnapshot else { return }
        if let interval = snap.recordingIntervalSec { intervalSec = interval }
        if let m = snap.recordingMode { mode = m }
        if let sec = snap.securityOn { securityOn = sec }
        if let rec = snap.isRecording { startRecording = rec }
    }
}

