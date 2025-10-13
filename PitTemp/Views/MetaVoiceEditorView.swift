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
    @State private var debugParsed: [String:String] = [:]

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
                
                if !debugParsed.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parsed (debug)").font(.caption).foregroundStyle(.secondary)
                        ForEach(debugParsed.keys.sorted(), id: \.self) { k in
                            HStack { Text(k).frame(width: 80, alignment: .leading).foregroundStyle(.secondary); Text(debugParsed[k] ?? "-") }
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
    /// transcript から各メタ項目を抽出して vm.meta に反映（区切りなしにも強い版）
    private func applyTranscriptToMeta() {
        // 1) 正規化（全角→半角、全角スペース→半角、全角コロン→半角）
        let text = transcript // Variable 'text' was never mutated; consider changing to 'let' constant
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "＝", with: "=")
            .replacingOccurrences(of: "‐", with: "-")
            .replacingOccurrences(of: "ー", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 大文字/小文字の影響がある英字だけ lowercased（日本語はそのままでもOK）
        let lower = text.lowercased()

        // 2) キー語辞書（同義語をまとめて一意キーへ）
        enum Field: String { case track, date, time, car, driver, tyre, lap, checker }
        let dict: [(Field, [String])] = [
            (.track,  ["track","コース","トラック","サーキット"]),
            (.date,   ["date","日付","日にち"]),
            (.time,   ["time","時刻","タイム"]),
            (.car,    ["car","車","車両","クルマ","ゼッケン","ナンバー","番号"]),
            (.driver, ["driver","ドライバー","運転手","ドライバ"]),
            (.tyre,   ["tyre","タイヤ","タイア","タイヤ種"]),
            (.lap,    ["lap","ラップ","周回"]),
            (.checker,["checker","チェッカー","担当","記録者","計測者"])
        ]

        // 3) すべてのキー語のマッチ位置を集める
        struct Hit { let field: Field; let range: Range<String.Index> }
        var hits: [Hit] = []

        for (field, keys) in dict {
            for k in keys {
                var start = lower.startIndex
                while start < lower.endIndex,
                      let r = lower.range(of: k, range: start..<lower.endIndex) {
                    hits.append(Hit(field: field, range: r))
                    start = r.upperBound
                }
            }
        }

        guard !hits.isEmpty else {
            print("[MetaVoice] no keys found in transcript")
            return
        }

        // 4) 先頭位置でソート
        hits.sort { $0.range.lowerBound < $1.range.lowerBound }

        // 5) 各キー語の終端から「次のキー語の始端」までを値として切り出し
        //    「:」「=」「は」「→」などの直後から開始できるようスキップ
        func trimValue(_ s: Substring) -> String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":=：＝-ー→〜〜は、。,."))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed)
        }

        var results: [Field: String] = [:]

        for (idx, hit) in hits.enumerated() {
            let valueStart0 = hit.range.upperBound
            // キーの直後に区切りがあればスキップ
            var valueStart = valueStart0
            while valueStart < lower.endIndex,
                  [":","=","-","→","は"," "].contains(String(lower[valueStart])) {
                valueStart = lower.index(after: valueStart)
            }

            let valueEnd = (idx + 1 < hits.count) ? hits[idx + 1].range.lowerBound : lower.endIndex
            guard valueStart < valueEnd else { continue }

            let rawSlice = text[valueStart..<valueEnd] // 元テキストから切る（大小/日本語保持）
            let value = trimValue(rawSlice)
            if !value.isEmpty {
                // 既に値がある場合は“後勝ち”にする（最後に言ったものを優先）
                results[hit.field] = value
            }
        }

        // 6) デバッグ出力
        print("[MetaVoice] parse results:", results.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: " | "))

        // 7) 反映（空でなければ上書き）
        if let v = results[.track]   { vm.meta.track   = v }
        if let v = results[.car]     { vm.meta.car     = v }
        if let v = results[.driver]  { vm.meta.driver  = v }
        if let v = results[.tyre]    { vm.meta.tyre    = v }
        if let v = results[.lap]     { vm.meta.lap     = v }
        if let v = results[.time]    { vm.meta.time    = v }
        if let v = results[.checker] { vm.meta.checker = v }
        if let v = results[.date]    { vm.meta.date    = v }
        
        self.debugParsed = [
            "TRACK": vm.meta.track,
            "CAR": vm.meta.car,
            "DRIVER": vm.meta.driver,
            "TYRE": vm.meta.tyre,
            "LAP": vm.meta.lap,
            "TIME": vm.meta.time,
            "CHECKER": vm.meta.checker,
            "DATE": vm.meta.date
        ]

    }
}
