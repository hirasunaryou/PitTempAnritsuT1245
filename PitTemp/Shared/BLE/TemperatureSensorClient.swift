import Foundation

/// スキャン結果の軽量ビュー
struct ScannedDevice: Identifiable, Equatable {
    let id: String            // peripheral.identifier.uuidString
    var name: String          // 広告名
    var rssi: Int             // dBm
    var lastSeenAt: Date
    var profile: BLEDeviceProfile // どのBLE仕様で接続すべきか（Anritsu/TR4Aなど）
}

/// 温度センサーとの接続状態
enum ConnectionState: Equatable {
    case idle, scanning, connecting, ready, failed(String)
}
