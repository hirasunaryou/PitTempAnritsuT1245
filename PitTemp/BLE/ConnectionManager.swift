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
        // CBService.peripheral は weak/optional なので、通知設定や後続のコールバックに渡す前に安全に unwrap する。
        guard let peripheral = service.peripheral else {
            onFailed?("Char discovery: missing peripheral reference")
            return
        }
        if let ch = readChar {
            // 実際にデバイスからの通知を受け取れるように通知フラグを有効化する。
            peripheral.setNotifyValue(true, for: ch)
        }
        onCharacteristicsReady?(peripheral, readChar, writeChar)
    }
}
