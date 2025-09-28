//
//  MainTabView.swift
//  PitTemp
//
// MainTabView.swift

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var vm: SessionViewModel

    @State private var sel = 0
    var body: some View {
        TabView(selection: $sel) {
            MeasureView().tabItem { Label("Measure", systemImage: "dot.scope") }.tag(0)
            LibraryView().tabItem { Label("Library", systemImage: "table") }.tag(1)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .onChange(of: sel) { _, newVal in
            // 計測タブ以外では HID を確実停止
            if newVal != 0 { vm.stopAll() }
        }
    }
}
