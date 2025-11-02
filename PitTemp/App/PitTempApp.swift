import SwiftUI

@main
struct PitTempApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var vm: SessionViewModel
    @StateObject private var folderBM = FolderBookmark()
    @AppStorage("onboarded") private var onboarded: Bool = false
    @StateObject private var recorder = SessionRecorder()
    @StateObject private var ble = BluetoothService()
    @StateObject private var registry = DeviceRegistry()
    @StateObject private var uiLog: UILogStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let s = SettingsStore()
        let log = UILogStore()
        let autosave = SessionAutosaveStore(uiLogger: log)
        _settings = StateObject(wrappedValue: s)
        _uiLog = StateObject(wrappedValue: log)
        _vm = StateObject(wrappedValue: SessionViewModel(settings: s,
                                                         autosaveStore: autosave,
                                                         uiLog: log))
    }

    // ここで画面ツリーをまとめて返す
    @ViewBuilder
    private var root: some View {
        Group {
                MainTabView()
                    .environmentObject(vm)
                    .environmentObject(settings)
                    .environmentObject(folderBM)
                    .environmentObject(ble)
                    .environmentObject(registry)
                    .environmentObject(uiLog)
                    .onAppear { ble.registry = registry }
        }
        // 起動時に一度だけBLE→Recorderを結線
        .onAppear {
            recorder.bind(to: ble.temperatureStream.eraseToAnyPublisher())
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { @MainActor in
                    vm.persistAutosaveNow()
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup { root }
    }
}
