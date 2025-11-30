import Foundation
import SwiftUI
import UIKit

/// アプリ内でBLE通信などを可視化するシンプルなオンデバイスロガー。
/// - Note: スレッドセーフにするため専用キューでバッファを管理し、UI へは MainActor 経由で公開する。
final class Logger: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: Category
        let message: String
    }

    enum Category: String {
        case ble = "BLE"
        case bleTx = "BLE TX"
        case bleRx = "BLE RX"
        case ui = "UI"
        case general = "General"
    }

    static let shared = Logger()

    @Published private(set) var entries: [Entry] = []

    private let queue = DispatchQueue(label: "Logger.queue", qos: .utility)
    private let capacity = 500

    private init() {}

    func log(_ message: String, category: Category = .general) {
        let entry = Entry(timestamp: Date(), category: category, message: message)
        queue.async {
            var updated = self.entries
            updated.append(entry)
            if updated.count > self.capacity { updated.removeFirst(updated.count - self.capacity) }
            DispatchQueue.main.async { self.entries = updated }
        }
    }

    func exportText() -> String {
        entries.map { "\($0.timestamp) [\($0.category.rawValue)] \($0.message)" }
            .joined(separator: "\n")
    }
}

// MARK: - Utilities
extension Data {
    func hexEncodedString(separation: String = " ") -> String {
        map { String(format: "%02X", $0) }.joined(separator: separation)
    }
}

struct LoggerView: View {
    @ObservedObject var logger = Logger.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(logger.entries.reversed())) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.category.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Debug Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: logger.exportText()) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = logger.exportText()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
