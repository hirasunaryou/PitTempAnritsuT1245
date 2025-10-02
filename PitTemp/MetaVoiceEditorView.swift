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
                    FieldRow(
                        field: f,
                        value: value(for: f),
                        isRecording: (speech.isRecording && targetField == f),
                        onDictate: {
                            // 他の録音があれば反映してから開始
                            let (_, prevText) = speech.stopAndTakeText()
                            if !prevText.isEmpty, let tf = targetField { apply(text: prevText, to: tf) }
                            try? speech.start(for: .FL) // wheelは未使用
                            targetField = f
                            Haptics.impactLight()
                        },
                        onStop: {
                            speech.stop()
                            let t = speech.takeFinalText()
                            if !t.isEmpty { apply(text: t, to: f) }
                            targetField = nil
                        },
                        onEdit: {
                            draftText = value(for: f)
                            editingField = f
                        },
                        onClear: {
                            setValue("", for: f)
                        }
                    )
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

    // MARK: - 行コンポーネント（アイコンのみ／狭い幅で値を下段へ）
    private struct FieldRow: View {
        let field: MetaVoiceEditorView.Field
        let value: String
        let isRecording: Bool
        let onDictate: () -> Void
        let onStop: () -> Void
        let onEdit: () -> Void
        let onClear: () -> Void

        var body: some View {
            GeometryReader { geo in
                let narrow = geo.size.width < 360
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(field.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .leading)

                        Spacer(minLength: 0)

                        if isRecording {
                            Button(action: onStop) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 22, weight: .semibold))
                            }
                            .buttonStyle(PillIconButtonStyle(prominent: true))
                            .accessibilityLabel("Stop recording")
                        } else {
                            HStack(spacing: 10) {
                                Button(action: onDictate) {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                .buttonStyle(PillIconButtonStyle())
                                .accessibilityLabel("Dictate")

                                Button(action: onEdit) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                .buttonStyle(PillIconButtonStyle())
                                .accessibilityLabel("Edit")

                                Button(role: .destructive, action: onClear) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 18, weight: .semibold))
                                }
                                .buttonStyle(PillIconButtonStyle(destructive: true))
                                .accessibilityLabel("Clear")
                            }
                        }
                    }

                    if narrow {
                        Text(value.isEmpty ? "-" : value)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 76)
                    } else {
                        HStack {
                            Spacer()
                            Text(value.isEmpty ? "-" : value)
                                .font(.headline)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    Divider().opacity(0.15)
                }
            }
            .frame(height: 72)
        }
    }

    private struct PillIconButtonStyle: ButtonStyle {
        var prominent = false
        var destructive = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(destructive ? .red : (prominent ? .white : .blue))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(destructive ? Color.red.opacity(0.12)
                                          : (prominent ? Color.blue : Color.blue.opacity(0.12)))
                )
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
        }
    }

    // MARK: - 反映・値操作
    private func apply(text: String, to field: Field) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        switch mode {
        case .append:
            var meta = vm.meta
            if field == .car {
                // 既存値と空白区切りで連結 → 抽出
                let joined = [meta.car, cleaned]
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .joined(separator: " ")
                let (no, raw) = CarNumberExtractor.extract(from: joined)
                meta.car = raw                       // 画面表示は全文
                meta.carNo = no ?? meta.carNo        // 見つかったら更新
                meta.carNoAndMemo = raw              // 常に全文保持
            } else {
                field.append(cleaned, to: &meta)
            }
            vm.meta = meta

        case .replace:
            if field == .car {
                let (no, raw) = CarNumberExtractor.extract(from: cleaned)
                vm.meta.car = raw
                vm.meta.carNo = no ?? ""
                vm.meta.carNoAndMemo = raw
            } else {
                setValue(cleaned, for: field)
            }
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
        case .tyre:    vm.meta.tyre = newValue
        case .checker: vm.meta.checker = newValue
        }
    }

    private func value(for f: Field) -> String {
        switch f {
        case .track:   return vm.meta.track
        case .date:    return vm.meta.date
        case .time:    return vm.meta.time
        case .lap:     return vm.meta.lap
        case .car:     return vm.meta.car
        case .driver:  return vm.meta.driver
        case .tyre:    return vm.meta.tyre
        case .checker: return vm.meta.checker
        }
    }
}
