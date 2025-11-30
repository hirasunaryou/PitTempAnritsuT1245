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
    weak var registry: DeviceRegistrying? {
        didSet { scanner.registry = registry }
    }

    // 接続対象ごとのBLEプロファイル群（Anritsu + TR4A + TR45）
    private let profiles: [BLEDeviceProfile] = [.anritsu, .tr45, .tr4a]
    private var activeDevice: ThermometerDevice?
    private var scannedProfiles: [String: BLEDeviceProfile] = [:] // peripheralID→profile

    // CoreBluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?

    // 受信処理用の専用キュー
    private let bleQueue = DispatchQueue(label: "BLE.AnritsuT1245")

    // TR4 系向けポーリングタイマー（現在値取得を1秒ごとに送信）
    private var pollingTimer: DispatchSourceTimer?

    // Parser / UseCase
    private let temperatureUseCase: TemperatureIngesting

    // その他
    @Published var notifyCountUI: Int = 0  // UI表示用（Mainで増やす）
    @Published var notifyHz: Double = 0

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
    private lazy var scanner = DeviceScanner(profiles: profiles, registry: registry)

    init(temperatureUseCase: TemperatureIngesting = TemperatureIngestUseCase()) {
        self.temperatureUseCase = temperatureUseCase
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
        setupCallbacks()
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else { return }
        scannedProfiles.removeAll()
        DispatchQueue.main.async {
            self.connectionState = .scanning
            self.scanned.removeAll()
        }
        scanner.start(using: central)
    }

    func stopScan() { scanner.stop(using: central) }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        activeDevice?.disconnect(using: central)
        activeDevice = nil
        peripheral = nil
        stopPolling()
        DispatchQueue.main.async { self.connectionState = .idle }
    }

    /// 明示的に接続（デバイスピッカーから呼ぶ想定）
    func connect(deviceID: String) {
        // 1) 既にスキャン済みならその peripheral を使う
        if let found = central.retrievePeripherals(withIdentifiers: [UUID(uuidString: deviceID)!]).first {
            stopScan()
            peripheral = found
            if let profile = scannedProfiles[deviceID] {
                activeDevice = makeDevice(for: profile)
                bindCallbacks()
            }
            DispatchQueue.main.async {
                self.deviceName = found.name ?? "Unknown"
                self.connectionState = .connecting
            }
            central.connect(found, options: nil)
            return
        }
        // 2) 未取得なら、一度スキャン開始（UI側は “Scan→Connect” ボタン連携を想定）
        startScan()
    }

    // 時刻設定
    func setDeviceTime(to date: Date = Date()) {
        let cmd = temperatureUseCase.makeTimeSyncPayload(for: date)
        if let syncCapable = activeDevice as? TimeSyncCapable {
            syncCapable.sendTimeSync(cmd)
        }
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
        scanner.onDiscovered = { [weak self] entry, peripheral in
            guard let self else { return }
            self.scannedProfiles[entry.id] = entry.profile
            DispatchQueue.main.async {
                if let idx = self.scanned.firstIndex(where: { $0.id == entry.id }) {
                    self.scanned[idx] = entry
                } else {
                    self.scanned.append(entry)
                }
            }

            if self.autoConnectOnDiscover, self.peripheral == nil, self.connectionState == .scanning {
                let pid = peripheral.identifier.uuidString
                if self.preferredIDs.isEmpty || self.preferredIDs.contains(pid) {
                    self.stopScan()
                    self.peripheral = peripheral
                    self.activeDevice = self.makeDevice(for: entry.profile)
                    self.bindCallbacks()
                    DispatchQueue.main.async {
                        self.deviceName = entry.name
                        self.connectionState = .connecting
                    }
                    print("[BLE] found \(entry.name), auto-connecting…")
                    self.central.connect(peripheral, options: nil)
                }
            }
        }
    }

    /// デバイス実装を生成するファクトリ。スキャンで得たプロファイルに応じて切り替える。
    func makeDevice(for profile: BLEDeviceProfile) -> ThermometerDevice {
        switch profile.key {
        case BLEDeviceProfile.anritsu.key: return AnritsuDevice(ingestor: temperatureUseCase)
        case BLEDeviceProfile.tr45.key: return TR4Device()
        default: return TR4ALegacyDevice(ingestor: temperatureUseCase)
        }
    }

    /// ThermometerDevice からのコールバックを UI/状態更新へブリッジする。
    func bindCallbacks() {
        guard let device = activeDevice else { return }
        device.onFrame = { [weak self] frame in
            guard let self else { return }
            DispatchQueue.main.async {
                self.latestTemperature = frame.value
                self.notifyCountUI &+= 1
            }
            self.temperatureFramesSubject.send(frame)
        }
        device.onReady = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.connectionState = .ready }
            self.setDeviceTime()
            self.activeDevice?.startMeasurement()
            self.setupPollingIfNeeded()
        }
        device.onError = { [weak self] message in
            DispatchQueue.main.async { self?.connectionState = .failed(message) }
        }
    }

    private func setupPollingIfNeeded() {
        pollingTimer?.cancel()
        pollingTimer = nil

        guard let device = activeDevice,
              device.profile.requiresPollingForRealtime else { return }

        let timer = DispatchSource.makeTimerSource(queue: bleQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            device.startMeasurement()
        }
        timer.resume()
        pollingTimer = timer
    }

    func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
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
        print("[BLE] connected to \(p.name ?? "?")")
        p.delegate = self
        peripheral = p
        if activeDevice == nil {
            // スキャン結果がない場合はAnritsu前提でフォールバック。
            activeDevice = makeDevice(for: scannedProfiles[p.identifier.uuidString] ?? .anritsu)
            bindCallbacks()
        }
        activeDevice?.connect(using: central, to: p)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect p: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.connectionState = .failed("Connect failed: \(error?.localizedDescription ?? "unknown")")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral p: CBPeripheral,
                        error: Error?) {
        stopPolling()
        activeDevice?.disconnect(using: central)
        activeDevice = nil
        DispatchQueue.main.async {
            self.connectionState = .idle
            self.latestTemperature = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        activeDevice?.didDiscoverServices(peripheral: peripheral, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        activeDevice?.didDiscoverCharacteristics(for: service, error: error)
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
        activeDevice?.didUpdateValue(for: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        activeDevice?.didWriteValue(for: characteristic, error: error)
    }
}
