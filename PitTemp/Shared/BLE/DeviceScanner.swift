import Foundation
import CoreBluetooth

/// スキャンと発見処理を担当
final class DeviceScanner {
    private let allowedNamePrefixes: [String]
    weak var registry: DeviceRegistrying?
    var onDiscovered: ((ScannedDevice, CBPeripheral) -> Void)?

    init(allowedNamePrefixes: [String], registry: DeviceRegistrying? = nil) {
        self.allowedNamePrefixes = allowedNamePrefixes
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
        guard allowedNamePrefixes.contains(where: { name.hasPrefix($0) }) else { return }

        registry?.upsertSeen(id: peripheral.identifier.uuidString, name: name, rssi: rssi.intValue)

        let entry = ScannedDevice(id: peripheral.identifier.uuidString, name: name, rssi: rssi.intValue, lastSeenAt: Date())
        onDiscovered?(entry, peripheral)
    }
}
