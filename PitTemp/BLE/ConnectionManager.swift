import Foundation
import CoreBluetooth

/// サービス/キャラクタリスティック探索を担当
final class ConnectionManager {
    private let serviceUUID: CBUUID
    private let readCharUUID: CBUUID
    private let writeCharUUID: CBUUID

    var onCharacteristicsReady: ((CBPeripheral, CBCharacteristic?, CBCharacteristic?) -> Void)?
    var onFailed: ((String) -> Void)?

    init(serviceUUID: CBUUID, readCharUUID: CBUUID, writeCharUUID: CBUUID) {
        self.serviceUUID = serviceUUID
        self.readCharUUID = readCharUUID
        self.writeCharUUID = writeCharUUID
    }

    func didConnect(_ peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func didDiscoverServices(peripheral: CBPeripheral, error: Error?) {
        if let e = error {
            onFailed?("Service discovery: \(e.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            print("[BLE] target service not found yet")
            return
        }
        peripheral.discoverCharacteristics([readCharUUID, writeCharUUID], for: service)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        if let e = error {
            onFailed?("Char discovery: \(e.localizedDescription)")
            return
        }
        var readChar: CBCharacteristic?
        var writeChar: CBCharacteristic?
        service.characteristics?.forEach { ch in
            if ch.uuid == readCharUUID { readChar = ch }
            if ch.uuid == writeCharUUID { writeChar = ch }
        }
        if let ch = readChar {
            service.peripheral.setNotifyValue(true, for: ch)
        }
        onCharacteristicsReady?(service.peripheral, readChar, writeChar)
    }
}
