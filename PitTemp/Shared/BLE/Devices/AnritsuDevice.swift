import Foundation
import CoreBluetooth

/// Anritsu T1245 専用ロジックをカプセル化した ThermometerDevice 実装。
final class AnritsuDevice: NSObject, ThermometerDevice {
    let profile: BLEDeviceProfile = .anritsu
    let requiresPollingForRealtime: Bool = false

    private let ingestor: TemperatureIngesting
    private var peripheral: CBPeripheral?
    private var notifyChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?

    var onFrame: ((TemperatureFrame) -> Void)?
    var onReady: (() -> Void)?

    init(ingestor: TemperatureIngesting = TemperatureIngestUseCase()) {
        self.ingestor = ingestor
    }

    func bind(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    func connect() {
        // 既存のAnritsu機では特別な初期化は不要。
    }

    func discoverCharacteristics(on peripheral: CBPeripheral, service: CBService) {
        peripheral.discoverCharacteristics([profile.notifyCharUUID, profile.writeCharUUID], for: service)
    }

    func didDiscoverCharacteristics(error: Error?) {
        guard error == nil, let service = peripheral?.services?.first(where: { $0.uuid == profile.serviceUUID }) else { return }
        service.characteristics?.forEach { ch in
            if ch.uuid == profile.notifyCharUUID { notifyChar = ch }
            if ch.uuid == profile.writeCharUUID { writeChar = ch }
        }

        if let notify = notifyChar { peripheral?.setNotifyValue(true, for: notify) }
        onReady?()
    }

    func didUpdateValue(for characteristic: CBCharacteristic, data: Data) {
        guard characteristic.uuid == profile.notifyCharUUID else { return }
        for frame in ingestor.frames(from: data) {
            Logger.shared.log("Anritsu RX ← \(data.hexString)", category: .bleReceive)
            onFrame?(frame)
        }
    }

    func didWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        if let error { Logger.shared.log("Anritsu write error: \(error.localizedDescription)", category: .bleSend) }
    }

    func setDeviceTime(_ date: Date) {
        guard let p = peripheral, let w = writeChar else { return }
        let cmd = ingestor.makeTimeSyncPayload(for: date)
        Logger.shared.log("Anritsu TX → \(cmd.hexString)", category: .bleSend)
        p.writeValue(cmd, for: w, type: .withResponse)
    }

    func startMeasurement() {
        // Anritsu は Notify 自動送信のため特別なポーリングは不要。
    }

    func disconnect() {
        peripheral = nil
        notifyChar = nil
        writeChar = nil
    }
}
