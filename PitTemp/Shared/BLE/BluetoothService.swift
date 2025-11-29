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
    @Published private(set) var activeProfileKey: String = BLEDeviceProfile.anritsu.key
    @Published var scanned: [ScannedDevice] = []

    // ストリーム（TemperatureFrame で統一）
    private let temperatureFramesSubject = PassthroughSubject<TemperatureFrame, Never>()
    var temperatureFrames: AnyPublisher<TemperatureFrame, Never> { temperatureFramesSubject.eraseToAnyPublisher() }

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
            DispatchQueue.main.async { [weak self] in
                self?.activeProfileKey = self?.activeProfile.key ?? BLEDeviceProfile.anritsu.key
            }
        }
    }
    private var scannedProfiles: [String: BLEDeviceProfile] = [:] // peripheralID→profile

    // CoreBluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var readChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?

    // 受信処理用の専用キュー
    private let bleQueue = DispatchQueue(label: "BLE.AnritsuT1245")

    // TR4A向けのポーリングタイマー（現在値取得を1秒ごとに送信）
    private var tr4aPollTimer: DispatchSourceTimer?
    private let tr4aRouter = TR4ACommandRouter()

    enum TR4AControlError: LocalizedError {
        case notTR4A
        case notReady
        case invalidPayload
        case commandFailed(status: UInt8)
        case timeout

        var errorDescription: String? {
            switch self {
            case .notTR4A:
                return "TR45/TR4A以外では実行できません"
            case .notReady:
                return "書き込みキャラクタリスティックが未接続です"
            case .invalidPayload:
                return "設定ペイロードが取得できませんでした"
            case .commandFailed(let status):
                return String(format: "TR4Aコマンドが失敗しました (status=0x%02X)", status)
            case .timeout:
                return "TR4A応答がタイムアウトしました"
            }
        }
    }

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
    var activeProfilePublisher: AnyPublisher<String, Never> { $activeProfileKey.eraseToAnyPublisher() }
    var autoConnectPublisher: AnyPublisher<Bool, Never> { $autoConnectOnDiscover.eraseToAnyPublisher() }
    var notifyHzPublisher: AnyPublisher<Double, Never> { $notifyHz.eraseToAnyPublisher() }
    var notifyCountPublisher: AnyPublisher<Int, Never> { $notifyCountUI.eraseToAnyPublisher() }

    // コンポーネント
    private lazy var scanner = DeviceScanner(profiles: profiles, registry: registry)
    private lazy var connectionManager = ConnectionManager(profile: activeProfile)
    private lazy var notifyController = NotifyController(ingestor: temperatureUseCase) { [weak self] frame in
        guard let self else { return }
        DispatchQueue.main.async { self.latestTemperature = frame.value }
        self.temperatureFramesSubject.send(frame)
    }

    init(temperatureUseCase: TemperatureIngesting = TemperatureIngestUseCase()) {
        self.temperatureUseCase = temperatureUseCase
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
        setupCallbacks()
        // TR4A 設定系のレスポンスを横取りできるよう、Rawデータのフックを生やす。
        notifyController.onRawData = { [weak self] data in self?.tr4aRouter.handle(data) }
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
        tr4aRouter.clear()
        DispatchQueue.main.async { self.connectionState = .idle }
    }

    /// 明示的に接続（デバイスピッカーから呼ぶ想定）
    func connect(deviceID: String) {
        // 1) 既にスキャン済みならその peripheral を使う
        if let found = central.retrievePeripherals(withIdentifiers: [UUID(uuidString: deviceID)!]).first {
            stopScan()
            peripheral = found
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

    /// TR45/TR4Aの記録間隔(サンプリング周波数)をBLE越しに更新する。
    /// 1) 0x85で現行設定テーブルを取得 → 2) 先頭2B(記録間隔秒)を書き換え → 3) 0x3Cで書き戻し。
    func updateTR4ARecordInterval(seconds: UInt16, completion: @escaping (Result<Void, Error>) -> Void) {
        bleQueue.async {
            guard self.activeProfile.requiresPollingForRealtime else { completion(.failure(TR4AControlError.notTR4A)); return }
            guard let peripheral = self.peripheral, let writeChar = self.writeChar else { completion(.failure(TR4AControlError.notReady)); return }

            // 先に設定読み出しを待ち受けてからコマンド送信する。
            self.tr4aRouter.waitFor(command: 0x85) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let err):
                    completion(.failure(self.translate(err)))
                case .success(let resp):
                    guard resp.status == 0x00, resp.payload.count >= 64 else {
                        completion(.failure(TR4AControlError.invalidPayload));
                        return
                    }

                    // 仕様上、記録間隔は先頭2バイト（リトルエンディアン想定）。
                    var table = Data(resp.payload.prefix(64))
                    table[0] = UInt8(seconds & 0xFF)
                    table[1] = UInt8((seconds >> 8) & 0xFF)
                    self.writeTR4ASettings(table, peripheral: peripheral, writeChar: writeChar, completion: completion)
                }
            }

            let frame = self.buildTR4ACommand(command: 0x85, payload: Data([0x00, 0x00, 0x00, 0x00]))
            self.sendTR4AFrameWithBreak(frame, to: peripheral, write: writeChar)
        }
    }

    /// TR45/TR4Aの記録停止（節電目的の“ソフト電源OFF”扱い）。
    func powerOffTR4A(completion: @escaping (Result<Void, Error>) -> Void) {
        bleQueue.async {
            guard self.activeProfile.requiresPollingForRealtime else { completion(.failure(TR4AControlError.notTR4A)); return }
            guard let peripheral = self.peripheral, let writeChar = self.writeChar else { completion(.failure(TR4AControlError.notReady)); return }

            self.tr4aRouter.waitFor(command: 0x32) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let err): completion(.failure(self.translate(err)))
                case .success(let resp):
                    guard resp.status == 0x00 else {
                        completion(.failure(TR4AControlError.commandFailed(status: resp.status)))
                        return
                    }
                    self.stopTR4APolling()
                    completion(.success(()))
                }
            }

            let frame = self.buildTR4ACommand(command: 0x32, payload: Data())
            self.sendTR4AFrameWithBreak(frame, to: peripheral, write: writeChar)
        }
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
            // 初回接続時に時刻同期（必要なら Settings で ON/OFF 化）
            self.setDeviceTime()
            startTR4APollingIfNeeded(peripheral: peripheral, write: write)
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

    /// TR4Aの現在値取得（0x33-0x01コマンド）を1秒周期で発行し、Notify経由で値を受け取る。
    /// - Note: T&Dの仕様書にある「SOH直前の0x00(ブレーク信号)→20〜100ms後コマンド送信」に合わせ、
    ///   50msのギャップを空けて2回の write を行う。1秒以上の間隔を空けて実機負荷と切断リスクを抑える。
    func startTR4APollingIfNeeded(peripheral: CBPeripheral, write: CBCharacteristic?) {
        stopTR4APolling()
        guard activeProfile.requiresPollingForRealtime, let write else { return }

        let timer = DispatchSource.makeTimerSource(queue: bleQueue)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .seconds(1))
        timer.setEventHandler { [weak self, weak peripheral] in
            guard let self, let p = peripheral else { return }
            let cmd = self.buildTR4ACurrentValueCommand()
            self.sendTR4AFrameWithBreak(cmd, to: p, write: write)
        }
        timer.resume()
        tr4aPollTimer = timer
    }

    func stopTR4APolling() {
        tr4aPollTimer?.cancel()
        tr4aPollTimer = nil
    }

    /// TR4A「現在値取得(0x33/サブコマンド0x00)」SOHコマンドフレームを組み立てる。
    /// - Structure: SOH(0x01) + CMD + SUB(0x00) + DataSize(BE=0x0004) + "0000"(4B) + CRC16-BE。
    /// - Point: 仕様書の送信例 `01 33 00 04 00 00 00 00` はデータ長が **ビッグエンディアン** で4バイトを伴う。
    ///          ここを誤ると TR45 は応答を返さないため、スマホ側に温度が届かない。
    /// - CRC は SOH 以降を CCITT 初期値 0xFFFF で計算し、ビッグエンディアンで後続に付与する。
    func buildTR4ACurrentValueCommand() -> Data {
        buildTR4ACommand(command: 0x33, payload: Data([0x00, 0x00, 0x00, 0x00]))
    }

    /// TR4A仕様書に従い、SOH〜データまでを対象にCRC16-CCITT(0x1021)を計算する。
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

    /// TR4AのSOHコマンドを組み立てる共通ユーティリティ。データ長はビッグエンディアンで格納する。
    func buildTR4ACommand(command: UInt8, payload: Data, subcommand: UInt8 = 0x00) -> Data {
        var frame = Data([0x01, command, subcommand, 0x00, 0x00])
        let length = UInt16(payload.count)
        frame[3] = UInt8((length >> 8) & 0xFF)
        frame[4] = UInt8(length & 0xFF)
        frame.append(payload)
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    /// TR4Aのコマンド送信手順（0x00ブレーク→20〜100ms→SOHフレーム送信）を1か所にまとめる。
    func sendTR4AFrameWithBreak(_ frame: Data, to peripheral: CBPeripheral, write: CBCharacteristic, delayMs: Int = 50) {
        let breakSignal = Data([0x00])
        peripheral.writeValue(breakSignal, for: write, type: .withoutResponse)
        bleQueue.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak peripheral] in
            peripheral?.writeValue(frame, for: write, type: .withoutResponse)
        }
    }

    /// 取得した64B設定テーブルを書き戻す（0x3C）。
    func writeTR4ASettings(_ table: Data, peripheral: CBPeripheral, writeChar: CBCharacteristic, completion: @escaping (Result<Void, Error>) -> Void) {
        tr4aRouter.waitFor(command: 0x3C) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err): completion(.failure(self.translate(err)))
            case .success(let resp):
                guard resp.status == 0x00 else {
                    completion(.failure(TR4AControlError.commandFailed(status: resp.status)))
                    return
                }
                completion(.success(()))
            }
        }

        let frame = buildTR4ACommand(command: 0x3C, payload: table)
        sendTR4AFrameWithBreak(frame, to: peripheral, write: writeChar)
    }

    func translate(_ error: TR4ACommandRouter.CommandError) -> TR4AControlError {
        switch error {
        case .invalidFrame: return .invalidPayload
        case .timeout: return .timeout
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
        notifyController.handleNotification(data)
    }
}
