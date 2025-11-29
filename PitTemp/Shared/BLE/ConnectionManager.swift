import Foundation
import CoreBluetooth

/// 外部からログ出力を注入するためのシンプルなフック。
typealias ConnectionManagerLog = (String, BLEDebugLogEntry.Level) -> Void

/// サービス/キャラクタリスティック探索を担当
final class ConnectionManager {
    private var profile: BLEDeviceProfile

    var onLog: ConnectionManagerLog?

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
        // - TR45 では Data Line が 0x0002/0x0004/0x0007 など複数 advertise されるため、公式サンプルと同じ
        //   notify/write の組み合わせを優先しながらもプロパティを見て安全な候補へ落とす。
        let characteristics = service.characteristics ?? []

        func firstMatch(in order: [CBUUID], where predicate: (CBCharacteristic) -> Bool) -> CBCharacteristic? {
            for uuid in order {
                if let hit = characteristics.first(where: { $0.uuid == uuid && predicate($0) }) {
                    return hit
                }
            }
            return nil
        }

        // TR4A の実機では notify が 0x0004/0x0006、write が 0x0007（writeNR）や 0x0003（writeNR）が返ることがある。
        // 公式サンプルが想定する 0x0004 (notify) + 0x0007 (writeNR) 優先の並びを用意し、最後にプロパティのみでフォールバックする。
        let tr4aNotifyOrder: [CBUUID] = [
            CBUUID(string: "6E400004-B5A3-F393-E0A9-E50E24DCCA42"),
            CBUUID(string: "6E400006-B5A3-F393-E0A9-E50E24DCCA42"),
            profile.notifyCharUUID
        ]
        let tr4aWriteOrder: [CBUUID] = [
            CBUUID(string: "6E400007-B5A3-F393-E0A9-E50E24DCCA42"),
            CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA42"),
            profile.writeCharUUID
        ]

        let notifyPredicate: (CBCharacteristic) -> Bool = {
            $0.properties.contains(.notify) || $0.properties.contains(.indicate)
        }
        let writePredicate: (CBCharacteristic) -> Bool = {
            $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write)
        }

        let readChar: CBCharacteristic?
        let writeChar: CBCharacteristic?

        if profile == .tr4a {
            readChar = firstMatch(in: tr4aNotifyOrder, where: notifyPredicate) ?? characteristics.first(where: notifyPredicate)
            // WriteWithoutResponse を優先するため、writeNR を持つ characteristic を先に探す
            writeChar = firstMatch(in: tr4aWriteOrder, where: writePredicate) ?? characteristics.first(where: writePredicate)
        } else {
            readChar = characteristics.first { $0.uuid == profile.notifyCharUUID && notifyPredicate($0) }
                ?? characteristics.first(where: notifyPredicate)
            writeChar = characteristics.first { $0.uuid == profile.writeCharUUID && writePredicate($0) }
                ?? characteristics.first(where: writePredicate)
        }

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
            onLog?("TR4A: setNotifyValue true for \(finalRead.uuid.uuidString) on \(peripheral.identifier.uuidString)", .info)
            peripheral.setNotifyValue(true, for: finalRead)
        }
        // TR4A の場合は応答ラインが複数存在するので、すべて notify on しておく（どこにレスポンスが来ても拾うため）。
        if profile == .tr4a {
            let notifyPredicate: (CBCharacteristic) -> Bool = {
                $0.properties.contains(.notify) || $0.properties.contains(.indicate)
            }
            (service.characteristics ?? []).filter(notifyPredicate).forEach { char in
                if char != finalRead {
                    onLog?("TR4A: setNotifyValue true for \(char.uuid.uuidString) on \(peripheral.identifier.uuidString) (extra notify line)", .info)
                    peripheral.setNotifyValue(true, for: char)
                }
            }
        }
        onCharacteristicsReady?(peripheral, finalRead, finalWrite)
    }
}
