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
    let settings = SettingsStore()
    let log = UILogStore()
    let folder = FolderBookmark()
    let coordinator = SessionFileCoordinator(exporter: CSVExporter(), uploader: folder)
    let bluetooth = BluetoothService()
    let registry = DeviceRegistry()
    let bluetoothVM = BluetoothViewModel(service: bluetooth, registry: registry)
    let vm = SessionViewModel(settings: settings,
                              autosaveStore: SessionAutosaveStore(uiLogger: log),
                              uiLog: log,
                              fileCoordinator: coordinator)
    vm.bindBluetooth(service: bluetooth)
    return RootView()
        .environmentObject(folder)
        .environmentObject(vm)
        .environmentObject(settings)
        .environmentObject(bluetoothVM)
        .environmentObject(registry)
        .environmentObject(log)
}
