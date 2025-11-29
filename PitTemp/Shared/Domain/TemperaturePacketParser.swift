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

        // 先にTR4AのSOHレスポンス(0x33/0x81)かどうかを判定。合致したらそちらを返す。
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

    /// TR4A「現在値取得(0x33/0x81)」の応答(最小24B)を簡易パースする。
    /// - Assumption: データサイズ0x0018の先頭に[Type(0x00), CH数, 測定値(Int16 LE,0.01℃), 状態コード2...]が並ぶ。
    ///   断線ビット(stateCode2 bit0)のみTemperatureFrame.Statusにマッピングし、温度は0.01℃→℃で返す。
    func parseTR4AFrame(_ data: Data) -> TemperatureFrame? {
        guard data.count >= 9 else { return nil }
        guard data[0] == 0x01, data[1] == 0x33, data[2] == 0x81 else { return nil }

        // データ長は仕様書通りビッグエンディアンで解釈する（0x0018 などが素直に24Bとして扱える）。
        let sizeBE = (UInt16(data[3]) << 8) | UInt16(data[4])
        let payloadStart = 6 // status(1B)を飛ばした位置
        let totalNeeded = payloadStart + Int(sizeBE) + 2 // CRC2B
        guard data.count >= totalNeeded else { return nil }

        let status = data[5]
        guard status == 0x00 else { return nil } // コマンド失敗時は温度を起こさない

        let payload = data[payloadStart..<payloadStart + Int(sizeBE)]
        guard payload.count >= 4 else { return nil }

        let channel = Int(payload[payload.startIndex + 1])
        let raw = Int16(bitPattern: UInt16(payload[payload.startIndex + 2])
                        | (UInt16(payload[payload.startIndex + 3]) << 8))
        let valueC = Double(raw) / 100.0

        var frameStatus: TemperatureFrame.Status?
        if payload.count > 4 {
            let stateCode2 = payload[payload.startIndex + 4]
            if stateCode2 & 0x01 == 1 { frameStatus = .bout }
        }

        return TemperatureFrame(time: Date(), deviceID: channel, value: valueC, status: frameStatus)
    }
}
