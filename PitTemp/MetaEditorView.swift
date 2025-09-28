//
//  MetaEditorView.swift
//  PitTemp
//
//  Created by development solution on 2025/09/22.
//

// MetaEditorView.swift
import SwiftUI

/// 役割: メタ情報(Track/Date/Car/Driver/Tyre/Time/Lap/Checker)の編集専用
/// ポイント:
///  - HIDTextFieldCaptureView を置かない＝温度計のキーはここでは無視
///  - @EnvironmentObject var vm のみを使って直接 vm.meta を編集
// MetaEditorView.swift


struct MetaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: SessionViewModel

    @State private var blockExternalKeys = true   // ← デフォルトで“遮断ON”

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Block external keyboard while editing", isOn: $blockExternalKeys)
                        .tint(.orange)
                        .font(.footnote)
                }

                Section("Session") {
                    TextField("TRACK", text: $vm.meta.track)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("DATE (ISO8601)", text: $vm.meta.date)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("TIME", text: $vm.meta.time).keyboardType(.numbersAndPunctuation)
                        TextField("LAP",  text: $vm.meta.lap).keyboardType(.numbersAndPunctuation)
                    }
                }

                Section("Car & People") {
                    TextField("CAR", text: $vm.meta.car)
                    TextField("DRIVER", text: $vm.meta.driver)
                    TextField("TYRE", text: $vm.meta.tyre)
                    TextField("CHECKER", text: $vm.meta.checker)
                }

                Section {
                    Toggle("Autofill Date/Time if empty", isOn: $vm.autofillDateTime)
                }
            }
            .navigationTitle("Edit Meta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            // ← これが“外部キーボード食い止めフィルタ”
            .background(HardwareKeyEater(isEnabled: blockExternalKeys))
        }
        .onAppear {
            // 念のため、計測は止めておく（HIDTextFieldCaptureはMeasure側にしか置いてない想定）
            vm.stopAll()
        }
    }
}
