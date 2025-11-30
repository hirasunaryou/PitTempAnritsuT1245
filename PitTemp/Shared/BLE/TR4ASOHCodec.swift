//
//  TR4ASOHCodec.swift
//  PitTemp
//
//  TR45 を含む TR4A 系 SOH コマンドの組み立てと簡易パースをまとめたクラス。
//  仕様に沿って CRC16-CCITT を計算し、0x00 ブレーク付きで書き込む Data を生成する。
//  今回は 0x33 現在値取得を中心にしているが、他のコマンドでも再利用できるよう汎用化しておく。
//

import Foundation

/// TR4A の SOH コマンドをまとめて扱うシンプルなコンポーネント。
/// - Important: 2/4/8byte のデータは Little Endian、CRC は Big Endian で配置する。
final class TR4ASOHCodec {
    /// 与えられたコマンド要素を SOH フレームへまとめる。
    /// - Parameters:
    ///   - command: SOH コマンドコード（例: 0x33 現在値取得）。
    ///   - subcommand: サブコマンド。現在値取得では 0x00 を利用する。
    ///   - payload: データ部。0x33 は仕様に従い 4 バイトの 0x00 を送る。
    ///   - includeBreak: 先頭に 0x00 の BREAK を付与するかどうか。TR4A は付与推奨。
    /// - Returns: 0x00（任意） + SOH〜CRC16 までを含むデータ。
    func buildFrame(command: UInt8, subcommand: UInt8, payload: Data = Data(), includeBreak: Bool = true) -> Data {
        var frame = Data()
        frame.append(0x01) // SOH
        frame.append(command)
        frame.append(subcommand)

        var length = UInt16(payload.count)
        // Little Endian で長さを入れる
        frame.append(UInt8(length & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(payload)

        // CRC16-CCITT を計算（初期値 0xFFFF / 多項式 0x1021 / Big Endian で格納）
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))

        if includeBreak {
            var wrapped = Data([0x00])
            wrapped.append(frame)
            return wrapped
        } else {
            return frame
        }
    }

    /// TR4A 仕様に従って CRC16-CCITT を計算する。
    /// - Note: SOH 以降のバイト列を対象とし、ビットシフト演算は 16bit 幅で保持する。
    func crc16CCITT(_ data: Data) -> UInt16 {
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
