import Foundation

/// 簡易的な BLE デバッグ用ログエントリ。
/// - Note: UILog とは別に "BLE の何が起きているか" を時系列で確認するために用意。
struct BLEDebugLogEntry: Identifiable, Equatable {
    enum Level: String {
        case info
        case warning
        case error
    }

    let id = UUID()
    let createdAt: Date
    let message: String
    let level: Level

    init(message: String, level: Level = .info, createdAt: Date = Date()) {
        self.message = message
        self.level = level
        self.createdAt = createdAt
    }
}
