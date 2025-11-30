import Foundation
import CoreBluetooth

/// Anritsu T1245 系の処理を切り出したデバイスクラス。
/// - Important: 既存の ASCII 通知ベースの実装を保持しつつ、マルチベンダー向けに ThermometerDevice に準拠。
final class AnritsuDevice: ThermometerDevice {
    let profile: BLEDeviceProfile = .anritsu
    weak var peripheral: CBPeripheral?
    var onFrame: ((TemperatureFrame) -> Void)?
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?

    private var readChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?
    private let notifyController: NotifyController

    init(ingestor: TemperatureIngesting) {
        // 既存の NotifyController を再利用して ASCII/既存 TR4A パケットをドメインへ橋渡しする。
        notifyController = NotifyController(ingestor: ingestor) { [weak self] frame in
            self?.onFrame?(frame)
        }
    }

    // MARK: ThermometerDevice
    func connect(using central: CBCentralManager, to peripheral: CBPeripheral) {
        Logger.shared.log("Connecting to Anritsu device", category: .ui)
        self.peripheral = peripheral
        peripheral.discoverServices([profile.serviceUUID])
    }

    func startMeasurement() {
        // Anritsu は Notify で現在値をプッシュするため特別なポーリングは不要。
    }

    /// 時刻同期は Anritsu の Write キャラクタリスティック経由で送る。
    func sendTimeSync(_ data: Data) {
        guard let peripheral, let writeChar else { return }
        Logger.shared.log("Anritsu TX time → \(data.hexEncodedString())", category: .bleTx)
        peripheral.writeValue(data, for: writeChar, type: .withResponse)
    }

    func disconnect(using central: CBCentralManager?) {
        Logger.shared.log("Disconnecting Anritsu device", category: .ui)
        readChar = nil
        writeChar = nil
        peripheral = nil
    }

    func didDiscoverServices(peripheral: CBPeripheral, error: Error?) {
        if let e = error {
            onError?("Service discovery failed: \(e.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == profile.serviceUUID }) else {
            return
        }
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
        Logger.shared.log("Anritsu RX ← \(data.hexEncodedString())", category: .bleRx)
        notifyController.handleNotification(data)
    }

    func didWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            onError?("Write failed: \(e.localizedDescription)")
        }
    }
}
