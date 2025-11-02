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
protocol SessionSettingsProviding {
    var validatedDurationSec: Int { get }
    var chartWindowSec: Double { get }
    var advanceWithGreater: Bool { get }
    var advanceWithRightArrow: Bool { get }
    var advanceWithReturn: Bool { get }
    var minAdvanceSec: Double { get }
    var zoneOrderSequence: [Zone] { get }
    var autofillDateTime: Bool { get }
}

@MainActor
final class SettingsStore: ObservableObject {

    // 既存キー（互換維持）
    @AppStorage("pref.durationSec") var durationSec: Int = 10
    @AppStorage("pref.chartWindowSec") var chartWindowSec: Double = 6
    @AppStorage("pref.advanceWithGreater") var advanceWithGreater: Bool = false
    @AppStorage("pref.advanceWithRightArrow") var advanceWithRightArrow: Bool = false
    @AppStorage("pref.advanceWithReturn") var advanceWithReturn: Bool = true
    @AppStorage("pref.minAdvanceSec") var minAdvanceSec: Double = 0.3
    @AppStorage("ble.autoConnect") var bleAutoConnect: Bool = true
    
    // ← zone順序は “Raw値” を保存して UI では型安全enumで扱う
    @AppStorage("pref.zoneOrder") private var zoneOrderRaw: Int = 0   // 0: IN-CL-OUT, 1: OUT-CL-IN

    // 自動補完や識別情報
    @AppStorage("pref.autofillDateTime") var autofillDateTime: Bool = true
    @AppStorage("hr2500.id") var hr2500ID: String = ""

    // 型安全enum（1つだけ定義）
    enum ZoneOrder: Int, CaseIterable, Identifiable {
        case in_cl_out = 0
        case out_cl_in = 1
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .in_cl_out: return "IN → CL → OUT"
            case .out_cl_in: return "OUT → CL → IN"
            }
        }
        var sequence: [Zone] {
            switch self {
            case .in_cl_out: return [.IN, .CL, .OUT]
            case .out_cl_in: return [.OUT, .CL, .IN]
            }
        }
    }

    /// UI用：enumで get/set（AppStorageのRaw値にブリッジ）
    var zoneOrderEnum: ZoneOrder {
        get { ZoneOrder(rawValue: zoneOrderRaw) ?? .in_cl_out }
        set { zoneOrderRaw = newValue.rawValue }
    }

    // 例：範囲バリデーション
    var validatedDurationSec: Int { max(1, min(durationSec, 60)) }
    
    // --- 追加: メタ入力モード ---
    @AppStorage("pref.metaInputMode") private var metaInputModeRaw: Int = 0
    enum MetaInputMode: Int, CaseIterable, Identifiable {
        case keyboard = 0
        case voice = 1
        var id: Int { rawValue }
        var label: String { self == .keyboard ? "Keyboard" : "Voice" }
    }
    var metaInputMode: MetaInputMode {
        get { MetaInputMode(rawValue: metaInputModeRaw) ?? .keyboard }
        set { metaInputModeRaw = newValue.rawValue }
    }
    
}

extension SettingsStore: SessionSettingsProviding {
    var zoneOrderSequence: [Zone] { zoneOrderEnum.sequence }
}
