import Foundation
import CoreBluetooth

/// 共通の温度計デバイスインターフェース。
/// - Note: これを基準に各ベンダー固有の処理（サービス探索/コマンド送信/パース）を切り出す。
protocol ThermometerDevice: AnyObject {
    /// プロファイル（サービスUUIDや名前判定に利用）
    var profile: BLEDeviceProfile { get }
    /// CoreBluetooth の周辺機器参照。接続中のみ保持する。
    var peripheral: CBPeripheral? { get set }
    /// デバイスからパース済みの温度が届いたときのコールバック。
    var onFrame: ((TemperatureFrame) -> Void)? { get set }
    /// サービス/キャラクタリスティックが揃ってコマンドを送れる状態になったときのフック。
    var onReady: (() -> Void)? { get set }
    /// デバイス固有のエラーを上位へ伝えるためのフック。
    var onError: ((String) -> Void)? { get set }

    /// 接続開始（CBCentralManager から呼ばれる）
    func connect(using central: CBCentralManager, to peripheral: CBPeripheral)
    /// 現在値取得などの計測開始トリガー。
    func startMeasurement()
    /// 明示切断時の後片付け。
    func disconnect(using central: CBCentralManager?)

    /// CoreBluetooth Delegate からのイベントを伝搬するエントリポイント。
    func didDiscoverServices(peripheral: CBPeripheral, error: Error?)
    func didDiscoverCharacteristics(for service: CBService, error: Error?)
    func didUpdateValue(for characteristic: CBCharacteristic, error: Error?)
    func didWriteValue(for characteristic: CBCharacteristic, error: Error?)
}

/// 時刻同期コマンドを流せるデバイス向けのオプションプロトコル。
protocol TimeSyncCapable {
    func sendTimeSync(_ data: Data)
}
