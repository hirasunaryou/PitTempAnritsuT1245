//
//  DeviceRegistryMocks.swift
//  PitTemp
//
//  単体テストやプレビューで UserDefaults に書き込まずに動作確認するためのモック群。
//  実サービスとの差は「永続性がない」点だけに留め、API 形状は同じに保っている。

import Foundation

/// インメモリ実装。テストで保存内容を追跡しやすいよう、最後に保存された配列も公開する。
final class InMemoryDeviceRegistryStore: DeviceRegistryStoring {
    private(set) var lastSavedRecords: [DeviceRecord] = []
    private var seed: [DeviceRecord]

    init(seed: [DeviceRecord] = []) {
        self.seed = seed
        self.lastSavedRecords = seed
    }

    func loadRecords() -> [DeviceRecord] {
        seed
    }

    func saveRecords(_ records: [DeviceRecord]) {
        // UserDefaults 版と同じく「配列丸ごと置き換え」を想定。
        seed = records
        lastSavedRecords = records
    }
}

/// SettingsStore を差し替えたい場合に使う簡易モック。
/// - 設定値を var で公開しつつ SessionSettingsProviding を実装するため、ViewModel にもそのまま渡せる。
@MainActor
final class MockSettingsStore: ObservableObject, SessionSettingsProviding {
    var validatedAutoStopLimitSec: Int = 20
    var chartWindowSec: Double = 6
    var advanceWithGreater: Bool = false
    var advanceWithRightArrow: Bool = false
    var advanceWithReturn: Bool = true
    var minAdvanceSec: Double = 0.3
    var zoneOrderSequence: [Zone] = [.IN, .CL, .OUT]
    var autofillDateTime: Bool = true
    var enableICloudUpload: Bool = true
}
