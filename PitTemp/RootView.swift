//
//  RootView.swift
//  PitTemp
//
//  役割: 3つのタブをまとめるルート。Measure / Library / Settings
//  初心者向けメモ: 「最初に見える画面」をここで決めます。
//  TabView の中にそれぞれの画面を入れるだけの“薄い”Viewです。
//

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            MeasureView()
                .tabItem { Label("Measure", systemImage: "dot.radiowaves.left.and.right") }

            LibraryView()
                .tabItem { Label("Library", systemImage: "tray.full") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(FolderBookmark())
        .environmentObject(SessionViewModel())
}
