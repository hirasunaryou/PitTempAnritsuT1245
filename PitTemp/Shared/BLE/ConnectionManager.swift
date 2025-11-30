import Foundation
import CoreBluetooth

/// サービス/キャラクタリスティック探索を担当
final class ConnectionManager {
    private var profile: BLEDeviceProfile

    var onCharacteristicsReady: ((CBPeripheral, CBCharacteristic?, CBCharacteristic?) -> Void)?
    var onFailed: ((String) -> Void)?

    init(profile: BLEDeviceProfile) {
        self.profile = profile
    }

    /// 接続先プロファイルを切り替える（Anritsu/TR4AでUUIDが異なるため）。
    func updateProfile(_ profile: BLEDeviceProfile) {
        self.profile = profile
    }

    func didConnect(_ peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func didDiscoverServices(peripheral: CBPeripheral, error: Error?) {
        if let e = error {
            onFailed?("Service discovery: \(e.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == profile.serviceUUID }) else {
            print("[BLE] target service not found yet")
            return
        }
        var uuids: [CBUUID] = [profile.notifyCharUUID, profile.writeCharUUID]
        uuids.append(contentsOf: profile.alternateNotifyUUIDs)
        uuids.append(contentsOf: profile.alternateWriteUUIDs)
        peripheral.discoverCharacteristics(uuids, for: service)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        if let e = error {
            onFailed?("Char discovery: \(e.localizedDescription)")
            return
        }
        var readChar: CBCharacteristic?
        var writeChar: CBCharacteristic?
        service.characteristics?.forEach { ch in
            if ch.uuid == profile.notifyCharUUID || profile.alternateNotifyUUIDs.contains(ch.uuid) {
                // TR45 support: try to pick the recommended notify characteristic (0x0004) first.
                if readChar == nil || ch.uuid == profile.notifyCharUUID {
                    readChar = ch
                }
            }
            if ch.uuid == profile.writeCharUUID || profile.alternateWriteUUIDs.contains(ch.uuid) {
                // Prefer 0x0002 (with response) but fall back to others if not present.
                if writeChar == nil || ch.uuid == profile.writeCharUUID {
                    writeChar = ch
                }
            }
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
