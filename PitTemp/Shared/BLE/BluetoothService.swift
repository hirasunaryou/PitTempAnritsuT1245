//  BluetoothService.swift
//  PitTemp
//  Role: CoreBluetooth 経由で BLE 温度センサーと接続し、UI/BLE ユースケースへ橋渡しする窓口。
//  Dependencies: CoreBluetooth, Combine, NotifyController（TemperatureIngestUseCase を注入）。
//  Threading: 専用 bleQueue でコールバックを受け、UI 更新は DispatchQueue.main へ hop。

import Foundation
import CoreBluetooth
import Combine

/// BLEから温度を受け取り、TemperatureFrameとしてPublishするサービス。
/// - Note: DATA ボタンの単発送信も「通知をそのまま受け取る」運用とし、明示的なポーリング関数は持たない。
final class BluetoothService: NSObject, BluetoothServicing {
    // 公開状態（UIは Main で触る）
    @Published var connectionState: ConnectionState = .idle
    @Published var latestTemperature: Double?
    @Published var deviceName: String?
    @Published var scanned: [ScannedDevice] = []

    // ストリーム（TemperatureFrame で統一）
    private let temperatureFramesSubject = PassthroughSubject<TemperatureFrame, Never>()
    var temperatureFrames: AnyPublisher<TemperatureFrame, Never> { temperatureFramesSubject.eraseToAnyPublisher() }

    // 外部レジストリ（App から注入）
    weak var registry: (any DeviceRegistrying)? {
        didSet { scanner.registry = registry }
    }

    // CoreBluetooth
    private var central: CBCentralManager!
    private var readChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?

    // 受信処理用の専用キュー
    private let bleQueue = DispatchQueue(label: "BLE.AnritsuT1245")

    // Parser / UseCase
    private let temperatureUseCase: TemperatureIngesting
    private var device: ThermometerDevice?
    private var advertisementCache: [String: [String: Any]] = [:]

    // その他
    @Published var notifyCountUI: Int = 0  // UI表示用（Mainで増やす）
    @Published var notifyHz: Double = 0

    private let logger = Logger.shared

    // Auto-connect の実装
    @Published var autoConnectOnDiscover: Bool = false
    private(set) var preferredIDs: Set<String> = []  // ← registry から設定（空なら「最初に見つけた1台」）

    // Combine での購読口。Protocol を介しても変更検知できるよう AnyPublisher 化。
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> { $connectionState.eraseToAnyPublisher() }
    var scannedPublisher: AnyPublisher<[ScannedDevice], Never> { $scanned.eraseToAnyPublisher() }
    var deviceNamePublisher: AnyPublisher<String?, Never> { $deviceName.eraseToAnyPublisher() }
    var latestTemperaturePublisher: AnyPublisher<Double?, Never> { $latestTemperature.eraseToAnyPublisher() }
    var autoConnectPublisher: AnyPublisher<Bool, Never> { $autoConnectOnDiscover.eraseToAnyPublisher() }
    var notifyHzPublisher: AnyPublisher<Double, Never> { $notifyHz.eraseToAnyPublisher() }
    var notifyCountPublisher: AnyPublisher<Int, Never> { $notifyCountUI.eraseToAnyPublisher() }

    // コンポーネント
    private lazy var scanner = DeviceScanner(registry: registry)

    init(temperatureUseCase: TemperatureIngesting = TemperatureIngestUseCase()) {
        self.temperatureUseCase = temperatureUseCase
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
        setupCallbacks()
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else { return }
        DispatchQueue.main.async {
            self.connectionState = .scanning
            self.scanned.removeAll()
        }
        advertisementCache.removeAll()
        scanner.start(using: central)
    }

    func stopScan() { scanner.stop(using: central) }

    func disconnect() {
        if let p = device?.peripheral { central.cancelPeripheralConnection(p) }
        device?.disconnect(using: central)
        device = nil; readChar = nil; writeChar = nil
        DispatchQueue.main.async { self.connectionState = .idle }
    }

    /// 明示的に接続（デバイスピッカーから呼ぶ想定）
    func connect(deviceID: String) {
        // 1) 既にスキャン済みならその peripheral を使う
        if let found = central.retrievePeripherals(withIdentifiers: [UUID(uuidString: deviceID)!]).first {
            stopScan()
            let cachedAds = advertisementCache[deviceID] ?? [CBAdvertisementDataLocalNameKey: found.name ?? "Unknown"]
            createDeviceIfNeeded(peripheral: found, advertisementData: cachedAds)
            DispatchQueue.main.async {
                self.deviceName = found.name ?? "Unknown"
                self.connectionState = .connecting
            }
            device?.connect(using: central)
            return
        }
        // 2) 未取得なら、一度スキャン開始（UI側は “Scan→Connect” ボタン連携を想定）
        startScan()
    }

    // 時刻設定
    func setDeviceTime(to date: Date = Date()) {
        guard let p = device?.peripheral, let w = writeChar else { return }
        let cmd = temperatureUseCase.makeTimeSyncPayload(for: date)
        p.writeValue(cmd, for: w, type: .withResponse)
    }

    // UI から設定するためのセッターを用意
    func setPreferredIDs(_ ids: Set<String>) {
        // UIスレッドから来るのでそのまま代入でOK
        preferredIDs = ids
    }
}

// MARK: - Private
private extension BluetoothService {
    func setupCallbacks() {
        scanner.onDiscovered = { [weak self] entry, peripheral, advertisementData in
            guard let self else { return }
            self.advertisementCache[entry.id] = advertisementData
            DispatchQueue.main.async {
                if let idx = self.scanned.firstIndex(where: { $0.id == entry.id }) {
                    self.scanned[idx] = entry
                } else {
                    self.scanned.append(entry)
                }
            }

            if self.autoConnectOnDiscover, self.device == nil, self.connectionState == .scanning {
                let pid = peripheral.identifier.uuidString
                if self.preferredIDs.isEmpty || self.preferredIDs.contains(pid) {
                    self.stopScan()
                    self.createDeviceIfNeeded(peripheral: peripheral, advertisementData: [:])
                    DispatchQueue.main.async {
                        self.deviceName = entry.name
                        self.connectionState = .connecting
                    }
                    print("[BLE] found \(entry.name), auto-connecting…")
                    self.device?.connect(using: self.central)
                }
            }
        }
    }

    func createDeviceIfNeeded(peripheral: CBPeripheral, advertisementData: [String: Any]) {
        guard device?.identifier != peripheral.identifier.uuidString else { return }
        device = ThermometerDeviceFactory.makeDevice(peripheral: peripheral,
                                                     advertisementData: advertisementData,
                                                     temperatureUseCase: temperatureUseCase)

        device?.onReady = { [weak self] read, write in
            guard let self else { return }
            self.readChar = read
            self.writeChar = write
            DispatchQueue.main.async { self.connectionState = .ready }
            self.logger.log("Characteristics ready for \(self.device?.name ?? "-")", category: .ble)
            self.setDeviceTime()
            self.device?.startMeasurement()
        }

        device?.onTemperature = { [weak self] frame in
            guard let self else { return }
            DispatchQueue.main.async { self.latestTemperature = frame.value }
            self.temperatureFramesSubject.send(frame)
        }

        device?.onFailed = { [weak self] message in
            DispatchQueue.main.async { self?.connectionState = .failed(message) }
            self?.logger.log("Device reported failure: \(message)", category: .ble)
        }

        device?.onNotifyCount = { [weak self] count in
            self?.notifyCountUI = count
        }

        device?.onNotifyHz = { [weak self] hz in
            self?.notifyHz = hz
        }
    }
}

// MARK: - CoreBluetooth delegates
extension BluetoothService: CBCentralManagerDelegate, CBPeripheralDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: startScan()
        case .unauthorized:
            DispatchQueue.main.async { self.connectionState = .failed("Bluetooth permission denied") }
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        scanner.handleDiscovery(peripheral: p, advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        logger.log("Connected to \(p.name ?? "?")", category: .ble)
        p.delegate = self
        p.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect p: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.connectionState = .failed("Connect failed: \(error?.localizedDescription ?? "unknown")")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        device?.didDiscoverServices(error: error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        device?.didDiscoverCharacteristics(for: service, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            print("[BLE] notify state error:", e.localizedDescription)
            return
        }
        print("[BLE] notify state \(characteristic.uuid): \(characteristic.isNotifying)")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        logger.log("Notify \(characteristic.uuid): \(data.hexEncodedString())", category: .bleRx)
        device?.didUpdateValue(for: characteristic, data: data)
    }
}
