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
                // まとめ録り（シート）も残しておく
                Section {
                    Button {
                        showVoiceEditor = true
                    } label: {
                        Label("Start voice input…", systemImage: "mic.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // --- SESSION ---
                Section("SESSION") {
                    FieldRow(label: "TRACK", text: $vm.meta.track)
                    FieldRow(label: "DATE (ISO8601)", text: $vm.meta.date, keyboard: .numbersAndPunctuation)
                    HStack {
                        FieldRow(label: "TIME", text: $vm.meta.time)
                        FieldRow(label: "LAP", text: $vm.meta.lap, keyboard: .numberPad)
                    }
                }

                // --- CAR & PEOPLE ---
                Section("CAR & PEOPLE") {
                    FieldRow(label: "CAR", text: $vm.meta.car)
                    FieldRow(label: "DRIVER", text: $vm.meta.driver)
                    FieldRow(label: "TYRE", text: $vm.meta.tyre)
                }

                // --- OTHER ---
                Section("OTHER") {
                    FieldRow(label: "CHECKER", text: $vm.meta.checker)
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
            .sheet(isPresented: $showVoiceEditor) {
                MetaVoiceEditorView().environmentObject(vm)
            }
        }
    }
}

/// テキストフィールド + 右端に“その欄だけ音声入力”ボタン
private struct FieldRow: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    @StateObject private var speech = SpeechMemoManager()
    @State private var interim: String = ""
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            TextField(label, text: $text)
                .keyboardType(keyboard)

            // マイクボタン
            Button {
                if isRecording {
                    stopAndApply()
                } else {
                    start()
                }
            } label: {
                Label(isRecording ? "Stop" : "Mic", systemImage: isRecording ? "stop.circle.fill" : "mic.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!speech.isAuthorized)
        }
        .onAppear { speech.requestAuth() }
        .onDisappear { if isRecording { speech.stop() } }
    }

    private func start() {
        interim.removeAll()
        do {
            // “どのホイールか”などの文脈は不要なので ダミーとして.FLを入れている
            try speech.start(for: .FL)
            isRecording = true
        } catch {
            isRecording = false
        }
    }

    private func stopAndApply() {
        speech.stop()
        isRecording = false
        let t = speech.takeFinalText().trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { text = t }
    }
}
