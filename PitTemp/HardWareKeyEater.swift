////
////  HardWareKeyEater.swift
////  PitTemp
////
////  Created by development solution on 2025/09/22.
////
//
//// HardwareKeyEater.swift
//// 役割: 接続中の外部キーボードからのキー入力を“最前面で受け取って破棄”する
//// ポイント:
////  - SwiftUI 上に置ける UIViewRepresentable
////  - canBecomeFirstResponder = true で最優先フォーカスを取り、pressesBegan/Endedを握り潰す
////  - アプリの他UI(TextFieldなど)にフォーカスが移らないので、外部HIDの数字が流入しない
////  - isEnabled=false のときは何もしない（通常の入力を許可）
////　補足説明
////
////EaterView が firstResponder を掴んでいる間、外部キーボードのキーはここで完結します（下層の TextField まで届かない）。
////
////画面としては通常通り編集できます（ペースト、タップ編集、音声入力などはOK）。
////
////物理キーボードのタイプだけが無効になります。必要に応じてトグルで一時解除可。
//
//
//import SwiftUI
//import UIKit
//
//struct HardwareKeyEater: UIViewRepresentable {
//    var isEnabled: Bool
//
//    func makeUIView(context: Context) -> EaterView {
//        let v = EaterView()
//        v.isEnabled = isEnabled
//        return v
//    }
//
//    func updateUIView(_ uiView: EaterView, context: Context) {
//        uiView.isEnabled = isEnabled
//        if isEnabled {
//            // 画面表示直後でも確実にファーストレスポンダを奪う
//            DispatchQueue.main.async {
//                _ = uiView.becomeFirstResponder()
//            }
//        } else {
//            uiView.resignFirstResponder()
//        }
//    }
//
//    final class EaterView: UIView {
//        var isEnabled: Bool = false
//
//        override var canBecomeFirstResponder: Bool { true }
//
////        // 外部キーボードの keyCommands を大量に宣言して先取りする
////        // （実際には pressesBegan/Ended で握り潰すので何でも可）
////        override var keyCommands: [UIKeyCommand]? {
////            guard isEnabled else { return [] }
////            // よく来るキーを一通り。input = nil でも呼ばれるが、念のため。
////            let common: [String] = [
////                UIKeyCommand.inputUpArrow, UIKeyCommand.inputDownArrow,
////                UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow,
////                UIKeyCommand.inputEscape, "\r", "\t", " ", "0","1","2","3","4","5","6","7","8","9",
////                ".", "-", "+", "e", "E"
////            ]
////            return common.map { UIKeyCommand(input: $0, modifierFlags: [], action: #selector(swallow)) }
////        }
//
////        @objc private func swallow(_: UIKeyCommand) {
////            // 何もしない＝消化
////        }
////
////        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
////            guard isEnabled else { return super.pressesBegan(presses, with: event) }
////            // 受け取って終了（next へ渡さない）
//        }
////        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
////            guard isEnabled else { return super.pressesEnded(presses, with: event) }
////        }
////        override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
////            guard isEnabled else { return super.pressesChanged(presses, with: event) }
////        }
////        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
////            guard isEnabled else { return super.pressesCancelled(presses, with: event) }
////        }
////    }
//}
