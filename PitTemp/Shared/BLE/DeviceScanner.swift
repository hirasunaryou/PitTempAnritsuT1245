import Foundation
import CoreBluetooth

/// スキャンと発見処理を担当
final class DeviceScanner {
    weak var registry: (any DeviceRegistrying)?
    var onDiscovered: ((ScannedDevice, CBPeripheral, [String: Any]) -> Void)?

    init(registry: (any DeviceRegistrying)? = nil) {
        self.registry = registry
    }

    func start(using central: CBCentralManager) {
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stop(using central: CBCentralManager) {
        central.stopScan()
    }

    func handleDiscovery(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                   ?? peripheral.name ?? "Unknown"

        // プロファイルに合致しない機器は一覧に出さない。
        guard let profile = ThermometerDeviceFactory.profile(for: name) else { return }

        registry?.upsertSeen(id: peripheral.identifier.uuidString, name: name, rssi: rssi.intValue)

        let entry = ScannedDevice(
            id: peripheral.identifier.uuidString,
            name: name,
            rssi: rssi.intValue,
            lastSeenAt: Date(),
            profile: profile
        )
        onDiscovered?(entry, peripheral, advertisementData)
    }
}
