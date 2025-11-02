//
//  MetaVoiceEditorView.swift
//  PitTemp
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

private enum MetaField: String, CaseIterable, Identifiable {
    case track, date, time, car, driver, tyre, lap, checker
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .track: return "Track"
        case .date: return "Date"
        case .time: return "Time"
        case .car: return "Car"
        case .driver: return "Driver"
        case .tyre: return "Tyre"
        case .lap: return "Lap"
        case .checker: return "Checker"
        }
    }
}

private struct VoiceAttempt: Identifiable {
    struct Segment: Identifiable {
        let id = UUID()
        let index: Int
        let text: String
        let timestamp: TimeInterval
        let duration: TimeInterval
        let confidence: Double
    }

    struct KeywordHit: Identifiable {
        let id = UUID()
        let field: MetaField
        let keyword: String
    }

    let id = UUID()
    let timestamp: Date
    let transcript: String
    let matched: [MetaField: String]
    let missing: [MetaField]
    let keywordHits: [KeywordHit]
    let score: Double
    let averageConfidence: Double?
    let wheel: WheelPos?
    let errorDescription: String?
    let segments: [Segment]
}

private struct AttemptCSVDocument: Transferable {
    let attempts: [VoiceAttempt]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { value in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(Self.filenameFormatter.string(from: Date()))
                .appendingPathExtension("csv")
            try value.makeCSV().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    private static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "'MetaVoiceAttempts-'yyyyMMdd-HHmmss"
        return f
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func escapeCSV(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") {
            escaped = "\"" + escaped + "\""
        }
        return escaped
    }

    private func row(for attempt: VoiceAttempt) -> String {
        let timestamp = Self.timestampFormatter.string(from: attempt.timestamp)
        let wheel = attempt.wheel?.rawValue ?? ""
        let matched = attempt.matched
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: "; ")
        let missing = attempt.missing.map(\.rawValue).joined(separator: "; ")
        let keywords = attempt.keywordHits
            .map { "\($0.field.rawValue):\($0.keyword)" }
            .joined(separator: "; ")
        let score = String(format: "%.2f", attempt.score)
        let confidence = attempt.averageConfidence.map { String(format: "%.2f", $0) } ?? ""
        let error = attempt.errorDescription ?? ""

        let columns = [
            timestamp,
            wheel,
            attempt.transcript,
            matched,
            missing,
            keywords,
            score,
            confidence,
            error
        ].map(escapeCSV)

        return columns.joined(separator: ",")
    }

    private func makeCSV() -> String {
        let header = [
            "timestamp",
            "wheel",
            "transcript",
            "matched",
            "missing",
            "keywords",
            "score",
            "average_confidence",
            "error"
        ].joined(separator: ",")

        let rows = attempts.map(row)
        return ([header] + rows).joined(separator: "\n")
    }
}

private final class SpeechMemoEventHub: ObservableObject, SpeechMemoManagerDelegate {
    struct StartEvent: Identifiable {
        let id = UUID()
        let wheel: WheelPos
    }
    struct RecognitionEvent: Identifiable {
        let id = UUID()
        let wheel: WheelPos?
        let telemetry: SpeechMemoManager.RecognitionTelemetry
    }

    struct ErrorEvent: Identifiable {
        let id = UUID()
        let wheel: WheelPos?
        let error: SpeechMemoManager.RecordingError
        let telemetry: SpeechMemoManager.RecognitionTelemetry?
    }

    @Published var startEvent: StartEvent?
    @Published var recognitionEvent: RecognitionEvent?
    @Published var errorEvent: ErrorEvent?

    func speechMemoManagerDidStartRecording(_ manager: SpeechMemoManager, wheel: WheelPos) {
        DispatchQueue.main.async {
            self.startEvent = StartEvent(wheel: wheel)
        }
    }

    func speechMemoManager(_ manager: SpeechMemoManager, didFinishRecording telemetry: SpeechMemoManager.RecognitionTelemetry, wheel: WheelPos?) {
        DispatchQueue.main.async {
            self.recognitionEvent = RecognitionEvent(wheel: wheel, telemetry: telemetry)
        }
    }

    func speechMemoManager(_ manager: SpeechMemoManager, didFailWith error: SpeechMemoManager.RecordingError, telemetry: SpeechMemoManager.RecognitionTelemetry?, wheel: WheelPos?) {
        DispatchQueue.main.async {
            self.errorEvent = ErrorEvent(wheel: wheel, error: error, telemetry: telemetry)
        }
    }
}

private struct ParseArtifacts {
    let matched: [MetaField: String]
    let missing: [MetaField]
    let keywordHits: [VoiceAttempt.KeywordHit]
    let score: Double
    let debugMap: [String: String]
    let message: String?
}

/// 既存の SpeechMemoManager を使って音声 → テキスト化し、
/// そのテキストから各メタ項目(Track/Car/Driver/…）を抽出・反映する簡易エディタ。
struct MetaVoiceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: SessionViewModel

    @StateObject private var speech = SpeechMemoManager()
    @StateObject private var speechEvents = SpeechMemoEventHub()

    @State private var transcript: String = ""
    @State private var lastError: String?
    @State private var debugParsed: [String:String] = [:]
    @State private var attempts: [VoiceAttempt] = []
    @State private var microphoneAvailable = true

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
                            stopRecording()
                        } label: {
                            Label("Stop", systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            // SpeechMemoManager.start(for:) が WheelPos 必須のため
                            // メタ入力ではダミーで .FL を渡して録音のみ利用する
                            do {
                                lastError = nil
                                try speech.start(for: .FL)
                            } catch let error as SpeechMemoManager.RecordingError {
                                lastError = error.errorDescription
                                if case .microphoneUnavailable = error {
                                    microphoneAvailable = false
                                }
                            } catch {
                                lastError = error.localizedDescription
                            }
                        } label: {
                            Label("Start", systemImage: "mic.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!speech.isAuthorized || !microphoneAvailable)
                    }
                }

                if !microphoneAvailable {
                    Text("シミュレータやマイク非搭載環境では録音を開始できません。画面下部のCSVエクスポートから解析ログを共有できます。")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.bottom, 4)
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

            keywordGuide

            if !attempts.isEmpty {
                attemptLog
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
            .onReceive(speechEvents.$startEvent) { _ in
                microphoneAvailable = true
                lastError = nil
            }
            .onReceive(speechEvents.$recognitionEvent) { event in
                guard let event else { return }
                handleRecognitionEvent(event)
            }
            .onReceive(speechEvents.$errorEvent) { event in
                guard let event else { return }
                handleErrorEvent(event)
            }
            .onAppear {
                speech.delegate = speechEvents
                speech.requestAuth()
                microphoneAvailable = AVAudioSession.sharedInstance().isInputAvailable
            }
            .onDisappear {
                if speech.isRecording { speech.stop() }
                speech.delegate = nil
            }
        }
    }

    private var keywordGuide: some View {
        let keywords = MetaField.allCases.map { $0.displayName.lowercased() }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 6) {
            Text("ヒント").font(.caption).foregroundStyle(.secondary)
            Text("各項目の前にキーワードを付けて話してください。例: \"track 鈴鹿\", \"driver 佐藤\", \"lap 5\"。")
                .font(.footnote)
            Text("認識するキーワード: \(keywords)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private var attemptLog: some View {
        let recentAttempts = Array(attempts.suffix(5).reversed())
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("解析履歴").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ShareLink(item: AttemptCSVDocument(attempts: attempts)) {
                    Label("CSVエクスポート", systemImage: "square.and.arrow.up")
                }
                .disabled(attempts.isEmpty)
            }
            ForEach(recentAttempts) { attempt in
                attemptRow(attempt)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func attemptRow(_ attempt: VoiceAttempt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(attempt.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let wheel = attempt.wheel {
                    Text("Wheel: \(wheel.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "Score %.0f%%", attempt.score * 100))
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            if let confidence = attempt.averageConfidence {
                Text(String(format: "信頼度(平均): %.0f%%", confidence * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let error = attempt.errorDescription, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Text(attempt.transcript)
                .font(.footnote)
            if !attempt.keywordHits.isEmpty {
                let keywords = attempt.keywordHits.map { "\($0.field.displayName)=\($0.keyword)" }.joined(separator: ", ")
                Text("Keywords: \(keywords)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if !attempt.matched.isEmpty {
                let pairs = attempt.matched.map { "\($0.key.displayName)=\($0.value)" }.sorted().joined(separator: ", ")
                Text("抽出: \(pairs)")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            if !attempt.missing.isEmpty {
                let missing = attempt.missing.map(\.displayName).joined(separator: ", ")
                Text("未抽出: \(missing)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "-" : value).font(.headline)
        }
    }

    /// Stop recording gracefully.
    private func stopRecording() {
        speech.stop()
    }

    /// transcript から簡易に各メタ項目を抽出して vm.meta に反映
    private func applyTranscriptToMeta() {
        let parse = parseTranscript(transcript)

        if let v = parse.matched[.track]   { vm.meta.track   = v }
        if let v = parse.matched[.car]     { vm.meta.car     = v }
        if let v = parse.matched[.driver]  { vm.meta.driver  = v }
        if let v = parse.matched[.tyre]    { vm.meta.tyre    = v }
        if let v = parse.matched[.lap]     { vm.meta.lap     = v }
        if let v = parse.matched[.time]    { vm.meta.time    = v }
        if let v = parse.matched[.checker] { vm.meta.checker = v }
        if let v = parse.matched[.date]    { vm.meta.date    = v }

        lastError = parse.message
        debugParsed = parse.debugMap
    }

    private func parseTranscript(_ rawText: String) -> ParseArtifacts {
        let text = rawText
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "＝", with: "=")
            .replacingOccurrences(of: "‐", with: "-")
            .replacingOccurrences(of: "ー", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = text.lowercased()

        let dict: [(MetaField, [String])] = [
            (.track,  ["track","コース","トラック","サーキット"]),
            (.date,   ["date","日付","日にち"]),
            (.time,   ["time","時刻","タイム"]),
            (.car,    ["car","車","車両","クルマ","ゼッケン","ナンバー","番号"]),
            (.driver, ["driver","ドライバー","運転手","ドライバ"]),
            (.tyre,   ["tyre","タイヤ","タイア","タイヤ種"]),
            (.lap,    ["lap","ラップ","周回"]),
            (.checker,["checker","チェッカー","担当","記録者","計測者"])
        ]

        struct Hit { let field: MetaField; let keyword: String; let range: Range<String.Index> }
        var hits: [Hit] = []

        for (field, keys) in dict {
            for k in keys {
                var start = lower.startIndex
                while start < lower.endIndex,
                      let r = lower.range(of: k, range: start..<lower.endIndex) {
                    hits.append(Hit(field: field, keyword: k, range: r))
                    start = r.upperBound
                }
            }
        }

        guard !hits.isEmpty else {
            print("[MetaVoice] no keys found in transcript")
            let debug = Dictionary(uniqueKeysWithValues: MetaField.allCases.map { ($0.displayName.uppercased(), "") })
            return ParseArtifacts(
                matched: [:],
                missing: MetaField.allCases,
                keywordHits: [],
                score: 0,
                debugMap: debug,
                message: "キーワードが見つかりませんでした。例: \"track 鈴鹿\" \"driver 佐藤\" のように項目名を付けてください。"
            )
        }

        hits.sort { $0.range.lowerBound < $1.range.lowerBound }

        func trimValue(_ s: Substring) -> String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":=：＝-ー→〜〜は、。,."))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed)
        }

        var results: [MetaField: String] = [:]

        for (idx, hit) in hits.enumerated() {
            let valueStart0 = hit.range.upperBound
            var valueStart = valueStart0
            while valueStart < lower.endIndex,
                  [":","=","-","→","は"," "].contains(String(lower[valueStart])) {
                valueStart = lower.index(after: valueStart)
            }

            let valueEnd = (idx + 1 < hits.count) ? hits[idx + 1].range.lowerBound : lower.endIndex
            guard valueStart < valueEnd else { continue }

            let rawSlice = text[valueStart..<valueEnd]
            let value = trimValue(rawSlice)
            if !value.isEmpty {
                results[hit.field] = value
            }
        }

        print("[MetaVoice] parse results:", results.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: " | "))

        let matched = results
        let missing = MetaField.allCases.filter { matched[$0]?.isEmpty ?? true }
        let keywordHits = hits.map { VoiceAttempt.KeywordHit(field: $0.field, keyword: $0.keyword) }
        let debug = Dictionary(uniqueKeysWithValues: MetaField.allCases.map { field in
            (field.displayName.uppercased(), matched[field] ?? "")
        })

        let score = Double(matched.count) / Double(MetaField.allCases.count)

        let message: String?
        if matched.isEmpty {
            message = "値が抽出できませんでした。項目名の直後に値を続けてください。"
        } else if !missing.isEmpty {
            let missingLabel = missing.map(\.displayName).joined(separator: ", ")
            message = "未抽出: \(missingLabel)"
        } else {
            message = nil
        }

        return ParseArtifacts(
            matched: matched,
            missing: missing,
            keywordHits: keywordHits,
            score: score,
            debugMap: debug,
            message: message
        )
    }

    private func appendTranscriptChunk(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        if transcript.isEmpty { transcript = chunk }
        else { transcript += "\n" + chunk }
    }

    private func recordAttempt(transcript chunk: String, telemetry: SpeechMemoManager.RecognitionTelemetry?, wheel: WheelPos?, errorDescription: String?) {
        let parse = parseTranscript(chunk)
        let segments = telemetry?.segments.map { seg in
            VoiceAttempt.Segment(index: seg.index, text: seg.text, timestamp: seg.timestamp, duration: seg.duration, confidence: seg.confidence)
        } ?? []

        let attempt = VoiceAttempt(
            timestamp: Date(),
            transcript: chunk,
            matched: parse.matched,
            missing: parse.missing,
            keywordHits: parse.keywordHits,
            score: parse.score,
            averageConfidence: telemetry?.averageConfidence,
            wheel: wheel,
            errorDescription: errorDescription ?? parse.message,
            segments: segments
        )

        attempts = Array((attempts + [attempt]).suffix(20))
        debugParsed = parse.debugMap
        lastError = errorDescription ?? parse.message
    }

    private func handleRecognitionEvent(_ event: SpeechMemoEventHub.RecognitionEvent) {
        let trimmed = event.telemetry.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            _ = speech.takeFinalText()
            return
        }
        appendTranscriptChunk(trimmed)
        recordAttempt(transcript: trimmed, telemetry: event.telemetry, wheel: event.wheel, errorDescription: nil)
        _ = speech.takeFinalText()
    }

    private func handleErrorEvent(_ event: SpeechMemoEventHub.ErrorEvent) {
        if case .microphoneUnavailable = event.error {
            microphoneAvailable = false
        }
        let partial = event.telemetry?.transcript.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !partial.isEmpty {
            appendTranscriptChunk(partial)
        }
        recordAttempt(transcript: partial, telemetry: event.telemetry, wheel: event.wheel, errorDescription: event.error.errorDescription)
        _ = speech.takeFinalText()
    }
}
