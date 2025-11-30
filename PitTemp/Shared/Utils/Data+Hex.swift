//
//  Data+Hex.swift
//  PitTemp
//
//  TR45/TR4A SOH コマンドの送受信フレームをUIへ見せるためのヘルパー。
//  16進ダンプはデバッグログで頻出するため、どこからでも呼べる拡張として切り出しておく。
//

import Foundation

extension Data {
    /// 1バイトずつ2桁の16進文字列へ変換するユーティリティ。
    /// - Note: BLEログ表示では大小文字で悩まないよう小文字固定とし、スペースで区切って読みやすくしている。
    var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
