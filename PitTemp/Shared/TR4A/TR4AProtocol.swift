import Foundation

/// TR4A シリーズ (TR45 など) の SOH ベースフレームをエンコード/デコードする責務に専念したユーティリティ。
/// アプリ全体で同じ計算式・長さ判定を共有するため、BLE 層から直接参照する。
struct TR4AProtocol {
    /// SOH フレームの完全な定義。
    struct Frame: Equatable {
        let command: TR4ACommand
        let sequence: UInt8
        let length: UInt16
        let status: TR4AStatus
        let payload: Data
        let crc: UInt16
    }

    /// SOH(0x01) を先頭に持つ 5 バイトのヘッダー長。
    private static let headerLength = 5

    /// フレームを Data にエンコードする。CRC16 は SOH 以降を対象に計算し、末尾にビッグエンディアンで付与する。
    static func encode(command: TR4ACommand, sequence: UInt8, payload: Data) -> Data {
        var frame = Data(capacity: headerLength + payload.count + 3) // status1 + crc2
        frame.append(0x01)
        frame.append(command.rawValue)
        frame.append(sequence)
        frame.append(UInt8(payload.count & 0xFF))
        frame.append(UInt8((payload.count >> 8) & 0xFF))
        frame.append(contentsOf: payload)
        let crc = crc16(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    /// 通知で届いた生データをパースし、CRC/長さが正しいフレームのみ返す。
    static func decode(_ data: Data) -> Frame? {
        guard data.count >= headerLength + 3 else { return nil }
        guard data[0] == 0x01 else { return nil }
        guard let cmd = TR4ACommand(rawValue: data[1]) else { return nil }
        let seq = data[2]
        let length = UInt16(data[3]) | (UInt16(data[4]) << 8)
        let totalLength = headerLength + Int(length) + 2
        guard data.count >= totalLength else { return nil }

        let payload = data[5..<(5 + Int(length))]
        let crcIndex = 5 + Int(length)
        let crcRead = (UInt16(data[crcIndex]) << 8) | UInt16(data[crcIndex + 1])
        let calc = crc16(data.prefix(crcIndex))
        guard crcRead == calc else { return nil }

        let status = TR4AStatus(payload: payload)
        return Frame(command: cmd, sequence: seq, length: length, status: status, payload: Data(payload), crc: crcRead)
    }

    /// 仕様書の CRC16-CCITT (poly 0x1021, init 0xFFFF, MSB-first) を実装。
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
}

/// サポートする SOH コマンド ID の一覧。必要に応じて拡張できるよう enum で宣言。
enum TR4ACommand: UInt8, CaseIterable {
    case getCurrentValue = 0x33
    case readRecordingSetting = 0x30
    case writeRecordingSetting = 0x35
    case startRecording = 0x31
    case stopRecording = 0x32
    case passcode = 0x76
}

/// ステータスは 0x00 ACK / 0x01 以降 REFUSE など、仕様書に従って分類する。
/// 詳細は payload 先頭の status バイトに記録されているため、初期化時に解釈する。
struct TR4AStatus: Equatable {
    enum Kind: Equatable {
        case ack
        case refuse(TR4ARefuseReason)
        case busy
        case unknown(UInt8)
    }

    let raw: UInt8
    let kind: Kind

    init(raw: UInt8) {
        self.raw = raw
        switch raw {
        case 0x00: kind = .ack
        case 0x01: kind = .busy
        case 0x02: kind = .refuse(.invalidCommand)
        case 0x03: kind = .refuse(.invalidParameter)
        case 0x04: kind = .refuse(.memoryError)
        case 0x05: kind = .refuse(.securityLocked)
        default: kind = .unknown(raw)
        }
    }

    /// payload 先頭を status とみなして解釈するユーティリティ。空 payload の場合は unknown を返す。
    init(payload: ArraySlice<UInt8>) {
        guard let first = payload.first else {
            self.init(raw: 0xFF)
            return
        }
        self.init(raw: first)
    }

    var isAck: Bool { if case .ack = kind { return true } else { return false } }
}

/// REFUSE の具体的な理由を enum 化。
enum TR4ARefuseReason: Equatable {
    case invalidCommand
    case invalidParameter
    case memoryError
    case securityLocked
    case unknown(UInt8)
}

/// TR45 の現在値ペイロードをデコードした結果を保持する軽量構造体。
struct TR4ACurrentValue: Equatable {
    let channel: Int
    let temperatureC: Double
    let recordingStatus: UInt8
    let securityOn: Bool
}

/// 設定系の状態をまとめたコンテナ。UI へ公開する想定で Optional 付き。
struct TR4ADeviceState: Equatable {
    var modelName: String?
    var serial: String?
    var firmware: String?
    var loggingIntervalSec: Int?
    var recordingModeEndless: Bool?
    var isRecording: Bool?
    var securityEnabled: Bool?
}
