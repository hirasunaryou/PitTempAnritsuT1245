//
//  TR4ASession.swift
//  PitTemp
//
//  役割: CoreBluetooth から独立した TR4A セッション管理。Write/Notify のハンドリング、
//        パスコード送信、現在値のポーリング開始/停止を担当する。
//

import Foundation
import CoreBluetooth
import os.log

/// BLE から届いた通知をフレームへ復元し、必要なコマンドを送り返すステートマシン。
final class TR4ASession {
    private weak var peripheral: CBPeripheral?
    private weak var writeCharacteristic: CBCharacteristic?
    private var sequence: UInt8 = 0
    private var buffer = Data()
    private var pollTimer: DispatchSourceTimer?
    private let registrationStore: TR4ARegistrationStoring?
    private let logger: UILogPublishing?
    private let oslog = OSLog(subsystem: "com.pit.temp", category: "BLE-DEBUG")
    private let deviceIdentifier: String?

    var onCurrentValue: ((TR4ACurrentValuePayload) -> Void)?
    var onSnapshot: ((TR4AStatusSnapshot) -> Void)?

    init(peripheral: CBPeripheral?,
         writeCharacteristic: CBCharacteristic?,
         registrationStore: TR4ARegistrationStoring?,
         logger: UILogPublishing?,
         identifier: String?) {
        self.peripheral = peripheral
        self.writeCharacteristic = writeCharacteristic
        self.registrationStore = registrationStore
        self.logger = logger
        self.deviceIdentifier = identifier
    }

    // MARK: - Lifecycle

    func update(peripheral: CBPeripheral?, write: CBCharacteristic?) {
        self.peripheral = peripheral
        self.writeCharacteristic = write
    }

    func invalidate() {
        stopPolling()
        buffer.removeAll()
    }

    // MARK: - Notify handling

    func handleNotification(_ data: Data) {
        buffer.append(data)
        let result = TR4AFrameCodec.decode(buffer: &buffer)
        result.errors.forEach { log("TR4A RX CRC error: \($0)", level: .warning) }

        for frame in result.frames {
            log(String(format: "RX cmd=0x%02X seq=%d len=%d status=%@", frame.command, frame.sequence, frame.length, frame.status.description))
            handle(frame)
        }
    }

    // MARK: - Command entry points

    func requestCurrentValue() {
        send(command: .getCurrentValue)
    }

    func sendPasscodeIfNeeded(for identifier: String) {
        guard let code = registrationStore?.code(for: identifier), let payload = try? TR4ARegistrationCodeConverter.bcdBytes(from: code) else {
            log("No registration code stored for \(identifier)", level: .warning)
            return
        }
        send(command: .passcode, payload: payload)
    }

    func apply(settings: TR4ADeviceSettingsRequest) {
        var payload = Data()
        // 記録間隔: 16bit little endian (sec)
        let interval = UInt16(max(1, min(settings.recordingIntervalSec, 65535)))
        payload.append(UInt8(interval & 0xFF))
        payload.append(UInt8((interval >> 8) & 0xFF))
        // モード
        payload.append(settings.recordingMode.rawValue)
        // セキュリティ
        payload.append(settings.enableSecurity ? 0x01 : 0x00)
        send(command: .setRecordingConditions, payload: payload)

        if let shouldStart = settings.startRecording {
            send(command: shouldStart ? .startRecording : .stopRecording)
        }
    }

    func refreshRecordingConditions() {
        send(command: .getRecordingConditions)
    }

    func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in self?.requestCurrentValue() }
        timer.resume()
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }
}

// MARK: - Private
private extension TR4ASession {
    func nextSequence() -> UInt8 { sequence &+= 1; return sequence }

    func send(command: TR4ACommand, payload: Data = Data()) {
        guard let p = peripheral, let w = writeCharacteristic else {
            log("Cannot send command, missing peripheral/characteristic", level: .error)
            return
        }
        let seq = nextSequence()
        let frame = TR4AFrameCodec.encode(command: command, sequence: seq, payload: payload)
        log("TX \(w.uuid): \(frame.map { String(format: "%02X", $0) }.joined(separator: " "))")
        p.writeValue(frame, for: w, type: .withoutResponse)
    }

    func handle(_ frame: TR4AFrame) {
        guard let command = TR4ACommand(rawValue: frame.command & 0x7F) else { return }

        switch command {
        case .getCurrentValue:
            guard frame.status.isAck, let payload = frame.decodeCurrentValue() else {
                log("Current value refused: \(frame.status.description)", level: .warning)
                if let id = deviceIdentifier {
                    sendPasscodeIfNeeded(for: id)
                }
                var snap = TR4AStatusSnapshot()
                snap.lastError = frame.status.description
                onSnapshot?(snap)
                return
            }
            onCurrentValue?(payload)
            var snap = TR4AStatusSnapshot()
            snap.isRecording = payload.isRecording
            snap.securityOn = payload.isSecurityOn
            snap.stateCode1 = payload.stateCode1
            snap.stateCode2 = payload.stateCode2
            onSnapshot?(snap)

        case .getRecordingConditions:
            if frame.status.isAck {
                let snap = decodeRecordingConditions(frame.payload)
                onSnapshot?(snap)
            } else {
                var snap = TR4AStatusSnapshot()
                snap.lastError = frame.status.description
                onSnapshot?(snap)
            }

        case .passcode:
            if frame.status.isAck {
                log("Passcode accepted", level: .success)
                startPolling()
            } else {
                log("Passcode refused: \(frame.status.description)", level: .error)
            }

        case .setRecordingConditions, .startRecording, .stopRecording, .securitySetting:
            if frame.status.isAck {
                log("Command 0x\(String(format: "%02X", command.rawValue)) ACK", level: .success)
                refreshRecordingConditions()
            } else {
                log("Command 0x\(String(format: "%02X", command.rawValue)) refused: \(frame.status.description)", level: .warning)
            }
        }
    }

    func decodeRecordingConditions(_ payload: Data) -> TR4AStatusSnapshot {
        var snap = TR4AStatusSnapshot()
        guard payload.count >= 5 else { return snap }
        let interval = UInt16(payload[1]) | (UInt16(payload[2]) << 8)
        snap.recordingIntervalSec = Int(interval)
        snap.recordingMode = TR4ARecordingMode(rawValue: payload[3])
        snap.securityOn = payload[4] != 0
        return snap
    }

    func log(_ message: String, level: UILogEntry.Level = .info) {
        os_log("%{public}@", log: oslog, type: .default, message)
        logger?.publish(UILogEntry(message: message, level: level, category: .ble))
    }
}

