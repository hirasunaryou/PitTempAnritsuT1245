//
//  CSVExporter.swift
//  Data/CSV
//
//  既存実装に合わせた CSV 出力。
//  ヘッダは従来の：
//  TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO
//

import Foundation

final class CSVExporter: CSVExporting {
    init() {}

    func export(
        meta: MeasureMeta,
        results: [MeasureResult],
        wheelMemos: [WheelPos: String],
        sessionStart: Date
    ) throws -> URL {

        // Wheel順は既存仕様に合わせて固定（あなたのプロジェクトは FL, FR, RL, RR）
        let wheels: [WheelPos] = [.FL, .FR, .RL, .RR]

        // 集計（各Wheelごとに OUT/CL/IN のピーク値を入れる）
        struct Agg { var out: Double?; var cl: Double?; var inn: Double? }
        var agg: [WheelPos: Agg] = [:]
        for w in wheels { agg[w] = Agg(out: nil, cl: nil, inn: nil) }

        for r in results {
            // r.peakC が有限値なら採用
            guard r.peakC.isFinite else { continue }
            switch r.zone {
            case .OUT: agg[r.wheel]?.out = r.peakC
            case .CL:  agg[r.wheel]?.cl  = r.peakC
            case .IN:  agg[r.wheel]?.inn = r.peakC
            }
        }

        // 保存先
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = Self.isoNoFrac.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url  = dir.appendingPathComponent("track_session_flatwheel_\(stamp).csv")

        // ヘッダ
        var rows: [String] = []
        rows.append("TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO")

        let exportedAt = Self.isoFrac.string(from: Date())
        let sessionISO = Self.isoFrac.string(from: sessionStart)

        // 1行 = 1 Wheel
        for w in wheels {
            let a = agg[w]!

            let outS = a.out.map { String(format: "%.1f", $0) } ?? ""
            let clS  = a.cl .map { String(format: "%.1f", $0) } ?? ""
            let inS  = a.inn.map { String(format: "%.1f", $0) } ?? ""

            let memo = csvEscape(wheelMemos[w] ?? "")

            rows.append("\(csvEscape(meta.track)),\(csvEscape(meta.date)),\(csvEscape(meta.car)),\(csvEscape(meta.driver)),\(csvEscape(meta.tyre)),\(csvEscape(meta.time)),\(csvEscape(meta.lap)),\(csvEscape(meta.checker)),\(w.rawValue),\(outS),\(clS),\(inS),\(memo),\(sessionISO),\(exportedAt),")
        }

        try rows.joined(separator: "\n").appending("\n").data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Helpers

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

    /// CSVエスケープ（カンマ/改行/ダブルクォートを含む場合は "..." に）
    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }
}
