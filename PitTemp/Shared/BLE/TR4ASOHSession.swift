//  TR4ASOHSession.swift
//  PitTemp
//
//  TR45/TR4A 系 SOH コマンドをまとめて扱うための小さなセッション管理クラス。
//  - 送信: 0x00 のブレークを挟みつつ SOH フレームをCRC付きで組み立てる
//  - 受信: Notifyで届く分割パケットをバッファに積み、CRC検証したうえで1フレームに復元
//  - 認証: 0x68がREFUSEなら0x76で登録コード認証→再度0x68で現在値を読む
//  教育的メモ: 「CRCはSOH〜データ末尾を対象にCCITT(0x1021)で計算し、ビッグエンディアンで格納する」

import Foundation
import CoreBluetooth

/// TR4A/TR45 の SOH フレームを表現。
struct TR4ASOHFrame {
    let command: UInt8
    let status: UInt8
    let payload: Data
}

/// TR45 サポート用のセッションコントローラ。
final class TR4ASOHSession {
    enum Status: Equatable {
        case idle
        case awaitingAuth
        case authenticated
        case refused
    }

    private weak var peripheral: CBPeripheral?
    private let writeChar: CBCharacteristic
    private weak var registry: DeviceRegistrying?
    private let logger: UILogPublishing?
    private let deviceID: String
    private let onTemperature: (TemperatureFrame) -> Void

    private var buffer = Data()
    private var pollTimer: DispatchSourceTimer?
    private var state: Status = .idle
    private var lastAuthAttempt: Date?

    init(peripheral: CBPeripheral,
         write: CBCharacteristic,
         registry: DeviceRegistrying?,
         deviceID: String,
         logger: UILogPublishing?,
         onTemperature: @escaping (TemperatureFrame) -> Void) {
        self.peripheral = peripheral
        self.writeChar = write
        self.registry = registry
        self.deviceID = deviceID
        self.logger = logger
        self.onTemperature = onTemperature
    }

    // MARK: - Lifecycle
    func start() {
        log("TR45 session start")
        sendSettingRequest()
        startPolling()
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        buffer.removeAll()
    }

    // MARK: - Notify handling
    func handleNotification(_ data: Data) {
        // TR45 support: Notifyは20B分割なのでバッファに積んでからパースする。
        buffer.append(data)
        parseFrames()
    }

    private func parseFrames() {
        // 簡易ステートマシン: SOH(0x01) を探し、長さが揃うまで待つ。
        while buffer.count >= 7 { // 最小: SOH+CMD+STATUS+LEN(2)+CRC(2)
            guard let sohIndex = buffer.firstIndex(of: 0x01) else {
                buffer.removeAll()
                return
            }
            if sohIndex > 0 { buffer.removeFirst(sohIndex) }
            guard buffer.count >= 5 else { return }
            let length = Int(buffer[3]) | (Int(buffer[4]) << 8)
            let total = 5 + length + 2
            guard buffer.count >= total else { return }
            let candidate = buffer.prefix(total)
            let crcRemote = (UInt16(candidate[total - 2]) << 8) | UInt16(candidate[total - 1])
            let crcLocal = crc16CCITT(candidate.dropLast(2))
            if crcLocal != crcRemote {
                log("CRC error cmd=0x\(String(format: "%02X", candidate[1])) local=\(crcLocal) remote=\(crcRemote)")
                buffer.removeFirst(total)
                continue
            }
            let payload = candidate[5..<(5 + length)]
            let frame = TR4ASOHFrame(command: candidate[1], status: candidate[2], payload: Data(payload))
            buffer.removeFirst(total)
            handle(frame: frame)
        }
    }

    // MARK: - Frame handlers
    private func handle(frame: TR4ASOHFrame) {
        log("RX cmd=0x\(String(format: "%02X", frame.command)) status=0x\(String(format: "%02X", frame.status)) payload=\(frame.payload.hexEncodedString())")
        switch frame.command {
        case 0x68:
            handleSettingFrame(frame)
        case 0x33:
            handleCurrentValueFrame(frame)
        case 0x76:
            handleAuthFrame(frame)
        default:
            break
        }
    }

    /// FORMAT=5 を想定した設定読み出し応答。
    private func handleSettingFrame(_ frame: TR4ASOHFrame) {
        if frame.status == 0x0F {
            // セキュリティONで拒否された → 登録コードを送って再試行
            attemptAuthIfPossible(reason: "0x68 REFUSE")
            return
        }
        guard frame.status == 0x06 else { return }
        guard frame.payload.count >= 30 else { return }
        let ch1Raw = Int16(bitPattern: UInt16(frame.payload[18]) | (UInt16(frame.payload[19]) << 8))
        let ch2Raw = Int16(bitPattern: UInt16(frame.payload[28]) | (UInt16(frame.payload[29]) << 8))
        publishTemperature(raw: ch1Raw, channel: 1)
        publishTemperature(raw: ch2Raw, channel: 2)
        state = .authenticated
    }

    /// 0x33 現在値取得の応答(4Bデータ)
    private func handleCurrentValueFrame(_ frame: TR4ASOHFrame) {
        guard frame.status == 0x06 else { return }
        guard frame.payload.count >= 4 else { return }
        let ch1Raw = Int16(bitPattern: UInt16(frame.payload[0]) | (UInt16(frame.payload[1]) << 8))
        let ch2Raw = Int16(bitPattern: UInt16(frame.payload[2]) | (UInt16(frame.payload[3]) << 8))
        publishTemperature(raw: ch1Raw, channel: 1)
        publishTemperature(raw: ch2Raw, channel: 2)
    }

    private func handleAuthFrame(_ frame: TR4ASOHFrame) {
        if frame.status == 0x06 {
            state = .authenticated
            log("0x76 authenticated")
            sendSettingRequest()
        } else {
            state = .refused
            log("0x76 refused: check register code")
        }
    }

    // MARK: - Temperature publishing
    private func publishTemperature(raw: Int16, channel: Int) {
        guard raw != Int16(bitPattern: 0xEEEE) && raw != Int16(bitPattern: 0xF000) else { return }
        let value = (Double(raw) - 1000.0) / 10.0
        let frame = TemperatureFrame(time: Date(), deviceID: channel, value: value, status: nil)
        onTemperature(frame)
    }

    // MARK: - Commands
    func sendSettingRequest() {
        var payload = Data([0x05, 0x00]) // FORMAT=5
        send(command: 0x68, subcommand: 0x00, payload: &payload)
    }

    func sendCurrentValueRequest() {
        var payload = Data([0x00, 0x00, 0x00, 0x00])
        send(command: 0x33, subcommand: 0x00, payload: &payload)
    }

    private func attemptAuthIfPossible(reason: String) {
        guard state != .awaitingAuth else { return }
        state = .awaitingAuth
        log("TR45 auth required: \(reason)")
        guard let registry, let record = registry.record(for: deviceID), let code = record.registerCode, code.count == 8 else {
            log("No register code stored for device; skipping 0x76")
            state = .refused
            return
        }
        guard lastAuthAttempt == nil || Date().timeIntervalSince(lastAuthAttempt ?? .distantPast) > 2 else { return }
        lastAuthAttempt = Date()
        let serial = record.serialNumber ?? "(unknown serial)"
        log("Sending 0x76 for serial \(serial)")
        var codeValue: UInt32 = UInt32(code) ?? 0
        var payload = Data()
        withUnsafeBytes(of: &codeValue.littleEndian) { payload.append(contentsOf: $0) }
        send(command: 0x76, subcommand: 0x00, payload: &payload)
    }

    private func startPolling() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "TR4A.soh.poll"))
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            switch self.state {
            case .authenticated:
                self.sendCurrentValueRequest()
            case .awaitingAuth, .refused:
                break
            case .idle:
                self.sendSettingRequest()
            }
        }
        timer.resume()
        pollTimer = timer
    }

    // MARK: - Frame builder
    private func send(command: UInt8, subcommand: UInt8, payload: inout Data) {
        guard let peripheral = peripheral else { return }
        var frame = Data([0x01, command, subcommand, UInt8(payload.count & 0xFF), UInt8((payload.count >> 8) & 0xFF)])
        frame.append(payload)
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        let breakByte = Data([0x00])
        log("TX cmd=0x\(String(format: "%02X", command)) payload=\(payload.hexEncodedString())")
        peripheral.writeValue(breakByte, for: writeChar, type: .withResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) {
            peripheral.writeValue(frame, for: self.writeChar, type: .withResponse)
        }
    }

    private func crc16CCITT(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }

    private func log(_ message: String) {
        logger?.publish(UILogEntry(message: "[BLE] " + message, level: .info, category: .ble))
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02X", $0) }.joined()
    }
}
