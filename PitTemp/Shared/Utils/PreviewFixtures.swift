//  PreviewFixtures.swift
//  PitTemp
//  Role: SwiftUI プレビュー用の依存関係をまとめて立ち上げるセットアップ。
//  Dependencies: SettingsStore・SessionViewModel などアプリ主要コンポーネント。
//  Threading: MainActor で UI ステートを扱い、プレビューでも実アプリ同等の挙動を再現。

import Foundation
import SwiftUI

/// Reusable fixtures for previews and UI snapshot tests.
@MainActor
struct MeasureViewPreviewFixtures {
    let settings: SettingsStore
    let logStore: UILogStore
    let autosave: SessionAutosaveStore
    let viewModel: SessionViewModel
    let folderBookmark: FolderBookmark
    let bluetooth: BluetoothService
    let bluetoothVM: BluetoothViewModel
    let registry: DeviceRegistry
    let registrationStore: TR4ARegistrationStore
    let driveService: GoogleDriveService
    let connectivity: ConnectivityMonitor

    init() {
        settings = SettingsStore()
        logStore = UILogStore()
        autosave = SessionAutosaveStore(uiLogger: logStore)
        viewModel = SessionViewModel(settings: settings,
                                     autosaveStore: autosave,
                                     uiLog: logStore)
        folderBookmark = FolderBookmark()
        registrationStore = TR4ARegistrationStore()
        bluetooth = BluetoothService(uiLogger: logStore, registrationStore: registrationStore)
        registry = DeviceRegistry()
        bluetoothVM = BluetoothViewModel(service: bluetooth, registry: registry)
        driveService = GoogleDriveService()
        connectivity = ConnectivityMonitor()

        // Previews also bind to BLE so charts refresh just like the app.
        viewModel.bindBluetooth(service: bluetooth)

        configureSamples()
    }

    private func configureSamples() {
        viewModel.wheelMemos[.FL] = "Front left is trending hot; monitor camber."
        viewModel.commitManualValue(wheel: .FL, zone: .OUT, value: 85.2)
        viewModel.commitManualValue(wheel: .FL, zone: .CL, value: 82.6)
        viewModel.commitManualValue(wheel: .FL, zone: .IN, value: 79.8)
        viewModel.commitManualValue(wheel: .FR, zone: .OUT, value: 76.4)
        viewModel.commitManualValue(wheel: .FR, zone: .CL, value: 74.9)
        viewModel.commitManualValue(wheel: .FR, zone: .IN, value: 73.1)

        bluetooth.deviceName = "AnritsuM-Preview"
        bluetooth.notifyHz = 4.8
        bluetooth.notifyCountUI = 512
        bluetooth.latestTemperature = 84.1

        viewModel.ingestBluetoothSample(
            TemperatureSample(time: Date(), value: 84.1)
        )
    }
}
