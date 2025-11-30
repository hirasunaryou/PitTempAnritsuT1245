import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// BLE ログの最新 500 行を確認・共有するためのシンプルなビュー。
struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [Logger.Entry] = Logger.shared.snapshot

    private var exportText: String { Logger.shared.exportText() }

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.dateFormatter.string(from: entry.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("[\(entry.category.rawValue)] \(entry.message)")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .onAppear { refresh() }
            .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                refresh()
            }
            .navigationTitle("Device Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = exportText
                        #endif
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: exportText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func refresh() {
        entries = Logger.shared.snapshot
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
}

#Preview {
    DebugLogView()
}
