import Foundation

/// BLEやUIの生ログを端末上で確認するための軽量ロガー。
/// - Attention: BLEコールバックはバックグラウンドキューから到着するため、
///   スレッドセーフなシリアルキューで蓄積し、@Published でUIへ届ける。
final class Logger: ObservableObject {
    /// シングルトンアクセス。
    static let shared = Logger()

    struct Entry: Identifiable, Equatable {
        enum Category: String {
            case bleTx = "BLE TX"
            case bleRx = "BLE RX"
            case ui = "UI"
            case general = "General"
        }

        let id = UUID()
        let timestamp: Date
        let category: Category
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    private let maxEntries = 500
    private let queue = DispatchQueue(label: "Logger.queue")

    private init() {}

    /// テキストメッセージを追記する。
    /// - Parameters:
    ///   - message: 任意のログ本文。BLE生データは hexEncodedString() で渡す。
    ///   - category: 種別。フィルタリングやUI表示で利用する。
    func log(_ message: String, category: Entry.Category = .general) {
        let entry = Entry(timestamp: Date(), category: category, message: message)
        queue.async { [weak self] in
            guard let self else { return }
            var buffer = self.entries
            buffer.append(entry)
            if buffer.count > self.maxEntries {
                buffer.removeFirst(buffer.count - self.maxEntries)
            }
            DispatchQueue.main.async {
                self.entries = buffer
            }
        }
    }

    /// 直近ログを1本のテキストとしてまとめ、共有用に返す。
    func exportText() -> String {
        entries
            .map { entry in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
                let ts = formatter.string(from: entry.timestamp)
                return "[\(ts)] [\(entry.category.rawValue)] \(entry.message)"
            }
            .joined(separator: "\n")
    }
}

extension Data {
    /// BLEパケットの可読化用に16進文字列へ変換するユーティリティ。
    func hexEncodedString() -> String {
        map { String(format: "%02X", $0) }.joined()
    }
}
