//
//  SpeechMemoManager.swift
//  PitTemp
//
//  役割: 短い音声を録音→Appleのオンデバイス音声認識で文字起こし
//  初心者向けメモ:
//   - iOSの音声認識は SFSpeechRecognizer / AVAudioEngine を組み合わせて使います
//   - 新しい録音開始時に前の録音を自動 stop（現場向けの操作性）
//

import Foundation
import AVFoundation
import Speech

protocol SpeechMemoManagerDelegate: AnyObject {
    func speechMemoManagerDidStartRecording(_ manager: SpeechMemoManager, wheel: WheelPos)
    func speechMemoManager(_ manager: SpeechMemoManager, didFinishRecording telemetry: SpeechMemoManager.RecognitionTelemetry, wheel: WheelPos?)
    func speechMemoManager(_ manager: SpeechMemoManager, didFailWith error: SpeechMemoManager.RecordingError, telemetry: SpeechMemoManager.RecognitionTelemetry?, wheel: WheelPos?)
}

final class SpeechMemoManager: NSObject, ObservableObject {
    struct RecognitionTelemetry {
        struct Segment: Identifiable {
            let id = UUID()
            let index: Int
            let text: String
            let timestamp: TimeInterval
            let duration: TimeInterval
            let confidence: Double
        }

        let transcript: String
        let segments: [Segment]

        var averageConfidence: Double? {
            guard !segments.isEmpty else { return nil }
            let total = segments.reduce(0.0) { $0 + $1.confidence }
            return total / Double(segments.count)
        }
    }

    enum RecordingError: LocalizedError {
        case permissionDenied
        case recognizerUnavailable
        case microphoneUnavailable
        case audioSession(error: Error)
        case engine(error: Error)
        case recognition(error: Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "マイク／音声認識の権限が許可されていません。設定アプリで PitTemp のマイク・音声認識を有効にしてください。"
            case .recognizerUnavailable:
                return "音声認識サービスを利用できません（オフライン状態やシステム制限の可能性があります）。"
            case .microphoneUnavailable:
                return "マイク入力が利用できません。シミュレータの場合は録音ができないため、ログCSVの共有で結果を確認してください。"
            case .audioSession(let error):
                return "オーディオセッションの初期化に失敗しました: \(error.localizedDescription)"
            case .engine(let error):
                return "録音エンジンの起動に失敗しました: \(error.localizedDescription)"
            case .recognition(let error):
                return "音声認識の処理中にエラーが発生しました: \(error.localizedDescription)"
            }
        }
    }

    @Published var isAuthorized = false
    @Published var isRecording = false
    @Published var currentWheel: WheelPos? = nil

    weak var delegate: SpeechMemoManagerDelegate?

    private var audioEngine = AVAudioEngine()
    private var request = SFSpeechAudioBufferRecognitionRequest()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))!
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""
    private var latestSegments: [RecognitionTelemetry.Segment] = []
    private var hasNotifiedCompletion = false
    private var tapInstalled = false
    private var didRequestRecordPermission = false

    private var hasSpeechAuthorization = false {
        didSet { updateAuthorizationState() }
    }
    private var hasMicrophonePermission = false {
        didSet { updateAuthorizationState() }
    }

    func requestAuth() {
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async { self.hasSpeechAuthorization = (st == .authorized) }
        }

        if #available(iOS 17.0, *) {
            let application = AVAudioApplication.shared
            switch application.recordPermission {
            case .granted:
                DispatchQueue.main.async { self.hasMicrophonePermission = true }
            case .denied:
                DispatchQueue.main.async { self.hasMicrophonePermission = false }
            case .undetermined:
                if !didRequestRecordPermission {
                    didRequestRecordPermission = true
                    application.requestRecordPermission { granted in
                        DispatchQueue.main.async { self.hasMicrophonePermission = granted }
                    }
                }
            @unknown default:
                DispatchQueue.main.async { self.hasMicrophonePermission = false }
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted:
                DispatchQueue.main.async { self.hasMicrophonePermission = true }
            case .denied:
                DispatchQueue.main.async { self.hasMicrophonePermission = false }
            case .undetermined:
                if !didRequestRecordPermission {
                    didRequestRecordPermission = true
                    session.requestRecordPermission { granted in
                        DispatchQueue.main.async { self.hasMicrophonePermission = granted }
                    }
                }
            @unknown default:
                DispatchQueue.main.async { self.hasMicrophonePermission = false }
            }
        }
    }

    func resetAudioSessionState() throws {
        task?.cancel()
        task = nil
        request.endAudio()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.stop()
        audioEngine.reset()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            throw RecordingError.audioSession(error: error)
        }
    }

    func start(for wheel: WheelPos) throws {
        guard isAuthorized else {
            let error = RecordingError.permissionDenied
            notifyFailure(error, telemetry: nil, wheel: wheel)
            throw error
        }
        guard recognizer.isAvailable else {
            let error = RecordingError.recognizerUnavailable
            notifyFailure(error, telemetry: nil, wheel: wheel)
            throw error
        }

        do {
            try resetAudioSessionState()
        } catch let error as RecordingError {
            notifyFailure(error, telemetry: nil, wheel: wheel)
            throw error
        }

        currentWheel = wheel
        transcript = ""
        latestSegments = []
        hasNotifiedCompletion = false

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            let wrapped = RecordingError.audioSession(error: error)
            notifyFailure(wrapped, telemetry: nil, wheel: currentWheel)
            throw wrapped
        }

        guard session.isInputAvailable else {
            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                let wrapped = RecordingError.audioSession(error: error)
                notifyFailure(wrapped, telemetry: nil, wheel: currentWheel)
                throw wrapped
            }
            let error = RecordingError.microphoneUnavailable
            notifyFailure(error, telemetry: nil, wheel: currentWheel)
            throw error
        }

        let input = audioEngine.inputNode
        request = SFSpeechAudioBufferRecognitionRequest()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let best = result.bestTranscription
                self.transcript = best.formattedString
                self.latestSegments = best.segments.enumerated().map { idx, seg in
                    RecognitionTelemetry.Segment(
                        index: idx,
                        text: seg.substring,
                        timestamp: seg.timestamp,
                        duration: seg.duration,
                        confidence: Double(seg.confidence)
                    )
                }
                if result.isFinal {
                    self.stop()
                }
            }

            if let error {
                let wrapped = RecordingError.recognition(error: error)
                self.stop(with: wrapped)
            }
        }

        let fmt = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.request.append(buf)
        }
        tapInstalled = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            tapInstalled = false
            let wrapped = RecordingError.engine(error: error)
            stop(with: wrapped)
            throw wrapped
        }

        DispatchQueue.main.async {
            self.isRecording = true
            self.delegate?.speechMemoManagerDidStartRecording(self, wheel: wheel)
        }
    }

    func stop() {
        stop(with: nil)
    }

    private func stop(with error: RecordingError?) {
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request.endAudio()
        task?.cancel()
        task = nil

        DispatchQueue.main.async { self.isRecording = false }

        notifyCompletionIfNeeded(error: error)
    }

    func takeFinalText() -> String {
        let t = transcript
        transcript = ""
        currentWheel = nil
        return t
    }

    // 前の録音を止めて Wheel とテキストを返す
    func stopAndTakeText() -> (WheelPos?, String) {
        if isRecording {
            stop()
            let w = currentWheel
            let t = takeFinalText()
            return (w, t)
        } else {
            return (nil, "")
        }
    }

    private func notifyCompletionIfNeeded(error: RecordingError?) {
        guard !hasNotifiedCompletion else { return }
        hasNotifiedCompletion = true

        let telemetry = RecognitionTelemetry(transcript: transcript, segments: latestSegments)
        let wheel = currentWheel

        if let error {
            notifyFailure(error, telemetry: telemetry, wheel: wheel)
        } else {
            DispatchQueue.main.async {
                self.delegate?.speechMemoManager(self, didFinishRecording: telemetry, wheel: wheel)
            }
        }
    }

    private func notifyFailure(_ error: RecordingError, telemetry: RecognitionTelemetry?, wheel: WheelPos?) {
        DispatchQueue.main.async {
            self.delegate?.speechMemoManager(self, didFailWith: error, telemetry: telemetry, wheel: wheel)
        }
    }

    private func updateAuthorizationState() {
        let combined = hasSpeechAuthorization && hasMicrophonePermission
        if combined != isAuthorized {
            isAuthorized = combined
        }
    }
}
