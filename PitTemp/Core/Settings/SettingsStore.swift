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
    var validatedAutoStopLimitSec: Int { get }
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

    init() {
        migrateMetaVoiceKeywordsIfNeeded()
    }

    // 既存キー（互換維持）
    @AppStorage("pref.durationSec") var autoStopLimitSec: Int = 20
    @AppStorage("pref.chartWindowSec") var chartWindowSec: Double = 6
    @AppStorage("pref.advanceWithGreater") var advanceWithGreater: Bool = false
    @AppStorage("pref.advanceWithRightArrow") var advanceWithRightArrow: Bool = false
    @AppStorage("pref.advanceWithReturn") var advanceWithReturn: Bool = true
    @AppStorage("pref.minAdvanceSec") var minAdvanceSec: Double = 0.3
    @AppStorage("ble.autoConnect") var bleAutoConnect: Bool = true
    @AppStorage("pref.enableWheelVoiceInput") var enableWheelVoiceInput: Bool = false
    // 高齢の計測者向けに iPad mini を渡す運用があるため、大きな数字に切り替える設定を用意する。
    @AppStorage("pref.enableSeniorLayout") var enableSeniorLayout: Bool = false
    // シニアレイアウト時に「さらに大きく/少しだけ大きく」など、利用者が好みで調整できるスケール係数。
    // Double で保存しつつ getter でクランプすることで、不正値が入っても UI 崩れを防ぐ。
    @AppStorage("pref.senior.zoneFontScale") private var seniorZoneFontScaleRaw: Double = 1.0
    @AppStorage("pref.senior.chipFontScale") private var seniorChipFontScaleRaw: Double = 1.0
    @AppStorage("pref.senior.liveFontScale") private var seniorLiveFontScaleRaw: Double = 1.0

    // ← zone順序は “Raw値” を保存して UI では型安全enumで扱う
    @AppStorage("pref.zoneOrder") private var zoneOrderRaw: Int = 0   // 0: IN-CL-OUT, 1: OUT-CL-IN

    // 自動補完や識別情報
    @AppStorage("pref.autofillDateTime") var autofillDateTime: Bool = true
    @AppStorage("hr2500.id") var hr2500ID: String = ""

    // クラウド連携の有効/無効
    @AppStorage("cloud.enableICloudUpload") var enableICloudUpload: Bool = true
    @AppStorage("cloud.enableDriveUpload") var enableGoogleDriveUpload: Bool = false

    enum MetaVoiceField: String, CaseIterable, Identifiable {
        case track, date, time, car, driver, tyre, lap, checker
        var id: String { rawValue }
        var label: String {
            switch self {
            case .track: return "Track"
            case .date: return "Date"
            case .time: return "Time"
            case .car: return "Car"
            case .driver: return "Driver"
            case .tyre: return "Tyre"
            case .lap: return "Lap"
            case .checker: return "Checker"
            }
        }
    }

    private static let legacyCarKeywords = ["car", "カー", "車", "クルマ", "車両", "ゼッケン", "ゼッケン番号", "エントリー番号", "ナンバー", "番号"]
    private static let legacyDriverKeywords = ["driver", "ドライバー", "レーサー", "ライダー", "運転手"]

    static let defaultMetaVoiceKeywords: [MetaVoiceField: [String]] = [
        .track: ["track", "コース", "トラック", "サーキット", "レース会場"],
        .date: ["date", "日付", "日にち"],
        .time: ["time", "時刻", "タイム"],
        .car: ["car", "カー", "車", "クルマ", "車両", "ゼッケン", "ゼッケン番号", "エントリー番号", "ナンバー", "番号", "石鹸"],
        .driver: ["driver", "ドライバー", "ドライバ", "レーサー", "ライダー", "運転手"],
        .tyre: ["tyre", "タイヤ", "タイア", "タイヤ種"],
        .lap: ["lap", "ラップ", "周回", "周回数"],
        .checker: ["checker", "チェッカー", "担当", "記録者", "計測者", "測定者", "確認者"]
    ]

    @AppStorage("pref.metaKeyword.track") private var metaKeywordTrackRaw: String = defaultMetaVoiceKeywords[.track]!.joined(separator: ", ")
    @AppStorage("pref.metaKeyword.date") private var metaKeywordDateRaw: String = defaultMetaVoiceKeywords[.date]!.joined(separator: ", ")
    @AppStorage("pref.metaKeyword.time") private var metaKeywordTimeRaw: String = defaultMetaVoiceKeywords[.time]!.joined(separator: ", ")
    @AppStorage("pref.metaKeyword.car") private var metaKeywordCarRaw: String = defaultMetaVoiceKeywords[.car]!.joined(separator: ", ")
    @AppStorage("pref.metaKeyword.driver") private var metaKeywordDriverRaw: String = defaultMetaVoiceKeywords[.driver]!.joined(separator: ", ")
    @AppStorage("pref.metaKeyword.tyre") private var metaKeywordTyreRaw: String = defaultMetaVoiceKeywords[.tyre]!.joined(separator: ", ")
    @AppStorage("pref.metaKeyword.lap") private var metaKeywordLapRaw: String = defaultMetaVoiceKeywords[.lap]!.joined(separator: ", ")
    @AppStorage("pref.metaKeyword.checker") private var metaKeywordCheckerRaw: String = defaultMetaVoiceKeywords[.checker]!.joined(separator: ", ")

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
    var validatedAutoStopLimitSec: Int { max(1, min(autoStopLimitSec, 120)) }
    
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

    // MARK: - シニアレイアウトのカスタム倍率（クランプ付き）

    /// ゾーン値の拡大倍率。0.8〜2.0 の範囲で丸めることで「小さく戻しすぎ」「大きくしすぎ」を防ぐ。
    var seniorZoneFontScale: Double {
        get { clampedScale(seniorZoneFontScaleRaw) }
        set { seniorZoneFontScaleRaw = clampedScale(newValue) }
    }

    /// 要約チップ値の拡大倍率。同様にクランプして UI の破綻を防ぐ。
    var seniorChipFontScale: Double {
        get { clampedScale(seniorChipFontScaleRaw) }
        set { seniorChipFontScaleRaw = clampedScale(newValue) }
    }

    /// ライブ温度バッジの拡大倍率。瞬間値をどこまで強調するかを利用者が決められる。
    var seniorLiveFontScale: Double {
        get { clampedScale(seniorLiveFontScaleRaw) }
        set { seniorLiveFontScaleRaw = clampedScale(newValue) }
    }

    func metaVoiceKeywords(for field: MetaVoiceField) -> [String] {
        let raw = keywordText(for: field)
        let fallback = Self.defaultMetaVoiceKeywords[field] ?? []
        let source = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : parseKeywordList(raw)
        let lowered = source.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return lowered.isEmpty ? fallback : lowered
    }

    func defaultMetaVoiceKeywords(for field: MetaVoiceField) -> [String] {
        Self.defaultMetaVoiceKeywords[field] ?? []
    }

    func bindingForMetaVoiceKeyword(field: MetaVoiceField) -> Binding<String> {
        Binding(
            get: { self.keywordText(for: field) },
            set: { self.setKeywordText(self.normalizeKeywordInput($0), for: field) }
        )
    }

    func resetMetaVoiceKeywords() {
        for field in MetaVoiceField.allCases {
            setKeywordText(Self.defaultMetaVoiceKeywords[field]?.joined(separator: ", ") ?? "", for: field)
        }
    }

    private func keywordText(for field: MetaVoiceField) -> String {
        switch field {
        case .track: return metaKeywordTrackRaw
        case .date: return metaKeywordDateRaw
        case .time: return metaKeywordTimeRaw
        case .car: return metaKeywordCarRaw
        case .driver: return metaKeywordDriverRaw
        case .tyre: return metaKeywordTyreRaw
        case .lap: return metaKeywordLapRaw
        case .checker: return metaKeywordCheckerRaw
        }
    }

    private func setKeywordText(_ text: String, for field: MetaVoiceField) {
        switch field {
        case .track: metaKeywordTrackRaw = text
        case .date: metaKeywordDateRaw = text
        case .time: metaKeywordTimeRaw = text
        case .car: metaKeywordCarRaw = text
        case .driver: metaKeywordDriverRaw = text
        case .tyre: metaKeywordTyreRaw = text
        case .lap: metaKeywordLapRaw = text
        case .checker: metaKeywordCheckerRaw = text
        }
    }

    private func parseKeywordList(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: "、", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizeKeywordInput(_ input: String) -> String {
        let components = parseKeywordList(input)
        return components.joined(separator: components.isEmpty ? "" : ", ")
    }

    private func clampedScale(_ value: Double) -> Double {
        // 0.8〜2.0 に丸める。シニアの方が「もう少し小さくしたい」「もっと大きくしたい」と調整しても、
        // 画面崩れにならない安全幅に収めるためのガード。
        min(2.0, max(0.8, value))
    }

    private func migrateMetaVoiceKeywordsIfNeeded() {
        let defaultCar = Self.defaultMetaVoiceKeywords[.car]?.joined(separator: ", ") ?? ""
        let legacyCar = Self.legacyCarKeywords.joined(separator: ", ")
        if metaKeywordCarRaw == legacyCar {
            metaKeywordCarRaw = defaultCar
        }

        let defaultDriver = Self.defaultMetaVoiceKeywords[.driver]?.joined(separator: ", ") ?? ""
        let legacyDriver = Self.legacyDriverKeywords.joined(separator: ", ")
        if metaKeywordDriverRaw == legacyDriver {
            metaKeywordDriverRaw = defaultDriver
        }
    }

}

extension SettingsStore: SessionSettingsProviding {
    var zoneOrderSequence: [Zone] { zoneOrderEnum.sequence }
}
