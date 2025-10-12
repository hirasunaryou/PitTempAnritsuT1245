import SwiftUI

/// BLE版では不要。ビルド通過用のダミー実装（後で削除OK）
struct HIDTextFieldCaptureView: View {
    var onLine:    (String) -> Void
    var onSpecial: (String) -> Void
    var onBuffer:  (String) -> Void
    var isActive:  Bool
    @Binding var showField: Bool
    @Binding var focusTick: Int

    var body: some View {
        // 何もしない透明ビュー
        Color.clear.opacity(0.001)
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }
}
