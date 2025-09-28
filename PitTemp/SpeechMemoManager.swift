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

final class SpeechMemoManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var isRecording = false
    @Published var currentWheel: WheelPos? = nil

    private var audioEngine = AVAudioEngine()
    private var request = SFSpeechAudioBufferRecognitionRequest()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))!
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""

    func requestAuth() {
        SFSpeechRecognizer.requestAuthorization { st in
            DispatchQueue.main.async { self.isAuthorized = (st == .authorized) }
        }
    }

    func start(for wheel: WheelPos) throws {
        if isRecording { stop() } // ★次開始時に自動Stop
        currentWheel = wheel
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        request = SFSpeechAudioBufferRecognitionRequest()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let t = result?.bestTranscription.formattedString { self.transcript = t }
            if result?.isFinal == true || error != nil { self.stop() }
        }

        let fmt = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.request.append(buf)
        }
        audioEngine.prepare()
        try audioEngine.start()
        DispatchQueue.main.async { self.isRecording = true }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request.endAudio()
        task?.cancel()
        DispatchQueue.main.async { self.isRecording = false }
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
}
