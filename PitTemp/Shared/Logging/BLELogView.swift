import SwiftUI
import UIKit

/// BLE 通信ログをアプリ内で確認・共有するための簡易ビュー。
/// - Note: Logger.shared の entries をそのまま一覧表示し、コピー/共有ボタンを備える。
struct BLELogView: View {
    @ObservedObject private var logger = Logger.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false
    @State private var shareItem: String = ""

    var body: some View {
        NavigationStack {
            List(logger.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(formatted(date: entry.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.category.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                    }
                    Text(entry.message)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("BLE Debug Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = logger.exportText()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    Button {
                        shareItem = logger.exportText()
                        isSharing = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $isSharing) {
                ShareSheet(activityItems: [shareItem])
            }
        }
    }

    private func formatted(date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }
}

/// UIActivityViewController ラッパー
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
