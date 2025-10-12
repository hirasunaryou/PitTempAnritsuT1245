//
//  MetaEditorView.swift
//  PitTemp
//

import SwiftUI

struct MetaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: SessionViewModel
    @EnvironmentObject var settings: SettingsStore

    @State private var showVoiceEditor = false

    var body: some View {
        NavigationStack {
            Form {
                // 音声入力にワンタップで切り替え
                Section {
                    Button {
                        showVoiceEditor = true
                    } label: {
                        Label("Start voice input…", systemImage: "mic.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("現場では声で項目を読み上げて入力できます。録音テキストは下の各フィールドに反映されます。")
                }

                // セッション系
                Section("SESSION") {
                    TextField("TRACK", text: $vm.meta.track)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("DATE (ISO8601)", text: $vm.meta.date)
                        .keyboardType(.numbersAndPunctuation)
                    HStack {
                        TextField("TIME", text: $vm.meta.time)
                        Spacer(minLength: 12)
                        TextField("LAP", text: $vm.meta.lap)
                            .keyboardType(.numberPad)
                    }
                }

                // 車両・人
                Section("CAR & PEOPLE") {
                    TextField("CAR", text: $vm.meta.car)
                    TextField("DRIVER", text: $vm.meta.driver)
                    TextField("TYRE", text: $vm.meta.tyre)
                }

                // その他
                Section("OTHER") {
                    TextField("CHECKER", text: $vm.meta.checker)
                    Toggle("Autofill Date/Time if empty", isOn: $settings.autofillDateTime)
                }
            }
            .navigationTitle("Edit Meta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // ここで音声エディタをシート表示
            .sheet(isPresented: $showVoiceEditor) {
                MetaVoiceEditorView()
                    .environmentObject(vm)
            }
        }
    }
}
