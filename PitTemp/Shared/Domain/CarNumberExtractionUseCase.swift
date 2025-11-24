import Foundation

/// 車両番号に関する抽出結果をまとめた DTO。UI でそのまま使えるよう、
/// 正規化済みの文字列を保持している。
struct CarNumberExtractionResult {
    let cleanedCarText: String
    let carNumber: String
    let memoText: String
}

/// 車両番号の抽出を担当するユースケース。
/// - Note: 末尾に連続する数字を「車番」と見なし、それ以外はメモとして保持する
///   シンプルなルールにしている。将来ルールを差し替える際も ViewModel への
///   影響を最小限に抑えられる。
protocol CarNumberExtracting {
    func extract(from rawText: String) -> CarNumberExtractionResult
}

struct CarNumberExtractionUseCase: CarNumberExtracting {
    private let trailingDigitsRegex = try! NSRegularExpression(pattern: #"(\d{1,4})(?!.*\d)"#, options: [])

    func extract(from rawText: String) -> CarNumberExtractionResult {
        // 1) 余分な空白や全角スペースを削って読みやすくする。
        let normalizedSpaces = rawText
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2) 末尾側にある連続した数字を車番候補として取り出す。
        let number = matchTrailingDigits(in: normalizedSpaces)

        // 3) carNoAndMemo 用には空白整理だけ行い、「元テキストの記録」を残す。
        let memoText = normalizedSpaces

        // SwiftUI のバインディングに渡しやすい形にまとめて返す。
        return CarNumberExtractionResult(cleanedCarText: normalizedSpaces, carNumber: number, memoText: memoText)
    }

    private func matchTrailingDigits(in text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = trailingDigitsRegex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: text) else { return "" }
        return String(text[swiftRange])
    }
}
