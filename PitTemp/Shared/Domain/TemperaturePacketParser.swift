//
//  TemperaturePacketParser.swift
//  PitTemp
//

import Foundation

/// 温度パケットの変換ロジックを抽象化するプロトコル。
/// - Note: BLE 層だけでなくファイル再生などからも再利用できるようにする。
protocol TemperaturePacketParsing {
    func parseFrames(_ data: Data) -> [TemperatureFrame]
    func buildTIMESet(date: Date) -> Data
}

/// BLE の Notify(最大20B)から温度フレームを安全に取り出す既定実装。
/// 例: HEX ... → ASCII="001+00243"（ID=001, 温度=24.3℃）
final class TemperaturePacketParser: TemperaturePacketParsing {

    /// 1パケット(～20B)から取り出せるだけのフレームを返す（通常は1件）
    func parseFrames(_ data: Data) -> [TemperatureFrame] {
        guard !data.isEmpty else { return [] }

        // 先にTR4AのSOHレスポンス(0x33/0x00 系)かどうかを判定。合致したらそちらを返す。
        if let tr4a = parseTR4AFrame(data) {
            return [tr4a]
        }

        return parseAnritsuASCII(data)
    }

    // 時刻設定コマンドだけを公開。DATA 取得は通知購読に集約したため残さない。
    func buildTIMESet(date: Date) -> Data {
        let iso = ISO8601DateFormatter().string(from: date)
        return Data("TIME=\(iso)".utf8)
    }
}

private extension TemperaturePacketParser {
    /// 既存Anritsu ASCIIフレームを分解する処理を切り出し（符号位置からID/温度を抽出）。
    func parseAnritsuASCII(_ data: Data) -> [TemperatureFrame] {
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

    /// TR4A「現在値取得(0x33/0x00)」の最小応答(11B)をパースする。
    /// - Specification: オフセット5のInt16(LE)が (値-1000)/10 ℃ で表され、CH2は7-8byte目に格納される。
    ///   TR45は1ch温度のみなのでCH1のみ返す。CRCは受信元（BLEスタック）で検証済みとみなしここでは省略する。
    func parseTR4AFrame(_ data: Data) -> TemperatureFrame? {
        guard data.count >= 11 else { return nil }
        guard data[0] == 0x01, data[1] == 0x33 else { return nil }

        let sub = data[2]
        guard sub == 0x00 || sub == 0x80 else { return nil } // 0x80は成功応答の場合がある

        let sizeLE = UInt16(data[3]) | (UInt16(data[4]) << 8)
        let payloadStart = 5
        let totalNeeded = payloadStart + Int(sizeLE) + 2 // CRC16 2byte を含めた必要長
        guard data.count >= totalNeeded, sizeLE >= 4 else { return nil }

        let rawLE = UInt16(data[payloadStart]) | (UInt16(data[payloadStart + 1]) << 8)
        let raw = Int16(bitPattern: rawLE)
        // 仕様書の式: (Int16値 - 1000) / 10 で ℃ を得る
        let valueC = (Double(raw) - 1000.0) / 10.0

        return TemperatureFrame(time: Date(), deviceID: 1, value: valueC, status: nil)
    }
}
