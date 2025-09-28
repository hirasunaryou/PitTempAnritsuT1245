import SwiftUI

@main
struct PitTempApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var vm: SessionViewModel
    @StateObject private var folderBM = FolderBookmark()
    @AppStorage("onboarded") private var onboarded: Bool = false

    init() {
        // 同じ SettingsStore を VM と View に共有する
        let s = SettingsStore()
        _settings = StateObject(wrappedValue: s)
        _vm = StateObject(wrappedValue: SessionViewModel(settings: s))
    }

    @ViewBuilder
    private var root: some View {
        if onboarded {
            MainTabView()
                .environmentObject(vm)
                .environmentObject(settings)   // ⬅️ 追加
                .environmentObject(folderBM)
        } else {
            WelcomeView(onContinue: {
                Haptics.impactLight()
                onboarded = true
            })
            .environmentObject(settings)      // ⬅️ 追加（必要に応じて）
            .environmentObject(folderBM)
        }
    }

    var body: some Scene { WindowGroup { root } }
}
