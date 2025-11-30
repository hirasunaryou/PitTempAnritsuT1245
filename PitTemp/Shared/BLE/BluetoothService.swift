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
    @Published var currentPeripheralID: String?
    @Published var scanned: [ScannedDevice] = []
    @Published var tr4aState: TR4ADeviceState? = nil

    // ストリーム（TemperatureFrame で統一）
    private let temperatureFramesSubject = PassthroughSubject<TemperatureFrame, Never>()
    var temperatureFrames: AnyPublisher<TemperatureFrame, Never> { temperatureFramesSubject.eraseToAnyPublisher() }
    private let tr4aStateSubject = PassthroughSubject<TR4ADeviceState, Never>()
    var tr4aStatePublisher: AnyPublisher<TR4ADeviceState, Never> { tr4aStateSubject.eraseToAnyPublisher() }

    // 外部レジストリ（App から注入）
    weak var registry: DeviceRegistrying? {
        didSet { scanner.registry = registry }
    }

    // 接続対象ごとのBLEプロファイル群（Anritsu + TR4A）
    private let profiles: [BLEDeviceProfile] = [.anritsu, .tr4a]
    private var activeProfile: BLEDeviceProfile = .anritsu {
        didSet {
            // UUIDを差し替えても接続済みインスタンスを再利用できるよう、ConnectionManagerにも伝搬する。
            connectionManager.updateProfile(activeProfile)
        }
    }
    private var scannedProfiles: [String: BLEDeviceProfile] = [:] // peripheralID→profile

    // CoreBluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var readChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?

    private var tr4aClient: TR4AThermometerClient?

    // 受信処理用の専用キュー
    private let bleQueue = DispatchQueue(label: "BLE.AnritsuT1245")

    // TR4A向けのポーリングタイマー（現在値取得を1秒ごとに送信）
    private var tr4aPollTimer: DispatchSourceTimer?

    // Parser / UseCase
    private let temperatureUseCase: TemperatureIngesting
    private let registrationStore: RegistrationCodeStore
    private weak var uiLogger: UILogPublishing?

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
    var currentPeripheralIDPublisher: AnyPublisher<String?, Never> { $currentPeripheralID.eraseToAnyPublisher() }
    var latestTemperaturePublisher: AnyPublisher<Double?, Never> { $latestTemperature.eraseToAnyPublisher() }
    var autoConnectPublisher: AnyPublisher<Bool, Never> { $autoConnectOnDiscover.eraseToAnyPublisher() }
    var notifyHzPublisher: AnyPublisher<Double, Never> { $notifyHz.eraseToAnyPublisher() }
    var notifyCountPublisher: AnyPublisher<Int, Never> { $notifyCountUI.eraseToAnyPublisher() }
    var tr4aStatePublisher: AnyPublisher<TR4ADeviceState, Never> { tr4aStateSubject.eraseToAnyPublisher() }

    // コンポーネント
    private lazy var scanner = DeviceScanner(profiles: profiles, registry: registry)
    private lazy var connectionManager = ConnectionManager(profile: activeProfile)
    private lazy var notifyController = NotifyController(ingestor: temperatureUseCase) { [weak self] frame in
        guard let self else { return }
        DispatchQueue.main.async { self.latestTemperature = frame.value }
        self.temperatureFramesSubject.send(frame)
    }

    init(temperatureUseCase: TemperatureIngesting = TemperatureIngestUseCase(),
         registrationStore: RegistrationCodeStore = RegistrationCodeStore(),
         uiLogger: UILogPublishing? = nil) {
        self.temperatureUseCase = temperatureUseCase
        self.registrationStore = registrationStore
        self.uiLogger = uiLogger
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
        peripheral = nil; readChar = nil; writeChar = nil
        stopTR4APolling()
        tr4aClient = nil
        currentPeripheralID = nil
        DispatchQueue.main.async { self.connectionState = .idle }
    }

    /// 明示的に接続（デバイスピッカーから呼ぶ想定）
    func connect(deviceID: String) {
        // 1) 既にスキャン済みならその peripheral を使う
        if let found = central.retrievePeripherals(withIdentifiers: [UUID(uuidString: deviceID)!]).first {
            stopScan()
            peripheral = found
            currentPeripheralID = found.identifier.uuidString
            if let profile = scannedProfiles[deviceID] { switchProfile(to: profile) }
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
        guard let p = peripheral, let w = writeChar else { return }
        let cmd = temperatureUseCase.makeTimeSyncPayload(for: date)
        p.writeValue(cmd, for: w, type: .withResponse)
    }

    // UI から設定するためのセッターを用意
    func setPreferredIDs(_ ids: Set<String>) {
        // UIスレッドから来るのでそのまま代入でOK
        preferredIDs = ids
    }

    func requestTR4ASettings() { tr4aClient?.requestRecordingSettings() }

    func updateTR4ARecording(interval: UInt8, endless: Bool) {
        tr4aClient?.updateRecording(interval: interval, endless: endless)
    }

    func startTR4ARecording() { tr4aClient?.startRecording() }

    func stopTR4ARecording() { tr4aClient?.stopRecording() }

    func sendTR4APasscode(_ code: String) {
        tr4aClient?.saveRegistrationCode(code)
        tr4aClient?.sendPasscode(code)
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
                    self.currentPeripheralID = pid
                    self.switchProfile(to: entry.profile)
                    DispatchQueue.main.async {
                        self.deviceName = entry.name
                        self.connectionState = .connecting
                    }
                    print("[BLE] found \(entry.name), auto-connecting…")
                    self.central.connect(peripheral, options: nil)
                }
            }
        }

        connectionManager.onCharacteristicsReady = { [weak self] peripheral, read, write in
            guard let self else { return }
            self.readChar = read
            self.writeChar = write
            DispatchQueue.main.async { self.connectionState = .ready }
            self.log("Characteristics ready. notify=\(read?.uuid.uuidString ?? "none"), write=\(write?.uuid.uuidString ?? "none")")
            // 初回接続時に時刻同期（必要なら Settings で ON/OFF 化）
            self.setDeviceTime()
            self.startTR4AIfNeeded(peripheral: peripheral, notify: read, write: write)
        }
        connectionManager.onFailed = { [weak self] message in
            DispatchQueue.main.async { self?.connectionState = .failed(message) }
        }

        notifyController.onCountUpdate = { [weak self] count in
            self?.notifyCountUI = count
        }
        notifyController.onHzUpdate = { [weak self] hz in
            self?.notifyHz = hz
        }
    }

    /// プロファイル切替のユーティリティ。すでに同じプロファイルなら何もしない。
    func switchProfile(to profile: BLEDeviceProfile) {
        guard profile != activeProfile else { return }
        activeProfile = profile
        if !profile.requiresPollingForRealtime { stopTR4APolling() }
    }

    /// TR4A クライアントを初期化し、Notify/ポーリングを開始する。TR4A 以外では既存の NotifyController に任せる。
    func startTR4AIfNeeded(peripheral: CBPeripheral, notify: CBCharacteristic?, write: CBCharacteristic?) {
        stopTR4APolling()
        tr4aClient = nil
        guard activeProfile.requiresPollingForRealtime,
              let notify,
              let write else { return }

        let client = TR4AThermometerClient(
            peripheral: peripheral,
            notifyCharacteristic: notify,
            writeCharacteristic: write,
            registrationStore: registrationStore
        ).configure(handlers: TR4AThermometerClient.EventHandlers(
            onTemperature: { [weak self] frame in
                self?.temperatureFramesSubject.send(frame)
                DispatchQueue.main.async { self?.latestTemperature = frame.value }
            },
            onStateUpdate: { [weak self] state in
                self?.tr4aStateSubject.send(state)
                DispatchQueue.main.async { self?.tr4aState = state }
            },
            onLog: { [weak self] message in self?.log(message) },
            onSecurityNeeded: { [weak self] in self?.log("Security required – waiting for passcode") },
            onError: { [weak self] error in self?.log(error) }
        ))
        tr4aClient = client
        client.start()
        client.startPolling()
    }

    func stopTR4APolling() {
        tr4aPollTimer?.cancel()
        tr4aPollTimer = nil
        tr4aClient?.stopPolling()
    }

    func log(_ message: String) {
        print("[BLE-DEBUG]", message)
        uiLogger?.publish(UILogEntry(message: message, level: .info, category: .ble))
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
        connectionManager.didConnect(p)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect p: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.connectionState = .failed("Connect failed: \(error?.localizedDescription ?? "unknown")")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        connectionManager.didDiscoverServices(peripheral: peripheral, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        connectionManager.didDiscoverCharacteristics(for: service, error: error)
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
        if activeProfile.requiresPollingForRealtime {
            tr4aClient?.handleNotification(data)
        } else {
            notifyController.handleNotification(data)
        }
    }
}
