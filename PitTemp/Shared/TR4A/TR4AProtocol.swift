//
//  TR4AProtocol.swift
//  PitTemp
//
//  役割: TR4A(TR45 など) の SOH コマンドを組み立て/解析する純粋なプロトコル層。
//  Dependencies: Foundation のみ。BLE には依存せずユニットテストで検証しやすい形に保つ。
//

import Foundation

/// TR4A 系列で使用するコマンド ID を型安全に扱うための enum。
/// - Important: 仕様書に沿って定義する。SOH フレームは Command/Seq/Length/Params/CRC の順で並ぶ。
enum TR4ACommand: UInt8, CaseIterable {
    case getCurrentValue = 0x33
    case setRecordingConditions = 0x21
    case startRecording = 0x32
    case stopRecording = 0x35
    case getRecordingConditions = 0x31
    case passcode = 0x76
    case securitySetting = 0x77

    /// レスポンス側のコマンド ID は 0x80 を OR した値になるため計算する。
    var responseID: UInt8 { rawValue | 0x80 }
}

/// 1フレーム分の情報を表現するデータモデル。
struct TR4AFrame: Equatable {
    let command: UInt8
    let sequence: UInt8
    let length: UInt16
    let payload: Data
    let crc: UInt16

    /// ペイロード先頭を status バイトとして扱う補助プロパティ。
    var status: TR4AStatusCode {
        guard let first = payload.first else { return .unknown(0xFF) }
        return TR4AStatusCode(rawValue: first) ?? .unknown(first)
    }
}

/// ステータスバイトの意味付け。ACK/REFUSE 判定を簡単にする。
enum TR4AStatusCode: Equatable {
    case ack
    case refuse(reason: UInt8)
    case unknown(UInt8)

    init?(rawValue: UInt8) {
        switch rawValue {
        case 0x00: self = .ack
        case 0x01...0xFE: self = .refuse(reason: rawValue)
        default: self = .unknown(rawValue)
        }
    }

    var isAck: Bool {
        if case .ack = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .ack: return "ACK"
        case .refuse(let reason): return String(format: "REFUSE(0x%02X)", reason)
        case .unknown(let value): return String(format: "UNKNOWN(0x%02X)", value)
        }
    }
}

/// 記録条件などをまとめて UI へ渡すためのスナップショット。
struct TR4AStatusSnapshot: Equatable {
    var recordingIntervalSec: Int?
    var recordingMode: TR4ARecordingMode?
    var isRecording: Bool?
    var securityOn: Bool?
    var stateCode1: UInt8?
    var stateCode2: UInt8?
    var model: String?
    var serial: String?
    var firmware: String?
    var lastError: String?
    var lastUpdated: Date = Date()
}

enum TR4ARecordingMode: UInt8, CaseIterable, Identifiable {
    case endless = 0x00
    case oneTime = 0x01

    var id: UInt8 { rawValue }

    var label: String {
        switch self {
        case .endless: return "Endless"
        case .oneTime: return "One-time"
        }
    }
}

/// 記録条件の設定要求をまとめる構造体。
struct TR4ADeviceSettingsRequest {
    var recordingIntervalSec: Int
    var recordingMode: TR4ARecordingMode
    var enableSecurity: Bool
    var startRecording: Bool?
}

/// SOH フレームの構築/復号を担当する純粋関数群。
enum TR4AFrameCodec {
    /// CRC16-CCITT (0x1021, init=0xFFFF) を仕様に従って計算する。
    static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }

    /// コマンドとペイロードから送信用フレームを構築する。必要に応じて先頭に break(0x00) を付与する。
    static func encode(command: TR4ACommand,
                       sequence: UInt8,
                       payload: Data = Data(),
                       includeBreak: Bool = true) -> Data {
        var frame = Data([0x01, command.rawValue, sequence])
        let length = UInt16(payload.count)
        frame.append(UInt8(length & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(payload)

        let crc = crc16(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))

        if includeBreak {
            var packet = Data([0x00])
            packet.append(frame)
            return packet
        }
        return frame
    }

    /// 通知で受け取った生バイト列をフレーム単位に分割する。
    /// - Note: 先頭の break(0x00) は無視する。CRC が一致しない場合は破棄し、ログ用に reason を返す。
    static func decode(buffer: inout Data) -> (frames: [TR4AFrame], errors: [String]) {
        var frames: [TR4AFrame] = []
        var errors: [String] = []

        func popFront(_ count: Int) { buffer.removeFirst(min(count, buffer.count)) }

        while buffer.count >= 7 { // 最小: SOH+CMD+SEQ+LEN2+CRC2
            if let idx = buffer.firstIndex(where: { $0 == 0x01 }) {
                if idx > 0 { popFront(idx) }
            } else {
                buffer.removeAll()
                break
            }

            guard buffer.count >= 5 else { break }
            let length = UInt16(buffer[3]) | (UInt16(buffer[4]) << 8)
            let totalLength = 1 + 1 + 1 + 2 + Int(length) + 2
            guard buffer.count >= totalLength else { break }

            let frameData = buffer.prefix(totalLength)
            let crcRead = UInt16(frameData[totalLength - 2]) << 8 | UInt16(frameData[totalLength - 1])
            let crcCalc = crc16(frameData.dropLast(2))
            guard crcCalc == crcRead else {
                errors.append(String(format: "CRC mismatch: calc=0x%04X recv=0x%04X", crcCalc, crcRead))
                popFront(totalLength)
                continue
            }

            let command = frameData[1]
            let seq = frameData[2]
            let payload = frameData[5..<5 + Int(length)]
            let frame = TR4AFrame(command: command,
                                  sequence: seq,
                                  length: length,
                                  payload: Data(payload),
                                  crc: crcRead)
            frames.append(frame)
            popFront(totalLength)
        }

        return (frames, errors)
    }
}

// MARK: - Payload decoders

/// 現在値応答(0x33 → 0xB3)などに含まれるチャンネル情報を扱うモデル。
struct TR4ACurrentValuePayload: Equatable {
    let channel: Int
    let temperatureC: Double
    let stateCode1: UInt8
    let stateCode2: UInt8

    var isSensorError: Bool { stateCode2 & 0x01 == 0x01 }
    var isRecording: Bool { stateCode1 & 0x01 == 0x01 }
    var isSecurityOn: Bool { stateCode2 & 0x04 == 0x04 }
}

extension TR4AFrame {
    /// 現在値レスポンスのペイロードをデコードする。仕様書に沿った並びで、Type(1) / CH(1) / Temp(Int16 LE) / State1 / State2...
    func decodeCurrentValue() -> TR4ACurrentValuePayload? {
        guard payload.count >= 6 else { return nil }
        let channel = Int(payload[1])
        let raw = Int16(bitPattern: UInt16(payload[2]) | (UInt16(payload[3]) << 8))
        let value = Double(raw) / 100.0
        let state1 = payload[4]
        let state2 = payload[5]
        return TR4ACurrentValuePayload(channel: channel,
                                        temperatureC: value,
                                        stateCode1: state1,
                                        stateCode2: state2)
    }
}

// MARK: - Utilities

enum TR4AProtocolError: Error, LocalizedError {
    case invalidRegistrationCode

    var errorDescription: String? {
        switch self {
        case .invalidRegistrationCode:
            return "Registration code must be exactly 8 decimal digits"
        }
    }
}

/// 登録コード（パスコード）を 8 桁の 10 進文字列から BCD4B に直す変換器。
enum TR4ARegistrationCodeConverter {
    static func bcdBytes(from string: String) throws -> Data {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 8, trimmed.allSatisfy({ $0.isNumber }) else { throw TR4AProtocolError.invalidRegistrationCode }
        var bytes = Data(); bytes.reserveCapacity(4)
        stride(from: 0, to: trimmed.count, by: 2).forEach { idx in
            let hi = trimmed[trimmed.index(trimmed.startIndex, offsetBy: idx)]
            let lo = trimmed[trimmed.index(trimmed.startIndex, offsetBy: idx + 1)]
            let value = UInt8(String([hi, lo]))!
            bytes.append(value)
        }
        return bytes
    }
}

