// PitTemp/Data/CSV/CSVExporter.swift
import Foundation

/// ライブ追記（time,value）と集計CSV(export)の両方に対応する実装
final class CSVExporter: CSVExporting {

    // ---- ライブ追記（PitTempLogs）用 ----
    private var handle: FileHandle?
    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// ライブ追記：TemperatureSample を 1 行ずつ書く
    func appendLive(sample: TemperatureSample) {
        ensureStreamingHandle()
        guard let h = handle else { return }
        let line = "\(dateFmt.string(from: sample.time)),\(sample.value)\n"
        if let d = line.data(using: .utf8) {
            do { try h.write(contentsOf: d) } catch { /* optional log */ }
        }
    }

    deinit {
        if let h = handle {
            do { try h.close() } catch { /* ignore */ }
        }
    }
    // MARK: - 旧形式（wflat）
    func exportWFlat(
        meta: MeasureMeta,
        results: [MeasureResult],
        wheelMemos: [WheelPos: String],
        wheelPressures: [WheelPos: Double],
        sessionStart: Date,
        deviceName: String?
    ) throws -> URL {

        let base = documentsBase()
        let day = ISO8601DateFormatter().string(from: sessionStart).prefix(10) // yyyy-MM-dd
        let dir = base.appendingPathComponent("PitTempUploads/\(day)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // ファイル名: track_session_flatwheel_<ISO>_<device>_<track>.csv
        let ts = Self.fileStamp(sessionStart) // 例: 2025-10-13T12-06-19Z
        let dev = (deviceName ?? "Unknown").replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let trk = meta.track.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let url = dir.appendingPathComponent("track_session_flatwheel_\(ts)_\(dev)_\(trk).csv")

        // ヘッダは旧資産に合わせる
        // TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,IP_KPA,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO
        var csv = "TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,IP_KPA,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO\n"

        // wheelごとに OUT/CL/IN を詰める
        struct Acc { var out="", cl="", inS="", ip="" }
        var perWheel: [WheelPos:Acc] = [:]
        for r in results {
            var a = perWheel[r.wheel] ?? Acc()
            switch r.zone {
            case .OUT: a.out = r.peakC.isFinite ? String(format: "%.1f", r.peakC) : ""
            case .CL:  a.cl  = r.peakC.isFinite ? String(format: "%.1f", r.peakC) : ""
            case .IN:  a.inS = r.peakC.isFinite ? String(format: "%.1f", r.peakC) : ""
            }
            perWheel[r.wheel] = a
        }

        for (wheel, pressure) in wheelPressures {
            var acc = perWheel[wheel] ?? Acc()
            acc.ip = String(format: "%.1f", pressure)
            perWheel[wheel] = acc
        }

        let iso = ISO8601DateFormatter()
        let sessionISO  = iso.string(from: sessionStart)
        let exportedISO = iso.string(from: Date())
        let uploadedISO = "" // Upload時にアプリ側で埋める想定（空でOK）

        // wheel順で安定化
        let order: [WheelPos] = [.FL,.FR,.RL,.RR]
        for w in order {
            guard let a = perWheel[w] else { continue }
            let memo = wheelMemos[w] ?? ""
            let row = [
                meta.track, meta.date, meta.car, meta.driver, meta.tyre, meta.time, meta.lap, meta.checker,
                w.rawValue, a.out, a.cl, a.inS, a.ip,
                memo.replacingOccurrences(of: ",", with: " "),
                sessionISO, exportedISO, uploadedISO
            ].joined(separator: ",")
            csv += row + "\n"
        }

        try csv.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    // 共通: iCloud Documents or ローカル Documents
    private func documentsBase() -> URL {
        if let ubiq = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") {
            return ubiq
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func fileStamp(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear,.withMonth,.withDay,.withTime,.withColonSeparatorInTime] // 2025-10-13T12:06:19Z
        let s = f.string(from: d).replacingOccurrences(of: ":", with: "-")
        return s // 2025-10-13T12-06-19Z
    }


    // ---- ヘルパ ----

    /// ライブ追記用ファイルのハンドルを lazy に準備
    private func ensureStreamingHandle() {
        if handle != nil { return }
        let base = documentsBase()
        let day = ISO8601DateFormatter().string(from: Date()).prefix(10) // yyyy-MM-dd
        let dir = base.appendingPathComponent("PitTempLogs/\(day)")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("session-\(Int(Date().timeIntervalSince1970)).csv")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(
                    atPath: url.path,
                    contents: "time,value\n".data(using: .utf8)
                )
            }
            let h = try FileHandle(forWritingTo: url)
            try h.seekToEnd()
            handle = h
        } catch {
            handle = nil // 準備失敗時は以降の appendLive を無視
        }
    }
}
