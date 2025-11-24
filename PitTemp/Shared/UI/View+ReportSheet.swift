import SwiftUI
import UIKit

extension View {
    /// Session Report 用の共通 sheet / full-screen プレゼンター。
    /// - iPad(iPadOS 15 など): detent が効かない問題を避けるため fullScreenCover で 100% 表示。
    /// - iPhone: detent を素直に解釈するので fraction(1.0) の sheet でフルハイト表示。
    @ViewBuilder
    func reportSheet<Item: Identifiable>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> some View
    ) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            fullScreenCover(item: item) { payload in
                ReportSheetContainer {
                    content(payload)
                }
                // ドラッグジェスチャは残しつつ、iPad mini ではフルスクリーンにするため detent は不要。
                .presentationDragIndicator(.visible)
            }
        } else {
            sheet(item: item) { payload in
                ReportSheetContainer {
                    content(payload)
                }
                // iPhone の sheet は detent が効くので fraction(1.0) で確実に全画面化。
                .presentationDetents([.fraction(1.0)])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct ReportSheetContainer<Content: View>: View {
    // reportSheet でラップするすべての画面に「閉じる」ボタンを強制的に載せるコンテナ。
    // iPad の fullScreenCover はスワイプで閉じられないので、UI 上に明示的な戻り導線を用意する。
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            // 学習ポイント: fullScreenCover はジェスチャで閉じられないケースがあるため、
                            // UI ボタンで dismiss() を呼ぶのが確実な戻り手段になる。
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel("Close report")
                    }
                }
        }
    }
}
