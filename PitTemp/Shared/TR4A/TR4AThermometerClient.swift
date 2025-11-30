import CoreBluetooth
import Foundation

/// TR45 へのコマンド送信と応答処理を担当する専用クライアント。
/// - Important: "BLE 接続" と "SOH プロトコル" の責務を分離し、BluetoothService から再利用できるようにする。
final class TR4AThermometerClient {
    /// UI へ状態を伝えるためのイベントコールバック群。
    struct EventHandlers {
        var onTemperature: ((TemperatureFrame) -> Void)?
        var onStateUpdate: ((TR4ADeviceState) -> Void)?
        var onLog: ((String) -> Void)?
        var onSecurityNeeded: (() -> Void)?
        var onError: ((String) -> Void)?
    }

    private let peripheral: CBPeripheral
    private let notifyCharacteristic: CBCharacteristic
    private let writeCharacteristic: CBCharacteristic
    private let assembler = TR4AAssembler()
    private let registrationStore: RegistrationCodeStoring
    private var state = TR4ADeviceState()
    private var sequence: UInt8 = 0
    private var pollTimer: DispatchSourceTimer?
    private var securityUnlocked = false
    private var pendingPasscode: String?
    private var handlers = EventHandlers()

    init(peripheral: CBPeripheral,
         notifyCharacteristic: CBCharacteristic,
         writeCharacteristic: CBCharacteristic,
         registrationStore: RegistrationCodeStoring) {
        self.peripheral = peripheral
        self.notifyCharacteristic = notifyCharacteristic
        self.writeCharacteristic = writeCharacteristic
        self.registrationStore = registrationStore
    }

    deinit { stopPolling() }

    /// コールバックを設定する（メソッドチェーンしやすいよう戻り値を self に）。
    @discardableResult
    func configure(handlers: EventHandlers) -> TR4AThermometerClient {
        self.handlers = handlers
        return self
    }

    /// 初期化時に呼び出し、Notify を有効化して現在値取得を開始する。
    func start() {
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
        log("Notify enabled for \(notifyCharacteristic.uuid.uuidString)")
        requestCurrentValue()
    }

    /// 外部から通知データを渡すエントリポイント。Assembler 経由で完全フレームにしてから処理する。
    func handleNotification(_ data: Data) {
        for frame in assembler.append(data) {
            handle(frame: frame)
        }
    }

    /// 現在値を 1 秒周期で取得するポーリングを開始。
    func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "tr4a.poll"))
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.requestCurrentValue() }
        timer.resume()
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// 登録コードを UI から保存するための窓口を提供。
    func saveRegistrationCode(_ code: String) {
        registrationStore.save(code: code, for: peripheral.identifier.uuidString)
        pendingPasscode = code
    }

    // MARK: - Frame handlers

    private func handle(frame: TR4AProtocol.Frame) {
        switch frame.command {
        case .getCurrentValue:
            parseCurrentValue(frame)
        case .readRecordingSetting:
            parseRecordingSettings(frame)
        case .writeRecordingSetting:
            // 書き込み応答でもステータスを UI に伝えるため、読み直しをかける。
            if frame.status.isAck { requestRecordingSettings() }
        case .startRecording, .stopRecording:
            if frame.status.isAck { requestRecordingSettings() }
        case .passcode:
            handlePasscodeResponse(frame)
        }
    }

    /// 0x33 の応答から温度と状態ビットを抽出。
    private func parseCurrentValue(_ frame: TR4AProtocol.Frame) {
        guard frame.status.isAck else {
            if case .refuse(let reason) = frame.status.kind, reason == .securityLocked {
                handlers.onSecurityNeeded?()
                log("Security locked → waiting for passcode")
                if let code = registrationStore.code(for: peripheral.identifier.uuidString) {
                    sendPasscode(code)
                }
            }
            return
        }
        guard frame.payload.count >= 7 else { return }
        // payload[0]=status, [1]=Type, [2]=CH数, [3..4]=温度LE (0.01℃)
        let raw = Int16(bitPattern: UInt16(frame.payload[3]) | (UInt16(frame.payload[4]) << 8))
        let temperature = Double(raw) / 100.0
        let channel = Int(frame.payload[2])
        let recordingState = frame.payload[5]
        let securityState = frame.payload.count > 6 ? (frame.payload[6] & 0x01 == 0x01) : false

        let frameModel = TemperatureFrame(time: Date(),
                                          deviceID: channel,
                                          value: temperature,
                                          status: nil)
        state.isRecording = (recordingState & 0x01) == 0x01
        state.securityEnabled = securityState
        handlers.onStateUpdate?(state)
        handlers.onTemperature?(frameModel)
        if !securityUnlocked && securityState { handlers.onSecurityNeeded?() }
    }

    /// 設定取得（0x30系）の応答をデコードし、UI へまとめて渡す。
    private func parseRecordingSettings(_ frame: TR4AProtocol.Frame) {
        guard frame.status.isAck else { return }
        // payload 例: [status, interval(sec), mode, security]
        guard frame.payload.count >= 4 else { return }
        state.loggingIntervalSec = Int(frame.payload[1])
        state.recordingModeEndless = frame.payload[2] == 0x00
        state.securityEnabled = frame.payload[3] == 0x01
        handlers.onStateUpdate?(state)
    }

    private func handlePasscodeResponse(_ frame: TR4AProtocol.Frame) {
        if frame.status.isAck {
            securityUnlocked = true
            log("Passcode accepted → resume polling")
            startPolling()
        } else {
            handlers.onError?("Passcode rejected (status: \(frame.status.raw))")
        }
    }

    // MARK: - Command senders

    private func requestCurrentValue() {
        let payload = Data([0x00]) // status placeholder (ACK 用)
        send(command: .getCurrentValue, payload: payload)
    }

    func requestRecordingSettings() {
        send(command: .readRecordingSetting, payload: Data([0x00]))
    }

    func updateRecording(interval: UInt8, endless: Bool) {
        let mode: UInt8 = endless ? 0x00 : 0x01
        let payload = Data([0x00, interval, mode])
        send(command: .writeRecordingSetting, payload: payload)
    }

    func startRecording() { send(command: .startRecording, payload: Data([0x00])) }
    func stopRecording() { send(command: .stopRecording, payload: Data([0x00])) }

    func sendPasscode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bcd = RegistrationCodeStore.bcdBytes(from: trimmed) else {
            handlers.onError?("Invalid registration code")
            return
        }
        var payload = Data([0x00])
        payload.append(contentsOf: bcd)
        pendingPasscode = code
        send(command: .passcode, payload: payload)
    }

    private func send(command: TR4ACommand, payload: Data) {
        var framedPayload = Data()
        framedPayload.append(payload)
        let frame = TR4AProtocol.encode(command: command, sequence: sequence, payload: framedPayload)
        sequence &+= 1
        log("TX \(command) seq=\(sequence) bytes=\(frame as NSData)")
        peripheral.writeValue(frame, for: writeCharacteristic, type: .withoutResponse)
    }

    private func log(_ message: String) {
        handlers.onLog?("[TR4A] \(message)")
    }
}
