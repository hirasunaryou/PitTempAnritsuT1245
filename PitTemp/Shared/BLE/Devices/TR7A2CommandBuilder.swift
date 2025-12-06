import Foundation

/// TR7A2/A 系の SOH コマンドを組み立てるためのヘルパー。
/// - Note: 仕様書に従い、CRC16-CCITT (0x1021, init 0x0000) を Big Endian で末尾に付与する。
struct TR7A2CommandBuilder {
    /// 指定したコマンドとデータ長を持つ SOH フレームを生成する。
    /// - Parameters:
    ///   - command: SOH の次に入るコマンド種別 (例: 0x33)。
    ///   - expectedDataLength: レスポンスで返ってくるデータ部のバイト数（仕様書の表記に合わせる）。
    ///   - payload: コマンドに付与する追加ペイロード。不要なら空配列で良い。
    static func buildFrame(command: UInt8, expectedDataLength: UInt16, payload: Data = Data()) -> Data {
        // フレーム構成: SOH(0x01) | CMD | DataLen(H) | DataLen(L) | Payload... | CRC16(H) | CRC16(L)
        var frame = Data([0x01, command, UInt8((expectedDataLength >> 8) & 0xFF), UInt8(expectedDataLength & 0xFF)])
        frame.append(payload)
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    /// CRC16-CCITT (poly 0x1021, init 0x0000) を計算する。資料のC実装をSwiftへ移植。
    static func crc16CCITT(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0x0000
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
