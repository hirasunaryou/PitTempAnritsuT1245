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
    @StateObject private var ble = BluetoothService()
    @StateObject private var registry = DeviceRegistry()
    @StateObject private var uiLog: UILogStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let s = SettingsStore()
        let log = UILogStore()
        let autosave = SessionAutosaveStore(uiLogger: log)
        let folder = FolderBookmark()
        // CSV 書き出しから iCloud 共有フォルダ連携までを同じインスタンスで束ねる。
        let coordinator = SessionFileCoordinator(exporter: CSVExporter(), uploader: folder)
        _settings = StateObject(wrappedValue: s)
        _uiLog = StateObject(wrappedValue: log)
        _folderBM = StateObject(wrappedValue: folder)
        _vm = StateObject(wrappedValue: SessionViewModel(settings: s,
                                                         autosaveStore: autosave,
                                                         uiLog: log,
                                                         fileCoordinator: coordinator))
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
                    .environmentObject(ble)
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
