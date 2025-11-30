import Foundation
import CoreBluetooth

/// 複数メーカーのBLE温度計を判別・接続するためのプロファイル定義。
/// - Important: CBUUIDはEquatableではないため文字列表現で保持し、必要なときにCBUUIDへ変換する。
///   こうすることでスキャン一覧やテストの比較も安全に行える。
struct BLEDeviceProfile: Equatable, Codable {
    let key: String
    let allowedNamePrefixes: [String]
    let serviceUUIDString: String
    let notifyCharUUIDString: String
    let writeCharUUIDString: String
    let requiresPollingForRealtime: Bool
    let additionalNotifyUUIDStrings: [String]
    let additionalWriteUUIDStrings: [String]

    var serviceUUID: CBUUID { CBUUID(string: serviceUUIDString) }
    var notifyCharUUID: CBUUID { CBUUID(string: notifyCharUUIDString) }
    var writeCharUUID: CBUUID { CBUUID(string: writeCharUUIDString) }
    var notifyUUIDs: [CBUUID] { [notifyCharUUID] + additionalNotifyUUIDStrings.map(CBUUID.init) }
    var writeUUIDs: [CBUUID] { [writeCharUUID] + additionalWriteUUIDStrings.map(CBUUID.init) }

    /// 広告に含まれるローカルネームからプロファイルを推定するシンプルなフィルタ。
    func matches(name: String) -> Bool {
        allowedNamePrefixes.contains { name.hasPrefix($0) }
    }
}

extension BLEDeviceProfile {
    /// 既存のAnritsu T1245向けプロファイル。
    static let anritsu = BLEDeviceProfile(
        key: "anritsu",
        allowedNamePrefixes: ["AnritsuM-"],
        serviceUUIDString: "ada98080-888b-4e9f-9a7f-07ddc240f3ce",
        notifyCharUUIDString: "ada98081-888b-4e9f-9a7f-07ddc240f3ce",
        writeCharUUIDString: "ada98082-888b-4e9f-9a7f-07ddc240f3ce",
        requiresPollingForRealtime: false,
        additionalNotifyUUIDStrings: [],
        additionalWriteUUIDStrings: []
    )

    /// TR45 (TR4 シリーズ) 専用の SPP 拡張サービス向けプロファイル。
    static let tr4 = BLEDeviceProfile(
        key: "tr4",
        allowedNamePrefixes: ["TR45", "TR44", "TR43", "TR42", "TR41", "TR4"],
        serviceUUIDString: "6e400001-b5a3-f393-e0a9-e50e24dcca42",
        notifyCharUUIDString: "6e400005-b5a3-f393-e0a9-e50e24dcca42",
        writeCharUUIDString: "6e400002-b5a3-f393-e0a9-e50e24dcca42",
        requiresPollingForRealtime: true,
        additionalNotifyUUIDStrings: ["6e400006-b5a3-f393-e0a9-e50e24dcca42"],
        additionalWriteUUIDStrings: ["6e400003-b5a3-f393-e0a9-e50e24dcca42", "6e400007-b5a3-f393-e0a9-e50e24dcca42"]
    )
}
