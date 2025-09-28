//
//  Models.swift
//  PitTemp
//
//  役割: ドメインモデル（車輪/ゾーン/計測結果など）と小さなユーティリティ
//  初心者向けメモ: データの「型」をひとところに集めておくと見通しが良いです。
//  CSV のエスケープなど“どの層にも属しない小物”もここに置くと便利です。
//

import Foundation

enum WheelPos: String, CaseIterable, Identifiable, Codable { case FL, FR, RL, RR; var id: String { rawValue } }
enum Zone:     String, CaseIterable, Identifiable, Codable { case IN, CL, OUT; var id: String { rawValue } }

struct MeasureMeta: Codable {
    var track = "", date = "", car = "", driver = "", tyre = "", time = "", lap = "", checker = ""
}

struct MeasureResult: Identifiable, Codable {
    var id = UUID()
    var wheel: WheelPos
    var zone: Zone
    var peakC: Double
    var startedAt: Date
    var endedAt: Date
    var via: String   // "timeout" | "advanceKey" | "manual"
}

struct TempSample: Identifiable { let id = UUID(); let ts: Date; let c: Double }

// HR-2500 の 1秒ごとの文字列（例: "  28.1"）から数値を取り出す
enum HR2500Parser {
    static func parseValue(_ s: String) -> Double? {
        // 数字/符号/小数点以外を除去してから Double 変換
        let cleaned = s.replacingOccurrences(of: "[^0-9eE+\\-\\.]", with: "", options: .regularExpression)
        return Double(cleaned)
    }
}

// CSV の基本的なエスケープ（カンマ/改行/ダブルクォート対応）
extension String {
    var csvEscaped: String {
        if contains(",") || contains("\"") || contains("\n") {
            return "\"" + replacingOccurrences(of: "\"", with: "\"\"") + "\""
        } else { return self }
    }
}
