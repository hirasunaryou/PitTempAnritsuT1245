//  AnritsuDevice.swift
//  PitTemp
//  Role: 既存Anritsu T1245向けのBLE接続・通知処理をThermometerDeviceとして分離。

import Foundation
import CoreBluetooth

final class AnritsuDevice: NSObject, ThermometerDevice {
    let profile: BLEDeviceProfile = .anritsu
    weak var peripheral: CBPeripheral?
    var onReady: ((CBPeripheral) -> Void)?
    var onFrame: ((TemperatureFrame) -> Void)?
    var onFailure: ((String) -> Void)?

    private let ingestor: TemperatureIngesting
    private var readChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?

    /// BluetoothService から時刻同期コマンドを流すための窓口。
    var timeSyncWriteCharacteristic: CBCharacteristic? { writeChar }

    init(ingestor: TemperatureIngesting) {
        self.ingestor = ingestor
        super.init()
    }

    func didConnect(_ peripheral: CBPeripheral) {
        Logger.shared.log("Anritsu didConnect: discovering services", category: .system)
        peripheral.discoverServices([profile.serviceUUID])
    }

    func didDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        if let e = error { onFailure?("Service discovery: \(e.localizedDescription)"); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == profile.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([profile.notifyCharUUID, profile.writeCharUUID], for: service)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        if let e = error { onFailure?("Char discovery: \(e.localizedDescription)"); return }
        service.characteristics?.forEach { ch in
            if ch.uuid == profile.notifyCharUUID { readChar = ch }
            if ch.uuid == profile.writeCharUUID { writeChar = ch }
        }
        guard let peripheral = service.peripheral else { return }
        if let read = readChar {
            Logger.shared.log("Enabling notify on Anritsu readChar: \(read.uuid)", category: .system)
            peripheral.setNotifyValue(true, for: read)
        }
        if let write = writeChar {
            Logger.shared.log("Anritsu writeChar ready: \(write.uuid)", category: .system)
        }
        onReady?(peripheral)
    }

    func didReceiveNotification(from characteristic: CBCharacteristic, data: Data) {
        Logger.shared.log("Anritsu notify ← \(hexString(data))", category: .bleRx)
        ingestor.frames(from: data).forEach { onFrame?($0) }
    }

    func startMeasurement() {
        // AnritsuはNotify受信のみで常時測定値を流してくるため明示的なコマンドは不要。
    }

    func disconnect(using central: CBCentralManager) {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        readChar = nil
        writeChar = nil
    }
}
