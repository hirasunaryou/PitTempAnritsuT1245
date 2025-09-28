//
//  SessionViewModel.swift
//  PitTemp
//
//  役割: 測定ロジック一式（HID入力→ライブ更新→確定→CSV出力）
//  初心者向けメモ:
//   - SwiftUIの画面からは「状態変更リクエスト」だけ投げる（MVVM）
//   - HID(=キーボード)の“行確定”と“途中バッファ”の扱いを分離
//

import Foundation
import SwiftUI
import Combine


// ======= ここまで（重複注意） =======

@MainActor
final class SessionViewModel: ObservableObject {
    // --- 設定（AppStorage で永続化） ---
    @AppStorage("pref.durationSec") var durationSec: Int = 10
    @AppStorage("pref.zoneOrder") var zoneOrder: Int = 0 // 0: IN-CL-OUT, 1: OUT-CL-IN
    @AppStorage("pref.chartWindowSec") var chartWindowSec: Double = 6
    @AppStorage("pref.advanceWithGreater") var advanceWithGreater: Bool = false
    @AppStorage("pref.advanceWithRightArrow") var advanceWithRightArrow: Bool = false
    @AppStorage("pref.advanceWithReturn") var advanceWithReturn: Bool = true
    @AppStorage("pref.minAdvanceSec") var minAdvanceSec: Double = 0.3

    // 自動補完や識別情報
    @AppStorage("pref.autofillDateTime") var autofillDateTime: Bool = true
    @AppStorage("hr2500.id") var hr2500ID: String = ""   // ラベル/資産タグ等（手入力）

    // --- メタとライブ表示 ---
    @Published var meta = MeasureMeta()
    @Published private(set) var latestValueText: String = "--"
    @Published private(set) var live: [TempSample] = []
    private var lastSampleAt: Date? = nil

    // --- 測定状態 ---
    @Published private(set) var isCaptureActive = false
    @Published private(set) var currentWheel: WheelPos? = nil
    @Published private(set) var currentZone: Zone? = nil
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var peakC: Double = .nan

    // セッション時刻（要望：「測定を開始しようと動き出した時間」）
    private var sessionBeganAt: Date?

    // 結果とCSV
    @Published private(set) var results: [MeasureResult] = []
    @Published private(set) var lastCSV: URL? = nil

    // メモ
    // --- Memo（ホイール別の自由記述メモを保持） ---
    @Published var wheelMemos: [WheelPos: String] = [:]

    
    // CSV
    private let exporter: CSVExporting
    
    // 追加：デフォルト引数つき init（PitTempApp を変更しなくてOK）
    init(exporter: CSVExporting = CSVExporter()) {
        self.exporter = exporter
    }
    
    
    /// 音声起こし等のテキストを指定ホイールのメモに追記
    func appendMemo(_ text: String, to wheel: WheelPos) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let old = wheelMemos[wheel], !old.isEmpty {
            wheelMemos[wheel] = old + " " + t
        } else {
            wheelMemos[wheel] = t
        }
    }

    
    // タイマ
    private var startedAt: Date? = nil
    private var timer: Timer? = nil

    // MARK: - パブリック API（View から呼ぶ）
    func tapCell(wheel: WheelPos, zone: Zone) {
        start(wheel: wheel, zone: zone)
    }

    func stopAll() {
        finalize(via: "manual")
        isCaptureActive = false
    }

    /// HIDからの「行確定」
    func ingestLine(_ s: String) {
        if let v = HR2500Parser.parseValue(s) {
            latestValueText = String(format: "%.1f", v)
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
        // peakC / live はここでは触らない
    }

    /// 特殊キー（Return/→など）を受ける
    func receiveSpecial(_ token: String) {
        switch token {
        case "<RET>":
            if allowAdvanceNow() { finalize(via: "advanceKey"); autoAdvance() }
        default:
            break
        }
    }

    /// 既存CSVを返す。無ければ新規出力して返す
    func ensureCSV() -> URL? {
        if let u = lastCSV { return u }
        exportCSV()
        return lastCSV
    }

    /// CSV出力（ホイール1行＝OUT/CL/INの列）
    // CSV保存のトリガーで呼ぶ関数
    func exportCSV() {
        // セッション開始時間（未設定なら今）
        let sessionStart = sessionBeganAt ?? Date()

        // Dateが空欄かつ自動補完ONなら補完（元の挙動を踏襲）
        if autofillDateTime && meta.date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meta.date = Self.isoNoFrac.string(from: sessionStart)
        }

        do {
            let url = try exporter.export(
                meta: meta,
                results: results,
                wheelMemos: wheelMemos,
                sessionStart: sessionStart
            )
            lastCSV = url
            print("CSV saved:", url)
        } catch {
            print("CSV export error:", error)
        }
    }


//    func exportCSV() {
//        // セッション開始時間（未設定なら今）
//        let sessionStart = sessionBeganAt ?? Date()
//        // Dateが空欄かつ自動補完ONなら補完
//        if autofillDateTime && meta.date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
//            meta.date = Self.isoNoFrac.string(from: sessionStart)
//        }
//
//        // ホイールごとに OUT/CL/IN を集計
//        struct Agg { var out: Double?; var cl: Double?; var inn: Double? }
//        var agg: [WheelPos: Agg] = [:]
//        for w in WheelPos.allCases { agg[w] = Agg(out: nil, cl: nil, inn: nil) }
//        for r in results {
//            switch r.zone {
//            case .OUT: agg[r.wheel]?.out = r.peakC.isFinite ? r.peakC : nil
//            case .CL:  agg[r.wheel]?.cl  = r.peakC.isFinite ? r.peakC : nil
//            case .IN:  agg[r.wheel]?.inn = r.peakC.isFinite ? r.peakC : nil
//            }
//        }
//
//        // ファイル準備
//        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//        let name = "track_session_flatwheel_" + Self.isoNoFrac.string(from: Date()) + ".csv"
//        let url  = dir.appendingPathComponent(name)
//
//        var rows: [String] = []
//        // ヘッダ（UPLOADED_AT_ISO はアップロード時に埋める）
//        rows.append("TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO")
//        let exportedAt = Self.isoFrac.string(from: Date())
//        let sessionISO = Self.isoFrac.string(from: sessionStart)
//
//        for w in WheelPos.allCases {
//            let a = agg[w]!
//            let outS = a.out.map { String(format: "%.1f", $0) } ?? ""
//            let clS  = a.cl .map { String(format: "%.1f", $0) } ?? ""
//            let inS  = a.inn.map { String(format: "%.1f", $0) } ?? ""
//            let memo = (wheelMemos[w] ?? "").csvEscaped
//            rows.append("\(meta.track),\(meta.date),\(meta.car),\(meta.driver),\(meta.tyre),\(meta.time),\(meta.lap),\(meta.checker),\(w.rawValue),\(outS),\(clS),\(inS),\(memo),\(sessionISO),\(exportedAt),")
//        }
//
//        try? rows.joined(separator: "\n").appending("\n").data(using: .utf8)?.write(to: url)
//        lastCSV = url
//    }

    // MARK: - 内部処理
    private func start(wheel: WheelPos, zone: Zone) {
        // 最初の計測開始時にセッション開始時刻を記録
        if sessionBeganAt == nil { sessionBeganAt = Date() }

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
                if self.elapsed >= Double(self.durationSec) { self.finalize(via: "timeout") }
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

        // 次のターゲットへ（autoAdvanceは呼び出し側で）
        startedAt = nil; elapsed = 0; latestValueText = "--"; peakC = .nan
        Haptics.success()
    }

    private func autoAdvance() {
        guard let w = currentWheel, let z = currentZone else { isCaptureActive = false; return }
        let order: [Zone] = (zoneOrder == 0) ? [.IN, .CL, .OUT] : [.OUT, .CL, .IN]
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

    // 小物
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
}


