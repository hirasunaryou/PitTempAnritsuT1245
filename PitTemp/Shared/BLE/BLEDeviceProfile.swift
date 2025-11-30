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

    var serviceUUID: CBUUID { CBUUID(string: serviceUUIDString) }
    var notifyCharUUID: CBUUID { CBUUID(string: notifyCharUUIDString) }
    var writeCharUUID: CBUUID { CBUUID(string: writeCharUUIDString) }

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
        requiresPollingForRealtime: false
    )

    /// TR4A(TR41/42/43/44)のT&D SPPサービス向けプロファイル。
    /// - Note: Data Line特性はWriteWithoutResponse/Notify兼用なので同一UUIDを設定する。
    static let tr4a = BLEDeviceProfile(
        key: "tr4a",
        allowedNamePrefixes: ["TR44", "TR43", "TR42", "TR41", "TR4"],
        serviceUUIDString: "6e400001-b5a3-f393-e0a9-e50e24dcca42",
        notifyCharUUIDString: "6e400008-b5a3-f393-e0a9-e50e24dcca42",
        writeCharUUIDString: "6e400008-b5a3-f393-e0a9-e50e24dcca42",
        requiresPollingForRealtime: true
    )

    /// TR45 固有の分割フレーム仕様に合わせたプロファイル。
    static let tr45 = BLEDeviceProfile(
        key: "tr45",
        allowedNamePrefixes: ["TR45"],
        serviceUUIDString: "6e400001-b5a3-f393-e0a9-e50e24dcca42",
        notifyCharUUIDString: "6e400005-b5a3-f393-e0a9-e50e24dcca42",
        writeCharUUIDString: "6e400002-b5a3-f393-e0a9-e50e24dcca42",
        requiresPollingForRealtime: true
    )
}
