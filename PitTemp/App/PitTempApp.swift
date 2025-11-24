import SwiftUI
import Combine

@main
struct PitTempApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var vm: SessionViewModel
    @StateObject private var folderBM: FolderBookmark
    @StateObject private var driveService = GoogleDriveService()
    @AppStorage("onboarded") private var onboarded: Bool = false
    @StateObject private var recorder = SessionRecorder()
    @StateObject private var ble: BluetoothService
    @StateObject private var registry: DeviceRegistry
    @StateObject private var bluetoothVM: BluetoothViewModel
    @StateObject private var uiLog: UILogStore
    @StateObject private var connectivity = ConnectivityMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let s = SettingsStore()
        let log = UILogStore()
        let autosave = SessionAutosaveStore(uiLogger: log)
        let folder = FolderBookmark()
        let ble = BluetoothService()
        let registry = DeviceRegistry()
        // CSV 書き出しから iCloud 共有フォルダ連携までを同じインスタンスで束ねる。
        let coordinator = SessionFileCoordinator(exporter: CSVExporter(), uploader: folder)
        _settings = StateObject(wrappedValue: s)
        _uiLog = StateObject(wrappedValue: log)
        _folderBM = StateObject(wrappedValue: folder)
        let vm = SessionViewModel(settings: s,
                                  autosaveStore: autosave,
                                  uiLog: log,
                                  fileCoordinator: coordinator)
        _vm = StateObject(wrappedValue: vm)
        _ble = StateObject(wrappedValue: ble)
        _registry = StateObject(wrappedValue: registry)
        _bluetoothVM = StateObject(wrappedValue: BluetoothViewModel(service: ble, registry: registry))

        // ViewModel 側で Combine のキャンセル管理を一元化する。
        vm.bindBluetooth(service: ble)
    }

    // ここで画面ツリーをまとめて返す
    @ViewBuilder
    private var root: some View {
        Group {
                MainTabView()
                    .environmentObject(vm)
                    .environmentObject(settings)
                    .environmentObject(folderBM)
                    .environmentObject(driveService)
                    .environmentObject(connectivity)
                    .environmentObject(bluetoothVM)
                    .environmentObject(registry)
                    .environmentObject(uiLog)
                    .onAppear { ble.registry = registry }
        }
        // 起動時に一度だけBLE→Recorderを結線
        .onAppear {
            let samples = ble.temperatureFrames
                .map { TemperatureSample(time: $0.time, value: $0.value) }
                .eraseToAnyPublisher()
            recorder.bind(to: samples)
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
