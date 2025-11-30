import Foundation
import CoreBluetooth

/// 既存の TR4A (TR41/42/43/44) との通信をまとめたデバイスクラス。
/// - Important: 0x33/0x01 のSOHフレームをブレーク信号付きで送信し、Notifyで受信する既存仕様を保持。
final class TR4ALegacyDevice: ThermometerDevice, TimeSyncCapable {
    let profile: BLEDeviceProfile = .tr4a
    weak var peripheral: CBPeripheral?
    var onFrame: ((TemperatureFrame) -> Void)?
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?

    private var readChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?
    private let notifyController: NotifyController

    init(ingestor: TemperatureIngesting) {
        notifyController = NotifyController(ingestor: ingestor) { [weak self] frame in
            self?.onFrame?(frame)
        }
    }

    func connect(using central: CBCentralManager, to peripheral: CBPeripheral) {
        Logger.shared.log("Connecting to TR4A", category: .ui)
        self.peripheral = peripheral
        peripheral.discoverServices([profile.serviceUUID])
    }

    func startMeasurement() {
        guard let peripheral, let writeChar else { return }
        let cmd = buildTR4ACurrentValueCommand()
        Logger.shared.log("TR4A TX → \(cmd.hexEncodedString())", category: .bleTx)
        peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)
    }

    func disconnect(using central: CBCentralManager?) {
        readChar = nil
        writeChar = nil
        peripheral = nil
    }

    func didDiscoverServices(peripheral: CBPeripheral, error: Error?) {
        if let e = error {
            onError?("Service discovery failed: \(e.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == profile.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([profile.notifyCharUUID, profile.writeCharUUID], for: service)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        if let e = error {
            onError?("Char discovery failed: \(e.localizedDescription)")
            return
        }
        service.characteristics?.forEach { ch in
            if ch.uuid == profile.notifyCharUUID { readChar = ch }
            if ch.uuid == profile.writeCharUUID { writeChar = ch }
        }
        if let rc = readChar { service.peripheral?.setNotifyValue(true, for: rc) }
        onReady?()
    }

    func didUpdateValue(for characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        Logger.shared.log("TR4A RX ← \(data.hexEncodedString())", category: .bleRx)
        notifyController.handleNotification(data)
    }

    func didWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        if let e = error { onError?("Write failed: \(e.localizedDescription)") }
    }

    func sendTimeSync(_ data: Data) {
        guard let peripheral, let writeChar else { return }
        Logger.shared.log("TR4A TX time → \(data.hexEncodedString())", category: .bleTx)
        peripheral.writeValue(data, for: writeChar, type: .withResponse)
    }
}

private extension TR4ALegacyDevice {
    /// TR4A「現在値取得(0x33/0x01)」SOHコマンドフレームを組み立てる。
    /// - Structure: 0x00(ブレーク) + SOH(0x01) + CMD + SUB + DataSize(LE) + CRC16-BE。
    /// - DataSizeは0（ペイロード無し）。CRCはSOH以降をCCITT初期値0xFFFFで計算。
    func buildTR4ACurrentValueCommand() -> Data {
        var frame = Data([0x01, 0x33, 0x01, 0x00, 0x00])
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))

        var packet = Data([0x00])
        packet.append(frame)
        return packet
    }

    /// TR4A仕様書に従い、SOH〜データまでを対象にCRC16-CCITT(0x1021)を計算する。
    func crc16CCITT(_ data: Data) -> UInt16 {
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
}
