//  Logger.swift
//  PitTemp
//  Role: BLE/UI/システムの簡易オンデバイスロガー。最新500件をリングバッファで保持し、
//        デバッグ共有（コピー/共有シート）を容易にする。

import Foundation

/// ロガーのカテゴリー。BLE送信/受信/UIなどを区別し、読みやすくする。
enum LogCategory: String, CaseIterable, Codable {
    case bleTx = "BLE-TX"
    case bleRx = "BLE-RX"
    case ui = "UI"
    case system = "SYSTEM"
}

/// 1行分のログ。
struct LogEntry: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let message: String

    var formatted: String {
        let formatter = ISO8601DateFormatter()
        return "\(formatter.string(from: timestamp)) [\(category.rawValue)] \(message)"
    }
}

/// 端末内でログを閲覧・共有するための軽量シングルトン。
final class Logger: ObservableObject {
    static let shared = Logger()

    /// 直近のログ一覧（常にメインスレッドから参照される想定）
    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 500
    private let queue = DispatchQueue(label: "jp.pittemp.logger", qos: .utility)

    private init() {}

    /// ログ1行を追加する。内部ではバックグラウンドでリングバッファを更新し、UIへ通知する。
    func log(_ message: String, category: LogCategory = .system) {
        let entry = LogEntry(timestamp: Date(), category: category, message: message)
        queue.async {
            var next = self.entries
            next.append(entry)
            if next.count > self.maxEntries { next.removeFirst(next.count - self.maxEntries) }
            DispatchQueue.main.async { self.entries = next }
        }
    }

    /// 共有用に全行を結合したテキストを生成する。
    func joinedText() -> String {
        entries.map { $0.formatted }.joined(separator: "\n")
    }
}
