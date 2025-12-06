import Foundation
import CoreBluetooth

/// 共通の温度計デバイスインターフェース。
/// - Note: 複数ベンダーの実装差分を吸収し、BluetoothService からはこのプロトコルだけを見る。
protocol ThermometerDevice: AnyObject {
    /// 検出・接続に利用する BLE プロファイル情報。
    var profile: BLEDeviceProfile { get }

    /// リアルタイム値を得るためにポーリングが必要かどうか。
    var requiresPollingForRealtime: Bool { get }

    /// 接続対象の CBPeripheral をデバイスに紐付ける。
    func bind(peripheral: CBPeripheral)

    /// 接続完了時に呼び出される初期化フック。
    func connect()

    /// サービス発見後に必要なキャラクタリスティック探索を依頼する。
    func discoverCharacteristics(on peripheral: CBPeripheral, service: CBService)

    /// Notify/Write など BLE イベントをデバイス専用ロジックへ橋渡しする。
    func didDiscoverCharacteristics(error: Error?)
    func didUpdateValue(for characteristic: CBCharacteristic, data: Data)
    func didWriteValue(for characteristic: CBCharacteristic, error: Error?)

    /// 端末時刻同期。
    func setDeviceTime(_ date: Date)

    /// 現在値取得など、即時計測要求を開始する。
    func startMeasurement()

    /// 切断時のリセット処理。
    func disconnect()

    /// 複数チャンネルを持つデバイスで、どのチャンネルを取得対象にするかを外部から指示するためのフック。
    /// - Note: チャンネルを持たないデバイスはデフォルト実装の no-op をそのまま使う。
    func setInputChannel(_ channel: Int)

    /// UI へ温度フレームを流すコールバック。
    var onFrame: ((TemperatureFrame) -> Void)? { get set }

    /// デバイスが計測可能になったタイミングで呼ばれるコールバック。
    var onReady: (() -> Void)? { get set }
}

extension ThermometerDevice {
    /// チャンネル非対応デバイス向けのデフォルト実装（何もしない）。
    func setInputChannel(_ channel: Int) { /* default no-op */ }
}
