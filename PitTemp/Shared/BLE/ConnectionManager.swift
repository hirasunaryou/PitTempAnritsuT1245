import Foundation
import CoreBluetooth

/// サービス/キャラクタリスティック探索を担当
final class ConnectionManager {
    private var profile: BLEDeviceProfile

    var onCharacteristicsReady: ((CBPeripheral, CBCharacteristic?, CBCharacteristic?) -> Void)?
    var onFailed: ((String) -> Void)?
    var onServiceSnapshot: (([CBService]) -> Void)?
    var onCharacteristicSnapshot: ((CBService, [CBCharacteristic]) -> Void)?

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
        onServiceSnapshot?(peripheral.services ?? [])
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
        onCharacteristicSnapshot?(service, service.characteristics ?? [])
        // 期待する UUID を優先しつつ、プロパティに notify/write が含まれる別の characteristic があればフェールバックする。
        let characteristics = service.characteristics ?? []

        // UUID一致を優先しつつ、通知/書き込みビットが無ければプロパティ優先で安全な characteristic を選ぶ。
        // TR45 の環境によっては DataLine UUID が複数あり、必ずしも notify/write ビットを持っていないものが先に見つかるため。
        let preferredRead = characteristics.first {
            $0.uuid == profile.notifyCharUUID && ($0.properties.contains(.notify) || $0.properties.contains(.indicate))
        }
        let fallbackRead = characteristics.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
        let readChar = preferredRead ?? fallbackRead

        let preferredWrite = characteristics.first {
            $0.uuid == profile.writeCharUUID && ($0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write))
        }
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

        // setNotifyValue は notify/indicate ビットが無い characteristic へ投げると iOS 側がエラーを返す。
        // 上の選択処理でビットを確認済みだが、ここでも安全のためチェックしてから登録する。
        if finalRead.properties.contains(.notify) || finalRead.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: finalRead)
        }
        onCharacteristicsReady?(peripheral, finalRead, finalWrite)
    }
}
