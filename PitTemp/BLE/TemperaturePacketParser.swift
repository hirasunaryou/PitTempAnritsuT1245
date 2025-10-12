//
//  TemperaturePacketParser.swift
//  PitTemp
//

import Foundation

/// BLEのNotify(最大20B)から温度フレームを安全に取り出す
/// 例: HEX ... → ASCII="001+00243"（ID=001, 温度=24.3℃）
final class TemperaturePacketParser {

    /// 1パケット(～20B)から取り出せるだけのフレームを返す（通常は1件）
    func parseFrames(_ data: Data) -> [TemperatureFrame] {
        guard !data.isEmpty else { return [] }

        // 可視ASCIIのみ取り出し
        var asciiBytes: [UInt8] = []
        asciiBytes.reserveCapacity(data.count)
        for b in data where 0x20...0x7E ~= b { asciiBytes.append(b) }
        guard asciiBytes.count >= 8 else { return [] }

        let ascii = String(bytes: asciiBytes, encoding: .ascii) ?? ""

        // “+”か“-”の位置を探す（温度の符号）
        guard let signIdx = ascii.firstIndex(where: { $0 == "+" || $0 == "-" }) else { return [] }
        let signChar = ascii[signIdx]

        // ---- deviceID 抽出（sign の直前に連続する最大3桁の数字を読む）----
        var idDigits = ""
        var j = ascii.index(before: signIdx)
        while true {
            if ascii[j].isNumber {
                idDigits.insert(ascii[j], at: idDigits.startIndex)
            } else {
                break
            }
            if j == ascii.startIndex || idDigits.count >= 3 { break }
            j = ascii.index(before: j)
        }
        let deviceID = Int(idDigits)

        // ---- 温度の数値部（sign の直後から数字を収集、最大6桁想定）----
        let tempStart = ascii.index(after: signIdx)
        var digits = ""
        var i = tempStart
        while i < ascii.endIndex, digits.count < 6, ascii[i].isNumber {
            digits.append(ascii[i]); i = ascii.index(after: i)
        }
        guard digits.count >= 2 else { return [] } // 例 "00243" など

        let raw = (signChar == "-" ? "-" : "") + digits
        guard let iv = Int(raw) else { return [] }

        // 1/10℃ → ℃
        let valueC = Double(iv) / 10.0

        // ---- ステータス判定（任意）----
        let status: TemperatureFrame.Status?
        if ascii.contains("B-OUT") {
            status = .bout
        } else if ascii.contains("+OVER") {
            status = .over
        } else if ascii.contains("-OVER") {
            status = .under
        } else {
            status = nil
        }

        return [TemperatureFrame(time: Date(), deviceID: deviceID, value: valueC, status: status)]
    }

    // 単発要求/時刻設定コマンド（簡易）
    func buildDATARequest() -> Data { Data("DATA".utf8) }

    func buildTIMESet(date: Date) -> Data {
        let iso = ISO8601DateFormatter().string(from: date)
        return Data("TIME=\(iso)".utf8)
    }
}
