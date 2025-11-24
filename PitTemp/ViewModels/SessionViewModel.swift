//
//  SessionViewModel.swift
//  PitTemp
//
//  役割: 測定ロジック一式（HID入力→ライブ更新→確定→CSV出力）
//  初心者向けメモ:
//   - SwiftUIの画面からは「状態変更リクエスト」だけ投げる（MVVM）
//   - HID(=キーボード)の“行確定”と“途中バッファ”の扱いを分離
//
import Combine
import Foundation
import SwiftUI

@MainActor
final class SessionViewModel: ObservableObject {

    enum NextSessionCarryOver {
        case keepAllMeta
        case keepCarIdentity
        case resetEverything
    }

    // MARK: - 依存（DI）
    private let settings: SessionSettingsProviding
    private let fileCoordinator: SessionFileCoordinating
    private let autosaveStore: SessionAutosaveHandling
    private let uiLog: UILogPublishing?
    private let deviceIdentity: DeviceIdentity
    private var autosaveWorkItem: DispatchWorkItem?
    private var isRestoringAutosave = false
    private var currentSessionID = UUID()
    private var currentSessionReadableID: String = ""
    private var bluetoothCancellable: AnyCancellable?

    // UI からも確認できるよう公開しておく。@Published にすることで
    // 「新しいセッションへ切り替えた」「履歴を復元した」といった変化を
    // 画面が即座に検知できる。読み取り専用のため `private(set)` を付ける。
    @Published private(set) var sessionReadableIDForUI: String = ""
    @Published private(set) var sessionUUIDForUI: UUID = UUID()

    init(exporter: CSVExporting = CSVExporter(),
         settings: SessionSettingsProviding? = nil,
         autosaveStore: SessionAutosaveHandling = SessionAutosaveStore(),
         uiLog: UILogPublishing? = nil,
         fileCoordinator: SessionFileCoordinating? = nil) {
        self.autosaveStore = autosaveStore
        self.uiLog = uiLog
        self.deviceIdentity = DeviceIdentity.current()
        self.fileCoordinator = fileCoordinator ?? SessionFileCoordinator(exporter: exporter)
        // SettingsStore は @MainActor なため、デフォルト生成は init 本体で行う
        if let settings {
            self.settings = settings
        } else {
            self.settings = SettingsStore()
        }

        // 起動直後から「現在のセッションID」を画面に出せるよう、初期値をまとめて設定。
        // ここでは self の完全初期化後に公開用プロパティへ反映させる。
        let initialLabel = SessionIdentifierFormatter.makeReadableID(
            createdAt: Date(),
            device: deviceIdentity,
            seed: currentSessionID
        )
        updateSessionIdentifierState(id: currentSessionID, readableID: initialLabel)

        restoreAutosaveIfAvailable()
    }

    // MARK: - メタ & ライブ
    @Published var meta = MeasureMeta() {
        didSet { scheduleAutosave(reason: .metaUpdated) }
    }
    @Published private(set) var latestValueText: String = "--"
    @Published private(set) var liveTemperatureC: Double? = nil
    @Published private(set) var live: [TempSample] = []
    private var lastSampleAt: Date? = nil

    // MARK: - 測定状態
    @Published private(set) var isCaptureActive = false
    @Published private(set) var currentWheel: WheelPos? = nil
    @Published private(set) var currentZone: Zone? = nil
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var peakC: Double = .nan

    // セッション時刻（「測定を開始しようと動き出した時間」）
    private var sessionBeganAt: Date?

    // 結果とCSV
    @Published private(set) var results: [MeasureResult] = [] {
        didSet { scheduleAutosave(reason: .resultsUpdated) }
    }
    @Published private(set) var lastCSV: URL? = nil
    @Published private(set) var lastLegacyCSV: URL? = nil
    @Published private(set) var lastCSVMetadata: DriveCSVMetadata? = nil
    // メモ（ホイール別の自由記述）
    @Published var wheelMemos: [WheelPos: String] = [:] {
        didSet { scheduleAutosave(reason: .memoUpdated) }
    }
    @Published var wheelPressures: [WheelPos: Double] = [:] {
        didSet { scheduleAutosave(reason: .resultsUpdated) }
    }
    @Published private(set) var autosaveStatusEntry: UILogEntry? = nil
    @Published private(set) var sessionResetID = UUID()
    @Published private(set) var loadedHistorySummary: SessionHistorySummary? = nil

    // MARK: - 設定値（SettingsStore への窓口：同名で差し替え）
    private var autoStopLimitSec: Int { settings.validatedAutoStopLimitSec }
    private var chartWindowSec: Double { settings.chartWindowSec }
    private var advanceWithGreater: Bool { settings.advanceWithGreater }
    private var advanceWithRightArrow: Bool { settings.advanceWithRightArrow }
    private var advanceWithReturn: Bool { settings.advanceWithReturn }
    private var minAdvanceSec: Double { settings.minAdvanceSec }
    private var autofillDateTime: Bool { settings.autofillDateTime }
    private var enableICloudUpload: Bool { settings.enableICloudUpload }

    /// Refresh both the UUID (machine key) and the human-friendly label that is
    /// shown in history, exports, and debug logs. Keeping them paired here avoids
    /// accidental drift between what operators see and what gets persisted.
    private func regenerateSessionIdentifiers(at date: Date = Date()) {
        let freshID = UUID()
        let freshLabel = SessionIdentifierFormatter.makeReadableID(
            createdAt: date,
            device: deviceIdentity,
            seed: freshID
        )
        updateSessionIdentifierState(id: freshID, readableID: freshLabel)
    }

    /// UUID と可読ラベルを一箇所で同期させ、公開用プロパティも同時に更新する。
    /// - Parameters:
    ///   - id: 機械向けの UUID。
    ///   - readableID: 人が読めるラベル（デバッグや履歴表示用）。
    private func updateSessionIdentifierState(id: UUID, readableID: String) {
        currentSessionID = id
        currentSessionReadableID = readableID
        sessionUUIDForUI = id
        sessionReadableIDForUI = readableID
    }

      
    // タイマ
    private var startedAt: Date? = nil
    private var timer: Timer? = nil

    /// Bind Bluetooth samples once so the View does not manage cancellation.
    func bindBluetooth(service: BluetoothService) {
        bluetoothCancellable?.cancel()
        bluetoothCancellable = service.temperatureFrames
            .map { TemperatureSample(time: $0.time, value: $0.value) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in
                guard let self else { return }
                // 履歴表示中はライブサンプルを無視し、ViewModel側で判定を一元化する。
                guard self.loadedHistorySummary == nil else { return }
                self.ingestBLESample(sample)
            }
    }

    // BLEからのサンプルをUI更新系に反映
    func ingestBLESample(_ s: TemperatureSample) {
        // ライブ表示
        latestValueText = String(format: "%.1f", s.value)
        liveTemperatureC = s.value.isFinite ? s.value : nil
        if s.value.isFinite, s.value > peakC || !peakC.isFinite { peakC = s.value }

        // グラフ用のライブ配列（HIDと同じ窓切り）
        live.append(TempSample(ts: s.time, c: s.value))
        lastSampleAt = s.time
        let cutoff = s.time.addingTimeInterval(-chartWindowSec)
        if let idx = live.firstIndex(where: { $0.ts >= cutoff }), idx > 0 {
            live.removeFirst(idx)
        }
    }

    
    // MARK: - View からの操作
    func tapCell(wheel: WheelPos, zone: Zone) {
        if isCaptureActive, currentWheel == wheel, currentZone == zone {
            stopAll()
        } else {
            start(wheel: wheel, zone: zone)
        }
    }

    func stopAll() {
        finalize(via: "manual")
        timer?.invalidate(); timer = nil
        isCaptureActive = false
        currentWheel = nil
        currentZone = nil
        scheduleAutosave(reason: .stateChange)
    }

    func prepareForNextSession(carryOver: NextSessionCarryOver) {
        timer?.invalidate(); timer = nil

        let hadResults = !results.isEmpty || !wheelMemos.isEmpty || !wheelPressures.isEmpty
        var archiveMessage: String? = nil
        if hadResults {
            persistAutosaveNow()
            autosaveStore.archiveLatest()
            archiveMessage = "前の計測セッション (\(currentSessionReadableID)) をアーカイブしました。\nArchived previous session before starting a new one."
        }

        let preservedMeta: MeasureMeta
        switch carryOver {
        case .keepAllMeta:
            preservedMeta = meta
        case .keepCarIdentity:
            var base = MeasureMeta()
            base.car = meta.car
            base.carNo = meta.carNo
            base.carNoAndMemo = meta.carNoAndMemo
            preservedMeta = base
        case .resetEverything:
            preservedMeta = MeasureMeta()
        }

        sessionBeganAt = nil
        startedAt = nil
        lastSampleAt = nil
        elapsed = 0
        peakC = .nan
        latestValueText = "--"
        live.removeAll()
        currentWheel = nil
        currentZone = nil
        isCaptureActive = false

        results = []
        wheelMemos = [:]
        wheelPressures = [:]
        meta = preservedMeta
        lastCSV = nil
        lastLegacyCSV = nil
        lastCSVMetadata = nil

        loadedHistorySummary = nil

        regenerateSessionIdentifiers(at: Date())
        persistAutosaveNow()

        sessionResetID = UUID()

        var message = messageForNextSession(carryOver: carryOver)
        if let archiveMessage { message = archiveMessage + "\n\n" + message }
        let entry = UILogEntry(
            message: message,
            level: .info,
            category: .general
        )
        publishAutosaveStatus(entry)
    }

    /// 手動入力で値を確定させる
    func commitManualValue(wheel: WheelPos,
                           zone: Zone,
                           value: Double,
                           memo: String? = nil,
                           timestamp: Date = Date()) {
        sessionBeganAt = sessionBeganAt ?? timestamp

        let manualResult = MeasureResult(
            wheel: wheel,
            zone: zone,
            peakC: value,
            startedAt: timestamp,
            endedAt: timestamp,
            via: "manual"
        )

        results.removeAll { $0.wheel == wheel && $0.zone == zone }
        results.append(manualResult)
        results.sort { ($0.wheel.rawValue, $0.zone.rawValue) < ($1.wheel.rawValue, $1.zone.rawValue) }

        if let memo {
            let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                wheelMemos.removeValue(forKey: wheel)
            } else {
                wheelMemos[wheel] = trimmed
            }
        }

        Haptics.success()
    }

    func setPressure(_ value: Double?, for wheel: WheelPos) {
        if let value {
            wheelPressures[wheel] = value
        } else {
            wheelPressures.removeValue(forKey: wheel)
        }
    }

    /// HIDからの「行確定」
    func ingestLine(_ s: String) {
        if let v = HR2500Parser.parseValue(s) {
            latestValueText = String(format: "%.1f", v)
            liveTemperatureC = v.isFinite ? v : nil
            if v.isFinite, v > peakC || !peakC.isFinite { peakC = v }
            appendLive(v, at: Date())
        } else if advanceWithGreater && s.trimmingCharacters(in: .whitespacesAndNewlines) == ">" && allowAdvanceNow() {
            finalize(via: "advanceKey"); autoAdvance()
        }
    }

    /// HIDからの「途中バッファ」（ゼロ揺れをライブ値だけに反映）
    func ingestBufferSnapshot(_ s: String) {
        guard s.count >= 4, let v = HR2500Parser.parseValue(s) else { return }
        latestValueText = String(format: "%.1f", v)
        liveTemperatureC = v.isFinite ? v : nil
        // peakC / live はここでは触らない
    }

    /// 特殊キー（Return/→など）
    func receiveSpecial(_ token: String) {
        switch token {
        case "<RET>":
            if allowAdvanceNow() { finalize(via: "advanceKey"); autoAdvance() }
        default:
            break
        }
    }

    /// 既存CSVを返す。無ければ新規出力
    func ensureCSV(deviceName: String?) -> URL? {
        if let u = lastCSV { return u }
        exportCSV(deviceName: deviceName)
        return lastCSV
    }

    // 既定: wflat を保存（Library互換）。
    // 1) DTO にまとめる → 2) ファサードへ渡す → 3) autosave と iCloud へ反映
    func exportCSV(deviceName: String? = nil) {
        let sessionStart = sessionBeganAt ?? Date()

        if autofillDateTime && meta.date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meta.date = Self.isoNoFrac.string(from: sessionStart)
        }

        do {
            // ViewModel では「コンテキストを組み立てる」役割に専念し、
            // 実際の I/O は SessionFileCoordinator に委譲する。
            let export = try fileCoordinator.exportWFlat(
                context: SessionFileContext(
                    meta: meta,
                    sessionID: currentSessionID,
                    sessionReadableID: currentSessionReadableID,
                    sessionBeganAt: sessionStart,
                    deviceIdentity: deviceIdentity,
                    deviceName: deviceName
                ),
                results: results,
                wheelMemos: wheelMemos,
                wheelPressures: wheelPressures
            )
            lastCSV = export.url
            lastCSVMetadata = export.metadata
            print("CSV saved (wflat):", export.url.lastPathComponent)
            // 設定で許可されていれば、そのまま iCloud へブリッジする。
            if enableICloudUpload {
                fileCoordinator.uploadIfPossible(export)
            }
            persistAutosaveNow()
            autosaveStore.archiveLatest()
        } catch {
            print("CSV export error:", error)
        }
    }

    // MARK: - 内部処理
    private func start(wheel: WheelPos, zone: Zone) {
        if sessionBeganAt == nil {
            sessionBeganAt = Date()
            scheduleAutosave(reason: .sessionBegan)
        } else {
            scheduleAutosave(reason: .stateChange)
        }

        loadedHistorySummary = nil
        finalize(via: "auto") // 既存の計測があれば閉じる
        currentWheel = wheel
        currentZone  = zone
        peakC = .nan
        latestValueText = "--"
        startedAt = Date()
        isCaptureActive = true

        timer?.invalidate(); timer = nil
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let t0 = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(t0)
                if self.autoStopLimitSec > 0, self.elapsed >= Double(self.autoStopLimitSec) {
                    self.finalize(via: "timeout")
                    self.isCaptureActive = false
                    self.currentWheel = nil
                    self.currentZone = nil
                    self.scheduleAutosave(reason: .stateChange)
                }
            }
        }
    }

    private func finalize(via: String) {
        guard let w = currentWheel, let z = currentZone, let t0 = startedAt else { return }
        timer?.invalidate(); timer = nil
        let end = Date()
        let r = MeasureResult(wheel: w, zone: z, peakC: peakC.isFinite ? peakC : .nan,
                              startedAt: t0, endedAt: end, via: via)
        // 同一wheel/zoneは上書き
        results.removeAll { $0.wheel == w && $0.zone == z }
        results.append(r)
        // 表示上の安定化（FL..RR/IN..OUT）
        results.sort { ($0.wheel.rawValue, $0.zone.rawValue) < ($1.wheel.rawValue, $1.zone.rawValue) }

        // 次のターゲットへ
        startedAt = nil; elapsed = 0; latestValueText = "--"; peakC = .nan
        Haptics.success()
    }

    private func autoAdvance() {
        guard let w = currentWheel, let z = currentZone else { isCaptureActive = false; return }
//        let order: [Zone] = (zoneOrder == 0) ? [.IN, .CL, .OUT] : [.OUT, .CL, .IN]
        let order: [Zone] = settings.zoneOrderSequence
        if let idx = order.firstIndex(of: z) {
            let nextIdx = idx + 1
            if nextIdx < order.count {
                start(wheel: w, zone: order[nextIdx])
            } else {
                // FL->FR->RL->RR
                let wheels: [WheelPos] = [.FL, .FR, .RL, .RR]
                if let wi = wheels.firstIndex(of: w), wi + 1 < wheels.count {
                    start(wheel: wheels[wi+1], zone: order.first!)
                } else {
                    currentWheel = nil; currentZone = nil; isCaptureActive = false
                }
            }
        }
    }

    private func allowAdvanceNow() -> Bool {
        guard let t0 = startedAt else { return false }
        return Date().timeIntervalSince(t0) >= minAdvanceSec
    }

    private func appendLive(_ v: Double, at ts: Date) {
        // 0.25秒未満は間引き（文字ごと通知スパム対策）
        if let last = lastSampleAt, ts.timeIntervalSince(last) < 0.25 { return }
        live.append(TempSample(ts: ts, c: v))
        lastSampleAt = ts

        // 表示窓で切る
        let cutoff = ts.addingTimeInterval(-chartWindowSec)
        if let idx = live.firstIndex(where: { $0.ts >= cutoff }) {
            if idx > 0 { live.removeFirst(idx) }
        }
    }

    // MARK: - Autosave
    private enum AutosaveReason {
        case metaUpdated
        case resultsUpdated
        case memoUpdated
        case sessionBegan
        case stateChange
    }

    @discardableResult
    func restoreAutosaveIfAvailable() -> Bool {
        if !autosaveStore.hasSnapshot() {
            let entry = UILogEntry(
                message: "No autosave snapshot found to restore.",
                level: .info,
                category: .autosave
            )
            publishAutosaveStatus(entry)
            return false
        }

        guard let snapshot = autosaveStore.load() else {
            let entry = UILogEntry(
                message: "Autosave snapshot exists but failed to load.",
                level: .error,
                category: .autosave
            )
            publishAutosaveStatus(entry)
            return false
        }
        applySnapshot(snapshot)
        let created = Self.autosaveStatusFormatter.string(from: snapshot.createdAt)
        let entry = UILogEntry(
            message: "Restored autosave created at \(created).",
            level: .success,
            category: .autosave
        )
        publishAutosaveStatus(entry)
        return true
    }

    func loadHistorySnapshot(_ snapshot: SessionSnapshot, summary: SessionHistorySummary) {
        applySnapshot(snapshot, historySummary: summary)
        let created = Self.autosaveStatusFormatter.string(from: summary.createdAt)
        let entry = UILogEntry(
            message: "履歴を読み込みました: \(summary.displayTitle)\nLoaded archived session captured \(created).",
            level: .info,
            category: .autosave
        )
        publishAutosaveStatus(entry)
    }

    func exitHistoryMode() {
        if restoreAutosaveIfAvailable() { return }
        loadedHistorySummary = nil
    }

    func canRestoreCurrentSession() -> Bool {
        autosaveStore.hasSnapshot()
    }

    func persistAutosaveNow() {
        autosaveWorkItem?.cancel()
        persistAutosave()
    }

    private func scheduleAutosave(reason: AutosaveReason) {
        guard !isRestoringAutosave else { return }
        autosaveWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.persistAutosave()
        }
        autosaveWorkItem = work

        let delay: DispatchTimeInterval
        switch reason {
        case .sessionBegan:
            delay = .milliseconds(150)
        case .metaUpdated, .memoUpdated:
            delay = .milliseconds(300)
        case .resultsUpdated, .stateChange:
            delay = .milliseconds(100)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func persistAutosave() {
        let snapshot = SessionSnapshot(
            meta: meta,
            results: results,
            wheelMemos: wheelMemos,
            wheelPressures: wheelPressures,
            sessionBeganAt: sessionBeganAt,
            sessionID: currentSessionID,
            sessionReadableID: currentSessionReadableID,
            originDeviceID: deviceIdentity.id,
            originDeviceName: deviceIdentity.name
        )
        autosaveStore.save(snapshot)
    }

    // MARK: - Session report helpers

    func makeLiveSnapshotForReport() -> SessionSnapshot {
        SessionSnapshot(
            meta: meta,
            results: results,
            wheelMemos: wheelMemos,
            wheelPressures: wheelPressures,
            sessionBeganAt: sessionBeganAt,
            sessionID: currentSessionID,
            sessionReadableID: currentSessionReadableID,
            originDeviceID: deviceIdentity.id,
            originDeviceName: deviceIdentity.name
        )
    }

    func makeLiveSummary(for snapshot: SessionSnapshot? = nil) -> SessionHistorySummary {
        let snapshot = snapshot ?? makeLiveSnapshotForReport()
        return SessionHistorySummary.makeLiveSummary(from: snapshot, isFromCurrentDevice: true)
    }

    private func applySnapshot(_ snapshot: SessionSnapshot, historySummary: SessionHistorySummary? = nil) {
        isRestoringAutosave = true
        meta = snapshot.meta
        results = snapshot.results
        wheelMemos = snapshot.wheelMemos
        wheelPressures = snapshot.wheelPressures
        sessionBeganAt = snapshot.sessionBeganAt
        // ここで UUID/ラベル/公開用プロパティをまとめて同期し、
        // 「履歴を開いたらセッションID表示が即座に切り替わる」ようにする。
        updateSessionIdentifierState(id: snapshot.sessionID, readableID: snapshot.sessionReadableID)
        isCaptureActive = false
        currentWheel = nil
        currentZone = nil
        elapsed = 0
        peakC = .nan
        lastCSV = nil
        lastLegacyCSV = nil
        lastCSVMetadata = nil
        isRestoringAutosave = false
        loadedHistorySummary = historySummary
    }

    func clearAutosave() {
        autosaveWorkItem?.cancel()
        autosaveStore.clear()
        let entry = UILogEntry(
            message: "Cleared autosave snapshot manually.",
            level: .info,
            category: .autosave
        )
        publishAutosaveStatus(entry)
    }

    // MARK: - 小物
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let autosaveStatusFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    private func publishAutosaveStatus(_ entry: UILogEntry) {
        autosaveStatusEntry = entry
        uiLog?.publish(entry)
    }

    private func messageForNextSession(carryOver: NextSessionCarryOver) -> String {
        let base: String
        switch carryOver {
        case .keepAllMeta:
            base = "計測結果をクリアしました（メタ情報は保持）。\nCleared results while keeping meta fields."
        case .keepCarIdentity:
            base = "計測結果をクリアし、車両Noのみ引き継ぎました。\nCleared results and kept only the car number."
        case .resetEverything:
            base = "計測結果とメタ情報をすべて初期化しました。\nReset results and meta for the next vehicle."
        }
        return base + "\n\nSession ID: \(currentSessionReadableID) (UUID: \(currentSessionID.uuidString))"
    }
}
