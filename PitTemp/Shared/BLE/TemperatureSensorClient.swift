import Foundation
import Combine

/// スキャン結果の軽量ビュー
struct ScannedDevice: Identifiable, Equatable {
    let id: String            // peripheral.identifier.uuidString
    var name: String          // 広告名
    var rssi: Int             // dBm
    var lastSeenAt: Date
}

/// 温度センサーとの接続状態
enum ConnectionState: Equatable {
    case idle, scanning, connecting, ready, failed(String)
}

/// UI/VM に公開する温度センサークライアントのインターフェイス
protocol TemperatureSensorClient: ObservableObject {
    var connectionState: ConnectionState { get }
    var deviceName: String? { get }
    var scanned: [ScannedDevice] { get }
    var latestTemperature: Double? { get }
    var temperatureFrames: AnyPublisher<TemperatureFrame, Never> { get }

    func startScan()
    func stopScan()
    func connect(deviceID: String)
    func disconnect()
    func setDeviceTime(to date: Date)
}
