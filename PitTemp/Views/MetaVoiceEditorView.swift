//
//  MetaVoiceEditorView.swift
//  PitTemp
//

import SwiftUI

/// 既存の SpeechMemoManager を使って音声 → テキスト化し、
/// そのテキストから各メタ項目(Track/Car/Driver/…）を抽出・反映する簡易エディタ。
struct MetaVoiceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: SessionViewModel

    @StateObject private var speech = SpeechMemoManager()

    @State private var transcript: String = ""
    @State private var lastError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                // 録音状態表示 + 操作
                HStack(spacing: 12) {
                    Group {
                        if speech.isRecording {
                            Label("録音中…", systemImage: "record.circle.fill")
                                .foregroundStyle(.red)
                        } else {
                            Label("待機中", systemImage: "mic")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.headline)

                    Spacer()

                    if speech.isRecording {
                        Button {
                            stopRecordingAndAppend()
                        } label: {
                            Label("Stop", systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            // SpeechMemoManager.start(for:) が WheelPos 必須のため
                            // メタ入力ではダミーで .FL を渡して録音のみ利用する
                            do { try speech.start(for: .FL) } catch {
                                lastError = error.localizedDescription
                            }
                        } label: {
                            Label("Start", systemImage: "mic.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!speech.isAuthorized)
                    }
                }

                // 音声→テキスト結果
                TextEditor(text: $transcript)
                    .font(.body)
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.top, 4)

                HStack {
                    Button {
                        transcript.removeAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        applyTranscriptToMeta()
                    } label: {
                        Label("テキストから反映", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // 現在のメタ（読み取り専用プレビュー）
                VStack(alignment: .leading, spacing: 6) {
                    metaRow("TRACK", vm.meta.track)
                    metaRow("DATE", vm.meta.date)
                    metaRow("TIME", vm.meta.time)
                    metaRow("CAR", vm.meta.car)
                    metaRow("DRIVER", vm.meta.driver)
                    metaRow("TYRE", vm.meta.tyre)
                    metaRow("LAP", vm.meta.lap)
                    metaRow("CHECKER", vm.meta.checker)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                if let e = lastError {
                    Text("Error: \(e)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 8)
            }
            .padding()
            .navigationTitle("Meta (Voice)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(speech.isRecording)
                }
            }
            .onAppear { speech.requestAuth() }
            .onDisappear { if speech.isRecording { speech.stop() } }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "-" : value).font(.headline)
        }
    }

    /// Stop → 認識テキストを transcript に追記
    private func stopRecordingAndAppend() {
        speech.stop()
        let t = speech.takeFinalText()
        if !t.isEmpty {
            if transcript.isEmpty { transcript = t }
            else { transcript += "\n" + t }
        }
    }

    /// transcript から簡易に各メタ項目を抽出して vm.meta に反映
    private func applyTranscriptToMeta() {
        let text = transcript
            .replacingOccurrences(of: "：", with: ":") // 全角コロン対策
            .replacingOccurrences(of: "　", with: " ")
            .lowercased()

        func find(_ keys: [String]) -> String? {
            for k in keys {
                if let r = text.range(of: "\(k)[:\\s]+([^\\n]+)", options: .regularExpression) {
                    let line = String(text[r])
                    if let m = line.range(of: "[:\\s]+([^\\n]+)", options: .regularExpression) {
                        let val = line[m]
                        return String(val)
                            .replacingOccurrences(of: ":", with: "")
                            .trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            return nil
        }

        // よく言いがちな言い回しを複数キーで吸収（日本語＋英語）
        let track = find(["track", "コース", "トラック", "サーキット"])
        let car = find(["car", "車", "車種", "クルマ"])
        let driver = find(["driver", "ドライバー", "運転手"])
        let tyre = find(["tyre", "タイヤ", "タイア", "タイヤ種"])
        let lap = find(["lap", "ラップ"])
        let time = find(["time", "時刻", "タイム"])
        let checker = find(["checker", "チェッカー", "担当", "記録者", "計測者"])
        let date = find(["date", "日付", "日にち"])

        // 反映（空でなければ上書き）
        if let v = track, !v.isEmpty { vm.meta.track = v }
        if let v = car, !v.isEmpty { vm.meta.car = v }
        if let v = driver, !v.isEmpty { vm.meta.driver = v }
        if let v = tyre, !v.isEmpty { vm.meta.tyre = v }
        if let v = lap, !v.isEmpty { vm.meta.lap = v }
        if let v = time, !v.isEmpty { vm.meta.time = v }
        if let v = checker, !v.isEmpty { vm.meta.checker = v }
        if let v = date, !v.isEmpty { vm.meta.date = v }
    }
}
