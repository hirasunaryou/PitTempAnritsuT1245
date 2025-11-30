import Foundation
import CoreBluetooth

/// 既存 TR4A (TR41/42/43/44) のポーリング実装をデバイスクラスとして切り出し。
final class TR4APolledDevice: ThermometerDevice {
    let peripheral: CBPeripheral
    let name: String
    let identifier: String
    let profile: BLEDeviceProfile = .tr4a

    var onReady: ((CBCharacteristic?, CBCharacteristic?) -> Void)?
    var onTemperature: ((TemperatureFrame) -> Void)?
    var onFailed: ((String) -> Void)?
    var onNotifyCount: ((Int) -> Void)?
    var onNotifyHz: ((Double) -> Void)?

    private let connectionManager = ConnectionManager(profile: .tr4a)
    private let temperatureUseCase: TemperatureIngesting
    private lazy var notifyController: NotifyController = {
        // lazy 初期化で self を安全にキャプチャし、初期化順序の警告を防ぐ。
        NotifyController(ingestor: temperatureUseCase) { [weak self] frame in
            self?.onTemperature?(frame)
        }
    }()
    private let logger = Logger.shared

    private var pollTimer: DispatchSourceTimer?
    private weak var writeChar: CBCharacteristic?

    init(peripheral: CBPeripheral, name: String, temperatureUseCase: TemperatureIngesting) {
        self.peripheral = peripheral
        self.name = name
        self.identifier = peripheral.identifier.uuidString
        self.temperatureUseCase = temperatureUseCase
        setupCallbacks()
    }

    deinit { stopPolling() }

    func connect(using central: CBCentralManager) {
        central.connect(peripheral, options: nil)
    }

    func startMeasurement() {
        guard let writeChar else { return }
        startPolling(write: writeChar)
    }

    func disconnect(using central: CBCentralManager) {
        stopPolling()
    }

    func didDiscoverServices(error: Error?) {
        connectionManager.didDiscoverServices(peripheral: peripheral, error: error)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        connectionManager.didDiscoverCharacteristics(for: service, error: error)
    }

    func didUpdateValue(for characteristic: CBCharacteristic, data: Data) {
        logger.log("TR4A notify: \(data.hexEncodedString())", category: .bleRx)
        notifyController.handleNotification(data)
    }
}

private extension TR4APolledDevice {
    func setupCallbacks() {
        connectionManager.onCharacteristicsReady = { [weak self] _, read, write in
            self?.writeChar = write
            self?.onReady?(read, write)
        }
        connectionManager.onFailed = { [weak self] message in self?.onFailed?(message) }
        notifyController.onCountUpdate = { [weak self] count in self?.onNotifyCount?(count) }
        notifyController.onHzUpdate = { [weak self] hz in self?.onNotifyHz?(hz) }
    }

    func startPolling(write: CBCharacteristic) {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "BLE.TR4A.Poll"))
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let cmd = self.buildTR4ACurrentValueCommand()
            self.peripheral.writeValue(cmd, for: write, type: .withoutResponse)
            self.logger.log("TR4A poll 0x33: \(cmd.hexEncodedString())", category: .bleTx)
        }
        timer.resume()
        pollTimer = timer
    }

    func stopPolling() { pollTimer?.cancel(); pollTimer = nil }

    func buildTR4ACurrentValueCommand() -> Data {
        var frame = Data([0x01, 0x33, 0x01, 0x00, 0x00])
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))

        var packet = Data([0x00])
        packet.append(frame)
        return packet
    }

    func crc16CCITT(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}
