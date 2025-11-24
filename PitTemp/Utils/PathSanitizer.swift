//
//  PathSanitizer.swift
//  PitTemp
//
//  役割: ファイル/フォルダ名に使えるよう文字列を安全な形に整形する小さなユーティリティ。
//  初心者向けメモ: OSは一部の文字や長さに制約があるので、事前に"_"へ置換したり長さ制限をかけておくと
//  後からパス解釈で失敗しにくくなります。
//

import Foundation

extension String {
    /// ファイル/フォルダのパスコンポーネントとして使えるように無難な文字へ整形する。
    /// - Parameter limit: 文字数上限（0 の場合は無制限）。
    /// - Returns: 末尾のドット/ハイフン/アンダースコアを取り除いた安全な文字列。
    func sanitizedPathComponent(limit: Int = 48) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let collapsed = trimmed.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "_",
            options: .regularExpression
        )

        let deduped = collapsed
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))

        if limit > 0 && deduped.count > limit {
            let index = deduped.index(deduped.startIndex, offsetBy: limit)
            return String(deduped[..<index])
        }

        return deduped
    }
}
