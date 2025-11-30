import Foundation

/// BLE/アプリ内部のトラブルシュート用リングバッファーロガー。
/// - Important: UIスレッドから安全に呼べるようにスレッドセーフなキューで保護する。
final class Logger {
    enum Category: String {
        case bleSend = "BLE SEND"
        case bleReceive = "BLE RECV"
        case ui = "UI"
        case general = "GENERAL"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: Category
        let message: String
    }

    static let shared = Logger()
    private init() {}

    private let queue = DispatchQueue(label: "com.pittemp.logger", qos: .utility)
    private let maxEntries = 500
    private var entries: [Entry] = []

    /// 最新ログを取得するためのスナップショット。
    var snapshot: [Entry] {
        queue.sync { entries }
    }

    func log(_ message: String, category: Category = .general) {
        let entry = Entry(timestamp: Date(), category: category, message: message)
        queue.async { [weak self] in
            guard let self else { return }
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
    }

    /// ログ全体を共有用テキストとして整形する。
    func exportText() -> String {
        snapshot.map { entry in
            let date = Self.dateFormatter.string(from: entry.timestamp)
            return "\(date) [\(entry.category.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()
}

extension Data {
    /// 可読性を重視した HEX 文字列化ユーティリティ。
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
