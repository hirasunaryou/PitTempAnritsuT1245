import Foundation

/// ファイル名・パスコンポーネントに使えない文字を無害化するための小さなヘルパー。
/// SessionIDのように人間可読な文字列をそのままファイル名に使う場合に安全弁として利用する。
extension String {
    func safeFileToken(limit: Int = 96) -> String {
        let replaced = replacingOccurrences(of: "[/:\\]", with: "_", options: .regularExpression)
        if limit > 0 && replaced.count > limit {
            let idx = replaced.index(replaced.startIndex, offsetBy: limit)
            return String(replaced[..<idx])
        }
        return replaced
    }
}
