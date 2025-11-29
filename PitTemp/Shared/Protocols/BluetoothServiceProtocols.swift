import Foundation
import Combine

/// UI/VM に公開する温度センサークライアントのインターフェイス
/// - Note: BLE 実装だけでなく、将来的なシミュレータやテスト用のダミーも差し替えられるよう
///   Protocol 指向にしている。
protocol TemperatureSensorClient: ObservableObject {
    var connectionState: ConnectionState { get }
    var deviceName: String? { get }
    var scanned: [ScannedDevice] { get }
    var latestTemperature: Double? { get }
    var temperatureFrames: AnyPublisher<TemperatureFrame, Never> { get }
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> { get }
    var scannedPublisher: AnyPublisher<[ScannedDevice], Never> { get }
    var deviceNamePublisher: AnyPublisher<String?, Never> { get }
    var latestTemperaturePublisher: AnyPublisher<Double?, Never> { get }

    func startScan()
    func stopScan()
    func connect(deviceID: String)
    func disconnect()
    func setDeviceTime(to date: Date)
}

/// BluetoothService が公開する追加の制御系。
/// - Important: ConnectionState などの状態は `TemperatureSensorClient` で共通化し、
///   自動再接続の設定や通知メトリクスのような「実装固有の機能」をこちらに分離している。
protocol BluetoothServicing: TemperatureSensorClient {
    var autoConnectOnDiscover: Bool { get set }
    var notifyCountUI: Int { get }
    var notifyHz: Double { get }
    var registry: DeviceRegistrying? { get set }
    var autoConnectPublisher: AnyPublisher<Bool, Never> { get }
    var notifyHzPublisher: AnyPublisher<Double, Never> { get }
    var notifyCountPublisher: AnyPublisher<Int, Never> { get }

    func setPreferredIDs(_ ids: Set<String>)
    func refreshTR4ASettings()
    func updateTR4ARecordInterval(seconds: UInt16)
}

/// スキャンで見つけたデバイスを記録するレジストリのインターフェイス。
/// - Attention: View/VM から直接 UserDefaults に触らないよう、この窓口経由で
///   永続化や別名付与を行う。
protocol DeviceRegistrying: AnyObject, ObservableObject {
    var known: [DeviceRecord] { get }

    func record(for id: String) -> DeviceRecord?
    func record(forName name: String) -> DeviceRecord?
    func upsertSeen(id: String, name: String, rssi: Int?)
    func setAlias(_ alias: String?, for id: String)
    func setAutoConnect(_ on: Bool, for id: String)
    func forget(id: String)
}
