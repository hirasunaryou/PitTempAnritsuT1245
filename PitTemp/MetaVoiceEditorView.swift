//
//  MetaVoiceEditorView.swift
//  PitTemp
//

import SwiftUI

/// メタ情報の音声入力版エディタ。
/// 1フィールドずつ「録音→停止→追記/上書き」+ 手動編集/消去ができる。
struct MetaVoiceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: SessionViewModel

    @StateObject private var speech = SpeechMemoManager() // 既存の音声起こしマネージャを再利用
    @State private var targetField: Field?

    // 反映モード
    private enum ApplyMode: String, CaseIterable, Identifiable {
        case append = "Append"
        case replace = "Replace"
        var id: String { rawValue }
    }

    @State private var mode: ApplyMode = .append        // 追記/上書き 切替
    @State private var editingField: Field? = nil       // 手動編集対象
    @State private var draftText: String = ""           // 手動編集用

    enum Field: String, CaseIterable, Identifiable {
        case track, date, time, lap, car, driver, tyre, checker
        var id: String { rawValue }
        var label: String {
            switch self {
            case .track: "TRACK"
            case .date: "DATE"
            case .time: "TIME"
            case .lap: "LAP"
            case .car: "CAR"
            case .driver: "DRIVER"
            case .tyre: "TYRE"
            case .checker: "CHECKER"
            }
        }
        /// 追記の仕方を統一
        func append(_ text: String, to meta: inout MeasureMeta) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            func join(_ old: inout String) { old = old.isEmpty ? t : (old + " " + t) }
            switch self {
            case .track:   join(&meta.track)
            case .date:    join(&meta.date)
            case .time:    join(&meta.time)
            case .lap:     join(&meta.lap)
            case .car:     join(&meta.car)
            case .driver:  join(&meta.driver)
            case .tyre:    join(&meta.tyre)
            case .checker: join(&meta.checker)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Field.allCases) { f in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.label).font(.caption).foregroundStyle(.secondary)
                            Text(value(for: f).isEmpty ? "-" : value(for: f))
                                .font(.headline)
                                .lineLimit(2)
                        }
                        Spacer()

                        if speech.isRecording && targetField == f {
                            Button {
                                speech.stop()
                                let t = speech.takeFinalText()
                                if !t.isEmpty { apply(text: t, to: f) }
                                targetField = nil
                            } label: {
                                Label("Stop", systemImage: "stop.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            HStack(spacing: 8) {
                                Button {
                                    let (_, prevText) = speech.stopAndTakeText()
                                    if !prevText.isEmpty, let tf = targetField { apply(text: prevText, to: tf) }
                                    try? speech.start(for: .FL)   // wheelは未使用ダミー
                                    targetField = f
                                    Haptics.impactLight()
                                } label: { Label("Dictate", systemImage: "mic.fill") }
                                .buttonStyle(.bordered)
                                .disabled(!speech.isAuthorized)

                                Button {
                                    // 手動編集を開始
                                    draftText = value(for: f)
                                    editingField = f
                                } label: { Label("Edit", systemImage: "pencil") }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    setValue("", for: f)
                                } label: { Label("Clear", systemImage: "trash") }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Edit Meta (Voice)")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $mode) {
                        ForEach(ApplyMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // 録音中なら止めて反映
                        let (_, prevText) = speech.stopAndTakeText()
                        if !prevText.isEmpty, let t = targetField { apply(text: prevText, to: t) }
                        targetField = nil
                        dismiss()
                    }
                }
            }
        }
        .onAppear { speech.requestAuth(); vm.stopAll() }
        .sheet(item: $editingField) { f in
            NavigationStack {
                Form {
                    Section(f.label) {
                        TextField("Enter text", text: $draftText, axis: .vertical)
                            .textInputAutocapitalization(.characters)
                    }
                }
                .navigationTitle("Edit \(f.label)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingField = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            apply(text: draftText, to: f)   // モードに従い反映
                            editingField = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - 反映・値操作
    private func apply(text: String, to field: Field) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        switch mode {
        case .append:
            var meta = vm.meta
            field.append(cleaned, to: &meta)
            vm.meta = meta
        case .replace:
            setValue(cleaned, for: field)
        }
    }

    private func setValue(_ newValue: String, for f: Field) {
        switch f {
        case .track:   vm.meta.track = newValue
        case .date:    vm.meta.date = newValue
        case .time:    vm.meta.time = newValue
        case .lap:     vm.meta.lap = newValue
        case .car:     vm.meta.car = newValue
        case .driver:  vm.meta.driver = newValue
        case .tyre:    vm.meta.tyre = newVal
