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
        // TR45 のサービスには複数の DataLine が存在し、環境によって notify/write プロパティが異なるケースがある。
        // 期待する UUID があってもプロパティが欠けていると setNotifyValue で "request is not supported" になるため、
        // いったんサービス内の全 characteristic を取得してからプロパティを見て最適なものを選ぶ。
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        if let e = error {
            onFailed?("Char discovery: \(e.localizedDescription)")
            return
        }
        // 期待する UUID を優先しつつ、プロパティに notify/write が含まれる別の characteristic があればフェールバックする。
        let characteristics = service.characteristics ?? []

        let preferredRead = characteristics.first { $0.uuid == profile.notifyCharUUID }
        let fallbackRead = characteristics.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
        let readChar = preferredRead ?? fallbackRead

        let preferredWrite = characteristics.first { $0.uuid == profile.writeCharUUID }
        let fallbackWrite = characteristics.first {
            $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write)
        }
        let writeChar = preferredWrite ?? fallbackWrite

        // CBService.peripheral は weak/optional なので、通知設定や後続のコールバックに渡す前に安全に unwrap する。
        guard let peripheral = service.peripheral else {
            onFailed?("Char discovery: missing peripheral reference")
            return
        }

        guard let finalRead = readChar, let finalWrite = writeChar else {
            onFailed?("Char discovery: TR4A data characteristics not found")
            return
        }

        // プロパティが不足している characteristic に対して notify を有効化しようとすると iOS 側で "request is not supported"
        // になるため、対応ビットを持つことを確認したうえで設定する。
        guard finalRead.properties.contains(.notify) || finalRead.properties.contains(.indicate) else {
            let props = finalRead.properties
            onFailed?("Char discovery: read characteristic lacks notify/indicate (props=\(props))")
            return
        }

        if finalRead.properties.contains(.notify) || finalRead.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: finalRead)
        }
        onCharacteristicsReady?(peripheral, finalRead, finalWrite)
    }
}
