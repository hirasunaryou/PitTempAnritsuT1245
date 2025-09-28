//
//  HIDTextFieldCaptureView.swift
//  PitTemp
//
//  役割: HR-2500 を「外付けキーボード」として受けるための隠し UITextField
//  初心者向けメモ:
//   - SwiftUI だけでは「物理キーボードのキー」を細かく扱いにくい → UIViewRepresentable で橋渡し
//   - inputView に空の UIView を入れてソフトキーボードを抑止（HIDは受ける）
//

import SwiftUI
import UIKit

struct HIDTextFieldCaptureView: UIViewRepresentable {
    var onLine: (String) -> Void                  // 改行などで1行確定した時の通知
    var onSpecial: ((String) -> Void)? = nil      // "<RET>" 等（いまは Return のみ使用）
    var onBuffer: ((String) -> Void)? = nil       // 打鍵途中のスナップショット
    var isActive: Bool                            // true の間は FirstResponder を維持
    @Binding var showField: Bool                  // デバッグ表示の ON/OFF
    @Binding var focusTick: Int                   // 値が変わると becomeFirstResponder を再実行

    final class KeySinkTF: UITextField, UITextFieldDelegate {
        var onLine: ((String) -> Void)?
        var onSpecial: ((String) -> Void)?
        var onBuffer: ((String) -> Void)?
        var buffer: String = ""

        override var canBecomeFirstResponder: Bool { true }
        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            autocorrectionType = .no; autocapitalizationType = .none
            spellCheckingType = .no; keyboardType = .numbersAndPunctuation
            returnKeyType = .default; enablesReturnKeyAutomatically = false
            inputView = UIView() // ソフトキーボード抑止
            inputAssistantItem.leadingBarButtonGroups = []
            inputAssistantItem.trailingBarButtonGroups = []
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty { _ = buffer.popLast(); textField.text = buffer; return false }
            for ch in string { handleChar(ch) }
            textField.text = buffer
            onBuffer?(buffer)
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
//            onSpecial?("<RET>")
            onLine?(buffer)
            buffer.removeAll(keepingCapacity: true)
            textField.text = buffer
            return false
        }

        // 矢印キーなどは端末依存の挙動も多い → いったん拾わない
        override var keyCommands: [UIKeyCommand]? { [] }

        private func handleChar(_ ch: Character) {
            switch ch {
            case "\n", "\r":
                onLine?(buffer); buffer.removeAll(keepingCapacity: true)
            default:
                buffer.append(ch)
            }
            onBuffer?(buffer)
        }
    }

    func makeUIView(context: Context) -> KeySinkTF {
        let tf = KeySinkTF()
        tf.onLine = onLine; tf.onSpecial = onSpecial; tf.onBuffer = onBuffer
        tf.alpha = showField ? 1.0 : 0.01
        tf.borderStyle = .roundedRect
        return tf
    }

    func updateUIView(_ uiView: KeySinkTF, context: Context) {
        uiView.isHidden = !showField
        uiView.alpha = showField ? 1.0 : 0.01

        if isActive || showField {
            DispatchQueue.main.async { _ = uiView.becomeFirstResponder() }
        } else {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }

        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async { _ = uiView.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastFocusTick = 0 }
}
