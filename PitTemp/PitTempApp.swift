// PitTempApp.swift
import SwiftUI

@main
struct PitTempApp: App {
    @StateObject private var vm = SessionViewModel()
    @StateObject private var folderBM = FolderBookmark()
    @AppStorage("onboarded") private var onboarded: Bool = false

    // ← 追加：型推論が迷わないように中継ビューを用意
    @ViewBuilder
    private var root: some View {
        if onboarded {
            MainTabView()
                .environmentObject(vm)
                .environmentObject(folderBM)
        } else {
            WelcomeView(onContinue: {
                Haptics.impactLight()
                onboarded = true
            })
            .environmentObject(folderBM)
        }
    }

    var body: some Scene {
        WindowGroup { root }
    }
}
