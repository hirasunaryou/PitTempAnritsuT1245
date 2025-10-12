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
            do { try h.write(contentsOf: d) } catch { /* 必要ならログ出力 */ }
        }
    }

    deinit {
        if let h = handle {
            do { try h.close() } catch { /* ignore */ }
        }
    }

    // ---- 集計CSV（PitTempReports）用 ----
    func export(
        meta: MeasureMeta,
        results: [MeasureResult],
        wheelMemos: [WheelPos: String],
        sessionStart: Date
    ) throws -> URL {

        let base = documentsBase()
        let day = ISO8601DateFormatter().string(from: sessionStart).prefix(10) // yyyy-MM-dd
        let dir = base.appendingPathComponent("PitTempReports/\(day)")

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = Int(sessionStart.timeIntervalSince1970)
        let safeTrack = meta.track.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let url = dir.appendingPathComponent("report_\(safeTrack)_\(stamp).csv")

        var csv = ""
        csv += "# PitTemp Session Report\n"
        csv += "# track,\(meta.track)\n"
        csv += "# date,\(meta.date)\n"
        csv += "# time,\(meta.time)\n"
        csv += "# lap,\(meta.lap)\n"
        csv += "# car,\(meta.car)\n"
        csv += "# driver,\(meta.driver)\n"
        csv += "# tyre,\(meta.tyre)\n"
        csv += "# checker,\(meta.checker)\n"
        csv += "\n"
        csv += "wheel,zone,peakC,startedAt,endedAt,via,memo\n"

        let iso = ISO8601DateFormatter()
        for r in results {
            let memo = wheelMemos[r.wheel] ?? ""
            let row = [
                r.wheel.rawValue,
                r.zone.rawValue,
                r.peakC.isFinite ? String(format: "%.1f", r.peakC) : "",
                iso.string(from: r.startedAt),
                iso.string(from: r.endedAt),
                r.via,
                memo.replacingOccurrences(of: ",", with: " ")
            ].joined(separator: ",")
            csv += row + "\n"
        }

        try csv.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    // ---- ヘルパ ----

    /// iCloud Drive が有効なら /Documents、なければローカル Documents
    private func documentsBase() -> URL {
        if let ubiq = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") {
            return ubiq
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

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
