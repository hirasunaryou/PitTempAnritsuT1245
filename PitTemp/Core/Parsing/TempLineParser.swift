//
//  TempLineParser.swift
//  Core/Parsing
//
//  HR-2500 などの外部HIDから流れる1行テキストから温度値(Double)を抽出する純粋ロジック。
//  - UI/OSに依存しないため XCTest で安全にテストできます。
//  - 小数点は '.' と ',' の両方を許容（欧州配列の対策）。
//  - 1行に複数数値があれば「最初の1つ」を採用（機器の前置/後置ノイズ対策）。
//

import Foundation

public enum TempParseError: Error, Equatable {
    case noNumber
    case outOfRange(ClosedRange<Double>)
}

public struct TempLineParser {
    /// 許容する温度範囲の既定値（必要に応じて変更）
    public static let defaultRange: ClosedRange<Double> = -30.0...200.0

    /// 1行テキストから最初の数値を抽出
    /// - Parameters:
    ///   - line: 入力行（CR/LF は事前に除去してOK）
    ///   - clamp: 許容範囲。nil の場合は範囲チェックなし
    /// - Returns: 成功時は Double、失敗時は throw
    public static func parse(_ line: String, clamp: ClosedRange<Double>? = defaultRange) throws -> Double {
        // 1) 前後空白をカット & 小数点 ',' → '.' に統一
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let unified = trimmed.replacingOccurrences(of: ",", with: ".")

        // 2) 正規表現で「[-+]?digits[.digits]?」を最初に1つ拾う
        //    例: "-12.5", "+8", "  23 "
        let pattern = #"[-+]?\d+(?:\.\d+)?"#
        guard let range = unified.range(of: pattern, options: .regularExpression) else {
            throw TempParseError.noNumber
        }
        let token = String(unified[range])

        guard let value = Double(token) else {
            throw TempParseError.noNumber
        }

        if let clamp = clamp, !clamp.contains(value) {
            throw TempParseError.outOfRange(clamp)
        }
        return value
    }
}
