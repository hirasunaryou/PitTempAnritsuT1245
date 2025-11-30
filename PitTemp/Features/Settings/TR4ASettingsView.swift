import SwiftUI

/// TR45 の現在設定や登録コードをまとめて編集できるフォーム。
struct TR4ASettingsView: View {
    @EnvironmentObject var bluetooth: BluetoothViewModel
    @EnvironmentObject var registrationStore: RegistrationCodeStore
    @EnvironmentObject var uiLog: UILogStore

    @State private var registrationInput: String = ""
    @State private var intervalSelection: Double = 1
    @State private var endlessMode: Bool = true

    var body: some View {
        Form {
            Section("Device status") {
                if let state = bluetooth.tr4aState {
                    HStack { Text("Recording"); Spacer(); Text(state.isRecording == true ? "ON" : "OFF") }
                    HStack { Text("Security"); Spacer(); Text(state.securityEnabled == true ? "ON" : "OFF") }
                    HStack { Text("Interval"); Spacer(); Text("\(state.loggingIntervalSec ?? 0)s") }
                    HStack { Text("Mode"); Spacer(); Text(state.recordingModeEndless == false ? "One time" : "Endless") }
                } else {
                    Text("No TR4A state yet. Connect to TR45 and refresh.")
                        .foregroundStyle(.secondary)
                }
                Button("Refresh from device") { bluetooth.refreshTR4ASettings() }
            }

            Section("Recording") {
                Stepper(value: $intervalSelection, in: 1...60, step: 1) {
                    Text("Interval: \(Int(intervalSelection)) sec")
                }
                Toggle("Endless mode", isOn: $endlessMode)
                HStack {
                    Button("Apply interval/mode") {
                        bluetooth.updateTR4ARecording(interval: UInt8(intervalSelection), endless: endlessMode)
                    }
                    Spacer()
                    Button("Start") { bluetooth.startTR4ARecording() }
                    Button("Stop", role: .destructive) { bluetooth.stopTR4ARecording() }
                }
            }

            Section("Registration code") {
                TextField("8-digit code", text: $registrationInput)
                    .keyboardType(.numberPad)
                Button("Save & send to device") {
                    bluetooth.sendTR4APasscode(registrationInput)
                    let key = bluetooth.currentPeripheralID ?? (bluetooth.deviceName ?? "unknown")
                    registrationStore.save(code: registrationInput, for: key)
                }
                if !registrationStore.codes.isEmpty {
                    ForEach(registrationStore.codes.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.key).font(.caption)
                            Text(entry.value)
                        }
                    }
                }
            }

            Section("Logs") {
                NavigationLink("Open BLE log") {
                    BLELogView()
                        .environmentObject(uiLog)
                }
            }
        }
        .navigationTitle("TR4A")
        .onAppear { bluetooth.refreshTR4ASettings() }
    }
}
