import Foundation
import CoreBluetooth

/// ベンダーごとの差異を吸収するための共通インターフェイス。
/// - Important: CoreBluetooth の各種デリゲートから呼び出されるため、
///   スレッドは BLE コールバックキューに合わせて動くことを想定している。
protocol ThermometerDevice: AnyObject {
    var peripheral: CBPeripheral { get }
    var name: String { get }
    var identifier: String { get }
    var profile: BLEDeviceProfile { get }

    /// サービス探索〜キャラクタリスティック取得が完了したタイミングで UI 側に通知する。
    var onReady: ((CBCharacteristic?, CBCharacteristic?) -> Void)? { get set }
    /// 温度フレームが生成されたら BluetoothService 経由で UI/UseCase へ流す。
    var onTemperature: ((TemperatureFrame) -> Void)? { get set }
    /// 接続・探索エラーを橋渡しする。
    var onFailed: ((String) -> Void)? { get set }
    /// Notify の受信回数を UI へ伝える（メトリクス用途）。
    var onNotifyCount: ((Int) -> Void)? { get set }
    /// Notify の周波数を UI へ伝える（メトリクス用途）。
    var onNotifyHz: ((Double) -> Void)? { get set }

    func connect(using central: CBCentralManager)
    func startMeasurement()
    func disconnect(using central: CBCentralManager)

    func didDiscoverServices(error: Error?)
    func didDiscoverCharacteristics(for service: CBService, error: Error?)
    func didUpdateValue(for characteristic: CBCharacteristic, data: Data)
}

/// 広告から適切な ThermometerDevice を生成するファクトリ。
enum ThermometerDeviceFactory {
    static func profile(for name: String) -> BLEDeviceProfile? {
        if BLEDeviceProfile.anritsu.matches(name: name) { return .anritsu }
        if BLEDeviceProfile.tr45.matches(name: name) { return .tr45 }
        if BLEDeviceProfile.tr4a.matches(name: name) { return .tr4a }
        return nil
    }

    static func makeDevice(peripheral: CBPeripheral,
                           advertisementData: [String: Any],
                           temperatureUseCase: TemperatureIngesting) -> ThermometerDevice? {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        ?? peripheral.name ?? "Unknown"

        guard let profile = profile(for: name) else { return nil }

        switch profile {
        case .anritsu:
            return AnritsuDevice(peripheral: peripheral,
                                 name: name,
                                 temperatureUseCase: temperatureUseCase)
        case .tr4a:
            return TR4APolledDevice(peripheral: peripheral,
                                    name: name,
                                    temperatureUseCase: temperatureUseCase)
        case .tr45:
            return TR4Device(peripheral: peripheral, name: name)
        default:
            return nil
        }
    }
}
