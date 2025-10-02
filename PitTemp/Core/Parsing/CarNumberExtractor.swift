// Core/Parsing/CarNumberExtractor.swift
import Foundation

enum CarNumberExtractor {
    /// 末尾の数字ブロックを CarNo として抽出（全角→半角を許容）
    static func extract(from raw: String) -> (carNo: String?, normalizedRaw: String) {
        let normalized = toHalfWidthDigits(raw)
        // 末尾の連続数字（空白を挟まない）を拾う
        let pattern = #"([0-9]+)\s*$"#
        if let r = normalized.range(of: pattern, options: .regularExpression) {
            return (String(normalized[r]).trimmingCharacters(in: .whitespaces), normalized)
        }
        return (nil, normalized)
    }

    /// 全角数字を半角に正規化（日本語音声の誤変換対策）
    private static func toHalfWidthDigits(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            // '０'(0xFF10)〜'９'(0xFF19)
            if scalar.value >= 0xFF10 && scalar.value <= 0xFF19 {
                let half = UnicodeScalar(scalar.value - 0xFF10 + 0x30)!
                out.unicodeScalars.append(half)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
