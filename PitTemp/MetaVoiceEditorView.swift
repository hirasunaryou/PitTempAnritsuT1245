//
//  MetaVoiceEditorView.swift
//  PitTemp
//

import SwiftUI

/// メタ情報の音声入力版エディタ。
/// 1フィールドずつ「録音→停止→追記」できる最小構成。
struct MetaVoiceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: SessionViewModel

    @StateObject private var speech = SpeechMemoManager() // 既存の音声起こしマネージャを再利用
    @State private var targetField: Field?

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
                                if !t.isEmpty { f.append(t, to: &vm.meta) }
                                targetField = nil
                            } label: {
                                Label("Stop", systemImage: "stop.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button {
                                // もし他のフィールドで録音中なら取り出して反映してから開始
                                let (prevWheel, prevText) = speech.stopAndTakeText()
                                _ = prevWheel // メモ用のwheelは使わない
                                if !prevText.isEmpty, let t = targetField {
                                    t.append(prevText, to: &vm.meta)
                                }
                                try? speech.start(for: .FL) // ダミー（内部でwheelは使わない前提）
                                targetField = f
                                Haptics.impactLight()
                            } label: {
                                Label("Dictate", systemImage: "mic.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!speech.isAuthorized)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Edit Meta (Voice)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // 録音中なら止めて反映
                        let (prevWheel, prevText) = speech.stopAndTakeText()
                        _ = prevWheel
                        if !prevText.isEmpty, let t = targetField { t.append(prevText, to: &vm.meta) }
                        targetField = nil
                        dismiss()
                    }
                }
            }
        }
        .onAppear { speech.requestAuth(); vm.stopAll() }
    }

    private func value(for f: Field) -> String {
        switch f {
        case .track: vm.meta.track
        case .date: vm.meta.date
        case .time: vm.meta.time
        case .lap: vm.meta.lap
        case .car: vm.meta.car
        case .driver: vm.meta.driver
        case .tyre: vm.meta.tyre
        case .checker: vm.meta.checker
        }
    }
}
