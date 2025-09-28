import Foundation

@MainActor
extension SessionViewModel {
    /// 音声起こし等のテキストを指定ホイールのメモに追記
    func appendMemo(_ text: String, to wheel: WheelPos) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let old = wheelMemos[wheel], !old.isEmpty {
            wheelMemos[wheel] = old + " " + trimmed
        } else {
            wheelMemos[wheel] = trimmed
        }
    }
}
