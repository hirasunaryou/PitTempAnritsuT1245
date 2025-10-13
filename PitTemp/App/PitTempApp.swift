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
    
    init() {
        let s = SettingsStore()
        _settings = StateObject(wrappedValue: s)
        _vm = StateObject(wrappedValue: SessionViewModel(settings: s))
    }

    // ここで画面ツリーをまとめて返す
    @ViewBuilder
    private var root: some View {
        Group {
            if onboarded {
                MainTabView()
                    .environmentObject(vm)
                    .environmentObject(settings)
                    .environmentObject(folderBM)
                    .environmentObject(ble)
                    .environmentObject(registry)
            } else {
                WelcomeView(onContinue: {
                    Haptics.impactLight()
                    onboarded = true
                })
                .environmentObject(settings)
                .environmentObject(folderBM)
                .environmentObject(registry)
            }
        }
        // 起動時に一度だけBLE→Recorderを結線
        .onAppear {
            recorder.bind(to: ble.temperatureStream.eraseToAnyPublisher())
        }
    }

    var body: some Scene {
        WindowGroup { root }
    }
}
