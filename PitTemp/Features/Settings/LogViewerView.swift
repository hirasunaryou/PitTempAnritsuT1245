//
//  LogViewerView.swift
//  PitTemp
//
//  ログ確認用のモーダル。生徒に説明する気持ちで「コピー」「共有」の導線を明示する。

import SwiftUI
import UIKit

struct LogViewerView: View {
    @ObservedObject var logger = Logger.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List(logger.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("[\(entry.category.rawValue)] \(entry.message)")
                        .font(.footnote)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Debug Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = logger.joinedText()
                        copied = true
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: logger.joinedText()) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .alert("Copied", isPresented: $copied) {
                Button("OK", role: .cancel) { copied = false }
            }
        }
    }
}

struct LogViewerView_Previews: PreviewProvider {
    static var previews: some View {
        LogViewerView()
    }
}
