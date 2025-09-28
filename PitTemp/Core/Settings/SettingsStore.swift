//
//  SettingsStore.swift
//  Core/Settings
//
//  目的: 画面やVMに散らばった @AppStorage を一元管理して、型安全＆拡張しやすくする。
//  ポイント:
//   - 既存キー名をそのまま使用（互換性維持）
//   - 必要に応じてバリデーションや enum ラッパーをここで行う
//

import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {

    // ==== 既存キー（互換維持） ====
    @AppStorage("pref.durationSec") var durationSec: Int = 10
    @AppStorage("pref.zoneOrder") var zoneOrderRaw: Int = 0        // 0: IN-CL-OUT, 1: OUT-CL-IN
    @AppStorage("pref.chartWindowSec") var chartWindowSec: Double = 6
    @AppStorage("pref.advanceWithGreater") var advanceWithGreater: Bool = false
    @AppStorage("pref.advanceWithRightArrow") var advanceWithRightArrow: Bool = false
    @AppStorage("pref.advanceWithReturn") var advanceWithReturn: Bool = true
    @AppStorage("pref.minAdvanceSec") var minAdvanceSec: Double = 0.3

    // 自動補完や識別情報
    @AppStorage("pref.autofillDateTime") var autofillDateTime: Bool = true
    @AppStorage("hr2500.id") var hr2500ID: String = ""

    // ==== 型安全ラッパー ====
    enum ZoneOrder: Int {
        case in_cl_out = 0
        case out_cl_in = 1
    }
    var zoneOrder: ZoneOrder {
        get { ZoneOrder(rawValue: zoneOrderRaw) ?? .in_cl_out }
        set { zoneOrderRaw = newValue.rawValue }
    }

    // 必要に応じて、範囲バリデーションを追加（例）
    var validatedDurationSec: Int {
        max(1, min(durationSec, 60))
    }
}
