//
//  SettingsStore.swift
//  Core/Settings
//
//  目的: 画面やVMに散らばった設定保存を一元管理し、保存先を切り替えやすくする。
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
    /// iCloud への自動アップロードを VM から参照するためのフラグ
    var enableICloudUpload: Bool { get }
}

protocol SettingsStoreBacking {
    func value<T>(forKey key: String, default defaultValue: T) -> T
    func set<T>(_ value: T, forKey key: String)
}

struct UserDefaultsSettingsStore: SettingsStoreBacking {
    var defaults: UserDefaults = .standard

    func value<T>(forKey key: String, default defaultValue: T) -> T {
        if let existing = defaults.object(forKey: key) as? T {
            return existing
        }
        return defaultValue
    }

    func set<T>(_ value: T, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let autoStopLimitSec = "pref.durationSec"
        static let chartWindowSec = "pref.chartWindowSec"
        static let advanceWithGreater = "pref.advanceWithGreater"
        static let advanceWithRightArrow = "pref.advanceWithRightArrow"
        static let advanceWithReturn = "pref.advanceWithReturn"
        static let minAdvanceSec = "pref.minAdvanceSec"
        static let bleAutoConnect = "ble.autoConnect"
        static let enableWheelVoiceInput = "pref.enableWheelVoiceInput"
        static let enableSeniorLayout = "pref.enableSeniorLayout"
        static let seniorZoneFontScale = "pref.senior.zoneFontScale"
        static let seniorChipFontScale = "pref.senior.chipFontScale"
        static let seniorLiveFontScale = "pref.senior.liveFontScale"
        static let seniorMetaFontScale = "pref.senior.metaFontScale"
        static let seniorTileFontScale = "pref.senior.tileFontScale"
        static let seniorPressureFontScale = "pref.senior.pressureFontScale"
        static let zoneOrder = "pref.zoneOrder"
        static let autofillDateTime = "pref.autofillDateTime"
        static let hr2500ID = "hr2500.id"
        static let enableICloudUpload = "cloud.enableICloudUpload"
        static let enableGoogleDriveUpload = "cloud.enableDriveUpload"
        static let uploadAfterSave = "cloud.uploadAfterSave"
        static let metaInputMode = "pref.metaInputMode"
        static let metaKeywordTrack = "pref.metaKeyword.track"
        static let metaKeywordDate = "pref.metaKeyword.date"
        static let metaKeywordTime = "pref.metaKeyword.time"
        static let metaKeywordCar = "pref.metaKeyword.car"
        static let metaKeywordDriver = "pref.metaKeyword.driver"
        static let metaKeywordTyre = "pref.metaKeyword.tyre"
        static let metaKeywordLap = "pref.metaKeyword.lap"
        static let metaKeywordChecker = "pref.metaKeyword.checker"
    }

    private let store: SettingsStoreBacking

    @Published var autoStopLimitSec: Int { didSet { save(autoStopLimitSec, key: Keys.autoStopLimitSec) } }
    @Published var chartWindowSec: Double { didSet { save(chartWindowSec, key: Keys.chartWindowSec) } }
    @Published var advanceWithGreater: Bool { didSet { save(advanceWithGreater, key: Keys.advanceWithGreater) } }
    @Published var advanceWithRightArrow: Bool { didSet { save(advanceWithRightArrow, key: Keys.advanceWithRightArrow) } }
    @Published var advanceWithReturn: Bool { didSet { save(advanceWithReturn, key: Keys.advanceWithReturn) } }
    @Published var minAdvanceSec: Double { didSet { save(minAdvanceSec, key: Keys.minAdvanceSec) } }
    @Published var bleAutoConnect: Bool { didSet { save(bleAutoConnect, key: Keys.bleAutoConnect) } }
    @Published var enableWheelVoiceInput: Bool { didSet { save(enableWheelVoiceInput, key: Keys.enableWheelVoiceInput) } }
    @Published var enableSeniorLayout: Bool { didSet { save(enableSeniorLayout, key: Keys.enableSeniorLayout) } }
    @Published private var seniorZoneFontScaleRaw: Double { didSet { save(seniorZoneFontScaleRaw, key: Keys.seniorZoneFontScale) } }
    @Published private var seniorChipFontScaleRaw: Double { didSet { save(seniorChipFontScaleRaw, key: Keys.seniorChipFontScale) } }
    @Published private var seniorLiveFontScaleRaw: Double { didSet { save(seniorLiveFontScaleRaw, key: Keys.seniorLiveFontScale) } }
    @Published private var seniorMetaFontScaleRaw: Double { didSet { save(seniorMetaFontScaleRaw, key: Keys.seniorMetaFontScale) } }
    @Published private var seniorTileFontScaleRaw: Double { didSet { save(seniorTileFontScaleRaw, key: Keys.seniorTileFontScale) } }
    @Published private var seniorPressureFontScaleRaw: Double { didSet { save(seniorPressureFontScaleRaw, key: Keys.seniorPressureFontScale) } }
    @Published private var zoneOrderRaw: Int { didSet { save(zoneOrderRaw, key: Keys.zoneOrder) } }
    @Published var autofillDateTime: Bool { didSet { save(autofillDateTime, key: Keys.autofillDateTime) } }
    @Published var hr2500ID: String { didSet { save(hr2500ID, key: Keys.hr2500ID) } }
    @Published var enableICloudUpload: Bool { didSet { save(enableICloudUpload, key: Keys.enableICloudUpload) } }
    @Published var enableGoogleDriveUpload: Bool { didSet { save(enableGoogleDriveUpload, key: Keys.enableGoogleDriveUpload) } }
    @Published var uploadAfterSave: Bool { didSet { save(uploadAfterSave, key: Keys.uploadAfterSave) } }
    @Published private var metaInputModeRaw: Int { didSet { save(metaInputModeRaw, key: Keys.metaInputMode) } }
    @Published private var metaKeywordTrackRaw: String { didSet { save(metaKeywordTrackRaw, key: Keys.metaKeywordTrack) } }
    @Published private var metaKeywordDateRaw: String { didSet { save(metaKeywordDateRaw, key: Keys.metaKeywordDate) } }
    @Published private var metaKeywordTimeRaw: String { didSet { save(metaKeywordTimeRaw, key: Keys.metaKeywordTime) } }
    @Published private var metaKeywordCarRaw: String { didSet { save(metaKeywordCarRaw, key: Keys.metaKeywordCar) } }
    @Published private var metaKeywordDriverRaw: String { didSet { save(metaKeywordDriverRaw, key: Keys.metaKeywordDriver) } }
    @Published private var metaKeywordTyreRaw: String { didSet { save(metaKeywordTyreRaw, key: Keys.metaKeywordTyre) } }
    @Published private var metaKeywordLapRaw: String { didSet { save(metaKeywordLapRaw, key: Keys.metaKeywordLap) } }
    @Published private var metaKeywordCheckerRaw: String { didSet { save(metaKeywordCheckerRaw, key: Keys.metaKeywordChecker) } }

    init(store: SettingsStoreBacking = UserDefaultsSettingsStore()) {
        self.store = store

        autoStopLimitSec = store.value(forKey: Keys.autoStopLimitSec, default: 20)
        chartWindowSec = store.value(forKey: Keys.chartWindowSec, default: 6)
        advanceWithGreater = store.value(forKey: Keys.advanceWithGreater, default: false)
        advanceWithRightArrow = store.value(forKey: Keys.advanceWithRightArrow, default: false)
        advanceWithReturn = store.value(forKey: Keys.advanceWithReturn, default: true)
        minAdvanceSec = store.value(forKey: Keys.minAdvanceSec, default: 0.3)
        bleAutoConnect = store.value(forKey: Keys.bleAutoConnect, default: true)
        enableWheelVoiceInput = store.value(forKey: Keys.enableWheelVoiceInput, default: false)
        enableSeniorLayout = store.value(forKey: Keys.enableSeniorLayout, default: false)
        seniorZoneFontScaleRaw = store.value(forKey: Keys.seniorZoneFontScale, default: 1.0)
        seniorChipFontScaleRaw = store.value(forKey: Keys.seniorChipFontScale, default: 1.0)
        seniorLiveFontScaleRaw = store.value(forKey: Keys.seniorLiveFontScale, default: 1.0)
        seniorMetaFontScaleRaw = store.value(forKey: Keys.seniorMetaFontScale, default: 1.0)
        seniorTileFontScaleRaw = store.value(forKey: Keys.seniorTileFontScale, default: 1.0)
        seniorPressureFontScaleRaw = store.value(forKey: Keys.seniorPressureFontScale, default: 1.0)
        zoneOrderRaw = store.value(forKey: Keys.zoneOrder, default: 0)
        autofillDateTime = store.value(forKey: Keys.autofillDateTime, default: true)
        hr2500ID = store.value(forKey: Keys.hr2500ID, default: "")
        enableICloudUpload = store.value(forKey: Keys.enableICloudUpload, default: true)
        enableGoogleDriveUpload = store.value(forKey: Keys.enableGoogleDriveUpload, default: false)
        uploadAfterSave = store.value(forKey: Keys.uploadAfterSave, default: true)
        metaInputModeRaw = store.value(forKey: Keys.metaInputMode, default: 0)

        metaKeywordTrackRaw = store.value(forKey: Keys.metaKeywordTrack, default: Self.defaultMetaVoiceKeywords[.track]!.joined(separator: ", "))
        metaKeywordDateRaw = store.value(forKey: Keys.metaKeywordDate, default: Self.defaultMetaVoiceKeywords[.date]!.joined(separator: ", "))
        metaKeywordTimeRaw = store.value(forKey: Keys.metaKeywordTime, default: Self.defaultMetaVoiceKeywords[.time]!.joined(separator: ", "))
        metaKeywordCarRaw = store.value(forKey: Keys.metaKeywordCar, default: Self.defaultMetaVoiceKeywords[.car]!.joined(separator: ", "))
        metaKeywordDriverRaw = store.value(forKey: Keys.metaKeywordDriver, default: Self.defaultMetaVoiceKeywords[.driver]!.joined(separator: ", "))
        metaKeywordTyreRaw = store.value(forKey: Keys.metaKeywordTyre, default: Self.defaultMetaVoiceKeywords[.tyre]!.joined(separator: ", "))
        metaKeywordLapRaw = store.value(forKey: Keys.metaKeywordLap, default: Self.defaultMetaVoiceKeywords[.lap]!.joined(separator: ", "))
        metaKeywordCheckerRaw = store.value(forKey: Keys.metaKeywordChecker, default: Self.defaultMetaVoiceKeywords[.checker]!.joined(separator: ", "))

        migrateMetaVoiceKeywordsIfNeeded()
    }

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

    private static let legacyCarKeywords = ["car", "カー", "車", "クルマ", "車両", "ゼッケン", "ゼッケン番号", "エントリー番号",
                                            "ナンバー", "番号"]
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

    var zoneOrderEnum: ZoneOrder {
        get { ZoneOrder(rawValue: zoneOrderRaw) ?? .in_cl_out }
        set { zoneOrderRaw = newValue.rawValue }
    }

    var validatedAutoStopLimitSec: Int { max(1, min(autoStopLimitSec, 120)) }

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
    var seniorZoneFontScale: Double {
        get { clampedScale(seniorZoneFontScaleRaw) }
        set { seniorZoneFontScaleRaw = clampedScale(newValue) }
    }

    var seniorChipFontScale: Double {
        get { clampedScale(seniorChipFontScaleRaw) }
        set { seniorChipFontScaleRaw = clampedScale(newValue) }
    }

    var seniorLiveFontScale: Double {
        get { clampedScale(seniorLiveFontScaleRaw) }
        set { seniorLiveFontScaleRaw = clampedScale(newValue) }
    }

    var seniorMetaFontScale: Double {
        get { clampedScale(seniorMetaFontScaleRaw) }
        set { seniorMetaFontScaleRaw = clampedScale(newValue) }
    }

    var seniorTileFontScale: Double {
        get { clampedScale(seniorTileFontScaleRaw) }
        set { seniorTileFontScaleRaw = clampedScale(newValue) }
    }

    var seniorPressureFontScale: Double {
        get { clampedScale(seniorPressureFontScaleRaw) }
        set { seniorPressureFontScaleRaw = clampedScale(newValue) }
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

    private func save<T>(_ value: T, key: String) {
        store.set(value, forKey: key)
    }
}

extension SettingsStore: SessionSettingsProviding {
    var zoneOrderSequence: [Zone] { zoneOrderEnum.sequence }
}
