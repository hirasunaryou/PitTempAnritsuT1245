import Foundation
import CoreBluetooth

/// Anritsu T1245 向けのデバイスドライバ。既存の ASCII Notify ロジックを分離。
final class AnritsuDevice: ThermometerDevice {
    let peripheral: CBPeripheral
    let name: String
    let identifier: String
    let profile: BLEDeviceProfile = .anritsu

    var onReady: ((CBCharacteristic?, CBCharacteristic?) -> Void)?
    var onTemperature: ((TemperatureFrame) -> Void)?
    var onFailed: ((String) -> Void)?
    var onNotifyCount: ((Int) -> Void)?
    var onNotifyHz: ((Double) -> Void)?

    private let connectionManager = ConnectionManager(profile: .anritsu)
    private let notifyController: NotifyController
    private let logger = Logger.shared

    init(peripheral: CBPeripheral, name: String, temperatureUseCase: TemperatureIngesting) {
        self.peripheral = peripheral
        self.name = name
        self.identifier = peripheral.identifier.uuidString
        self.notifyController = NotifyController(ingestor: temperatureUseCase) { [weak self] frame in
            self?.onTemperature?(frame)
        }
        setupCallbacks()
    }

    func connect(using central: CBCentralManager) {
        central.connect(peripheral, options: nil)
    }

    func startMeasurement() {
        // Anritsu は Notify 購読だけで継続測定を受信するため特別なコマンドは不要。
        logger.log("Anritsu measurement stream listening", category: .ble)
    }

    func disconnect(using central: CBCentralManager) { }

    func didDiscoverServices(error: Error?) {
        connectionManager.didDiscoverServices(peripheral: peripheral, error: error)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        connectionManager.didDiscoverCharacteristics(for: service, error: error)
    }

    func didUpdateValue(for characteristic: CBCharacteristic, data: Data) {
        logger.log("Anritsu notify: \(data.hexEncodedString())", category: .bleRx)
        notifyController.handleNotification(data)
    }
}

private extension AnritsuDevice {
    func setupCallbacks() {
        connectionManager.onCharacteristicsReady = { [weak self] _, read, write in
            self?.onReady?(read, write)
        }
        connectionManager.onFailed = { [weak self] message in
            self?.onFailed?(message)
        }
        notifyController.onCountUpdate = { [weak self] count in self?.onNotifyCount?(count) }
        notifyController.onHzUpdate = { [weak self] hz in self?.onNotifyHz?(hz) }
    }
}
