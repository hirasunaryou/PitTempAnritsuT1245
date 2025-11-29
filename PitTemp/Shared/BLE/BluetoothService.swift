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

    // 受信処理用の専用キュー
    private let bleQueue = DispatchQueue(label: "BLE.AnritsuT1245")

    // TR4A向けのポーリングタイマー（現在値取得を1秒ごとに送信）
    private var tr4aPollTimer: DispatchSourceTimer?
    // TR4A ポーリング間隔（節電モードやログ間隔に合わせて可変にできるよう公開）。
    private var tr4aPollingIntervalSeconds: TimeInterval = 1.0
    // TR4A 記録設定のスナップショットと保留中の更新値
    private var tr4aLatestSettingsTable: Data?
    private var tr4aPendingIntervalUpdateSeconds: UInt16?

    // Parser / UseCase
    private let temperatureUseCase: TemperatureIngesting

    // その他
    @Published var notifyCountUI: Int = 0  // UI表示用（Mainで増やす）
    @Published var notifyHz: Double = 0
    @Published private(set) var bleDebugLog: [BLEDebugLogEntry] = []  // BLEイベントの簡易ログ（上限付き）

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
    var bleDebugLogPublisher: AnyPublisher<[BLEDebugLogEntry], Never> { $bleDebugLog.eraseToAnyPublisher() }

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
    }

    // MARK: - Public API

    func startScan() {
        guard central.state == .poweredOn else {
            appendBLELog("Scan skipped because Bluetooth state = \(central.state.rawValue)", level: .warning)
            return
        }
        appendBLELog("Starting scan for known thermometer profiles…")
        scannedProfiles.removeAll()
        DispatchQueue.main.async {
            self.connectionState = .scanning
            self.scanned.removeAll()
        }
        scanner.start(using: central)
    }

    func stopScan() {
        appendBLELog("Scan stopped (manual or connect path)")
        scanner.stop(using: central)
    }

    func disconnect() {
        handleDisconnection(resetState: true, reason: "Disconnected by user")
    }

    /// BLEログを手動でクリアするための窓口。デバッグ画面から呼び出される。
    func clearDebugLog() {
        DispatchQueue.main.async { [weak self] in self?.bleDebugLog.removeAll() }
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
            appendBLELog("Connecting to \(found.name ?? deviceID) [retrieved peripheral]")
            central.connect(found, options: nil)
            return
        }
        // 2) 未取得なら、一度スキャン開始（UI側は “Scan→Connect” ボタン連携を想定）
        appendBLELog("Requested connect to \(deviceID) but not cached; restarting scan")
        startScan()
    }

    // 時刻設定
    func setDeviceTime(to date: Date = Date()) {
        guard let p = peripheral, p.state == .connected, let w = writeChar else { return }
        let cmd = temperatureUseCase.makeTimeSyncPayload(for: date)
        appendBLELog("Sending time sync (size=\(cmd.count) bytes)")
        p.writeValue(cmd, for: w, type: preferredWriteType(for: w))
    }

    /// TR4A の設定テーブル（64byte）を読み出す。アプリからサンプリング間隔を変更する前段として利用。
    func refreshTR4ASettings() {
        guard activeProfile.requiresPollingForRealtime, let p = peripheral, p.state == .connected, let w = writeChar else { return }
        let frame = buildTR4ASettingsRequestCommand()
        appendBLELog("Requesting TR4A settings table (0x85, \(frame.count) bytes)")
        sendTR4ACommandWithBreak(frame, peripheral: p, write: w)
    }

    /// TR4A のサンプリング間隔（記録間隔）をアプリ側から更新する。
    /// - Note: 仕様上、まず 0x85 で設定テーブルを取得し、その内容を上書きして 0x3C で書き戻す必要がある。
    func updateTR4ARecordInterval(seconds: UInt16) {
        guard activeProfile.requiresPollingForRealtime else { return }
        tr4aPendingIntervalUpdateSeconds = seconds
        appendBLELog("Queued TR4A interval update to \(seconds)s (will apply after 0x85 response)")
        refreshTR4ASettings()
    }

    /// TR4A の現在値ポーリング周期を動的に変更する（0で停止）。
    /// - Important: TR45 には物理スイッチがないため、アプリ側でこの値を長くするとコマンド送信頻度が下がり、節電モード相当の挙動になる。
    func setTR4APollingInterval(seconds: TimeInterval) {
        let clamped = max(0.0, seconds)
        // BLEキュー上でタイマーを組み立て直す（UIスレッドから呼ばれても安全）。
        bleQueue.async { [weak self] in
            guard let self else { return }
            self.tr4aPollingIntervalSeconds = clamped

            // 接続済みなら即座に反映。0秒の場合はポーリング停止のみ実施。
            guard let p = self.peripheral, p.state == .connected, let w = self.writeChar, self.activeProfile.requiresPollingForRealtime else {
                return
            }
            if clamped == 0 {
                self.appendBLELog("TR4A polling stopped (interval set to 0s)")
                self.stopTR4APolling()
            } else {
                self.appendBLELog("TR4A polling interval updated to \(String(format: "%.1f", clamped))s")
                self.startTR4APollingIfNeeded(peripheral: p, write: w, intervalSeconds: clamped)
            }
        }
    }

    // UI から設定するためのセッターを用意
    func setPreferredIDs(_ ids: Set<String>) {
        // UIスレッドから来るのでそのまま代入でOK
        preferredIDs = ids
    }

    /// 内部デバッグログに追加するユーティリティ。BLEキューから呼ばれるため Main へ hop する。
    func appendBLELog(_ message: String, level: BLEDebugLogEntry.Level = .info) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            bleDebugLog.append(BLEDebugLogEntry(message: message, level: level))
            if bleDebugLog.count > 200 { bleDebugLog.removeFirst(bleDebugLog.count - 200) }
        }
        // Xcode コンソールにも残しておくと、実機デバッグ時に時系列を追いやすい。
        print("[BLE-DEBUG]", message)
    }
}

// MARK: - Private
private extension BluetoothService {
    func setupCallbacks() {
        scanner.onDiscovered = { [weak self] entry, peripheral in
            guard let self else { return }
            self.scannedProfiles[entry.id] = entry.profile
            self.appendBLELog("Cache discovery: \(entry.name) profile=\(entry.profile.key) RSSI=\(entry.rssi ?? 0)")
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
            self.appendBLELog("Notify=\(read?.uuid.uuidString ?? "nil"), Write=\(write?.uuid.uuidString ?? "nil") selected")
            startTR4APollingIfNeeded(peripheral: peripheral, write: write)
        }
        connectionManager.onFailed = { [weak self] message in
            DispatchQueue.main.async { self?.connectionState = .failed(message) }
            self?.appendBLELog("Characteristic discovery failed: \(message)", level: .error)
        }
        connectionManager.onServiceSnapshot = { [weak self] services in
            let list = services.map { $0.uuid.uuidString }.joined(separator: ", ")
            self?.appendBLELog("Service discovery returned: [\(list)]")
        }
        connectionManager.onCharacteristicSnapshot = { [weak self] service, chars in
            guard let self else { return }
            let entries = chars.map { c in
                let props = describeProperties(c.properties)
                return "\(c.uuid.uuidString) [\(props)]"
            }.joined(separator: ", ")
            appendBLELog("Characteristics under \(service.uuid.uuidString): \(entries)")
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

    /// TR4Aの現在値取得（0x33-0x00コマンド）を1秒周期で発行し、Notify経由で値を受け取る。
    /// - Important: TR4Aシリーズは「0x00（ブレーク）送信→20〜100ms待機→SOHコマンド送信」の順で
    ///   送らないと応答が返らない。BLEの書き込み制限を考慮して、ブレークとコマンドを分離し、
    ///   専用キューでディレイを挟んで送信している。
    func startTR4APollingIfNeeded(peripheral: CBPeripheral, write: CBCharacteristic?, intervalSeconds: TimeInterval? = nil) {
        stopTR4APolling()
        guard activeProfile.requiresPollingForRealtime, let write, peripheral.state == .connected else { return }

        // 接続維持のため最低1秒周期、0なら停止。UIから渡された値を優先し、未指定なら保存値を利用。
        let interval = max(intervalSeconds ?? tr4aPollingIntervalSeconds, 0)
        guard interval > 0 else { return }
        let repeatMs = max(1000, Int(interval * 1000))
        appendBLELog("TR4A polling timer armed: every \(repeatMs) ms on \(peripheral.name ?? "?")")

        let timer = DispatchSource.makeTimerSource(queue: bleQueue)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(repeatMs))
        timer.setEventHandler { [weak self, weak peripheral] in
            guard let self, let p = peripheral else { return }
            // CBPeripheral の接続状態はタイマー発火時に変化していることがあるため、毎回確認する。
            guard p.state == .connected else {
                self.stopTR4APolling()
                return
            }
            let frame = self.buildTR4ACurrentValueCommand()
            self.appendBLELog("→ Send 0x33 current-value request (size=\(frame.count))")
            self.sendTR4ACommandWithBreak(frame, peripheral: p, write: write)
        }
        timer.resume()
        tr4aPollTimer = timer
    }

    func stopTR4APolling() {
        tr4aPollTimer?.cancel()
        tr4aPollTimer = nil
        appendBLELog("TR4A polling timer cancelled")
    }

    /// TR4A「現在値取得(0x33/0x00)」SOHコマンドフレームを組み立てる。
    /// - Structure: SOH(0x01) + CMD(0x33) + SUB(0x00) + DataSize(0x0400) + Data(0x00000000) + CRC16-BE。
    /// - Note: ブレーク(0x00)は送信時に別 write として挟む。CRCはSOH以降を CCITT 初期値0xFFFF で計算。
    func buildTR4ACurrentValueCommand() -> Data {
        // データ長はリトルエンディアン 0x0400（=4byte）
        var frame = Data([0x01, 0x33, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00])
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    /// TR4Aコマンド送信の共通ユーティリティ（ブレーク→所定のSOHフレーム）。
    /// - Parameter delayMs: ブレーク後に挟むウェイト。仕様上20〜100msが推奨されるため、50msを既定値にしている。
    func sendTR4ACommandWithBreak(_ frame: Data, peripheral: CBPeripheral, write: CBCharacteristic, delayMs: Int = 50) {
        guard peripheral.state == .connected else { return }

        let writeType = preferredWriteType(for: write)
        appendBLELog("→ BREAK 0x00 then command (delay=\(delayMs)ms, type=\(writeType == .withoutResponse ? "no-rsp" : "with-rsp"))")
        peripheral.writeValue(Data([0x00]), for: write, type: writeType)
        bleQueue.asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
            guard peripheral.state == .connected else { return }
            peripheral.writeValue(frame, for: write, type: writeType)
        }
    }

    /// TR4A 設定テーブル取得(0x85)の SOH コマンドを構築する。
    /// - Note: Data Length=0x0400, Data=0x00000000 固定で CRC16 を付与する。
    func buildTR4ASettingsRequestCommand() -> Data {
        var frame = Data([0x01, 0x85, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00])
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    /// TR4A 記録開始(0x3C)の SOH コマンドを構築する。
    /// - Parameter settingsTable: 64byte の設定テーブル。先頭2byteが記録間隔(秒,LE)。
    func buildTR4AStartCommand(settingsTable: Data) -> Data {
        var table = settingsTable
        if table.count < 64 {
            table.append(Data(repeating: 0x00, count: 64 - table.count))
        }

        var frame = Data([0x01, 0x3C, 0x00, 0x40, 0x00])
        frame.append(table.prefix(64))
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
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

    /// 0x85 応答など TR4A 固有の制御レスポンスを横取りし、設定変更ワークフローに反映する。
    func handleTR4AControlFramesIfNeeded(_ data: Data, peripheral: CBPeripheral) {
        guard activeProfile.requiresPollingForRealtime else { return }
        guard data.count >= 5, data[0] == 0x01 else { return }

        let command = data[1]
        let sub = data[2]
        let sizeLE = UInt16(data[3]) | (UInt16(data[4]) << 8)
        let payloadStart = 5
        let totalNeeded = payloadStart + Int(sizeLE) + 2 // payload + CRC16
        guard data.count >= totalNeeded else { return }

        if command == 0x85, (sub == 0x00 || sub == 0x80) {
            // 64byte の設定テーブルをキャッシュし、待機中の記録間隔更新があれば上書きする。
            let payload = data[payloadStart..<payloadStart + Int(sizeLE)]
            tr4aLatestSettingsTable = Data(payload.prefix(64))
            appendBLELog("← 0x85 settings table received (\(payload.count) bytes)")
            if let pending = tr4aPendingIntervalUpdateSeconds {
                applyTR4AIntervalUpdate(pending, using: peripheral)
            }
        }
    }

    /// 設定テーブルを使って記録間隔を書き換え、0x3C コマンドで TR4A に送信する。
    func applyTR4AIntervalUpdate(_ seconds: UInt16, using peripheral: CBPeripheral) {
        guard let write = writeChar, peripheral.state == .connected else { return }

        // 既存テーブルをベースに、先頭2byteを記録間隔（秒, LE）として書き換える。
        var table = tr4aLatestSettingsTable ?? Data(repeating: 0x00, count: 64)
        if table.count < 64 { table.append(Data(repeating: 0x00, count: 64 - table.count)) }
        table[0] = UInt8(seconds & 0xFF)
        table[1] = UInt8((seconds >> 8) & 0xFF)

        let frame = buildTR4AStartCommand(settingsTable: table)
        appendBLELog("→ Send 0x3C start w/interval=\(seconds)s (frame \(frame.count) bytes)")
        sendTR4ACommandWithBreak(frame, peripheral: peripheral, write: write)

        tr4aPendingIntervalUpdateSeconds = nil
        tr4aLatestSettingsTable = table
    }

    /// 書き込み可能な CBCharacteristic から、応答付き/なしのどちらで送信するかを選ぶ。
    /// - Note: TR4A の環境では iOS が properties に WriteWithoutResponse を広告しないケースがあるため、
    ///         応答なしを前提にすると「プロパティに含まれないため無視された」という警告が出る。
    ///         ここでは WriteWithoutResponse を優先しつつ、無い場合は withResponse へフェールバックする。
    func preferredWriteType(for characteristic: CBCharacteristic) -> CBCharacteristicWriteType {
        if characteristic.properties.contains(.writeWithoutResponse) {
            return .withoutResponse
        }
        // 安立機や一部の TR45 では応答付きのみ広告する場合があるため、withResponse で確実に送信する。
        return .withResponse
    }

    /// CBCharacteristicProperties のビットを読みやすい文字列へ変換するデバッグ用ユーティリティ。
    func describeProperties(_ properties: CBCharacteristicProperties) -> String {
        var flags: [String] = []
        if properties.contains(.notify) { flags.append("notify") }
        if properties.contains(.indicate) { flags.append("indicate") }
        if properties.contains(.write) { flags.append("write") }
        if properties.contains(.writeWithoutResponse) { flags.append("writeNR") }
        if properties.contains(.read) { flags.append("read") }
        if properties.contains(.authenticatedSignedWrites) { flags.append("signed") }
        return flags.isEmpty ? "-" : flags.joined(separator: "/")
    }

    /// 接続が切断されたときの共通リセット処理。
    /// - Parameters:
    ///   - resetState: true の場合は connectionState を idle へ戻す。外部が再接続を試みる際に利用。
    ///   - reason: UI ログ用の説明。
    func handleDisconnection(resetState: Bool, reason: String) {
        if let p = peripheral, p.state != .disconnected {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil; readChar = nil; writeChar = nil
        stopTR4APolling()
        tr4aLatestSettingsTable = nil
        tr4aPendingIntervalUpdateSeconds = nil
        if resetState {
            DispatchQueue.main.async { self.connectionState = .idle }
        }
        appendBLELog("Disconnected: \(reason)", level: .warning)
        print("[BLE] disconnected: \(reason)")
    }
}

// MARK: - CoreBluetooth delegates
extension BluetoothService: CBCentralManagerDelegate, CBPeripheralDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            appendBLELog("Central powered on; auto-start scanning")
            startScan()
        case .unauthorized:
            DispatchQueue.main.async { self.connectionState = .failed("Bluetooth permission denied") }
            appendBLELog("Bluetooth unauthorized", level: .error)
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover p: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        appendBLELog("Discovered \(p.name ?? "?") RSSI=\(RSSI)")
        scanner.handleDiscovery(peripheral: p, advertisementData: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        print("[BLE] connected to \(p.name ?? "?")")
        appendBLELog("Connected to \(p.name ?? p.identifier.uuidString)")
        p.delegate = self
        connectionManager.didConnect(p)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // タイマーからのAPI MISUSEを防ぐため、CBPeripheral.state を確認して停止・掃除する。
        let message = error?.localizedDescription ?? "Disconnected"
        handleDisconnection(resetState: true, reason: message)
        DispatchQueue.main.async { self.connectionState = .failed(message) }
        appendBLELog("Did disconnect callback: \(message)", level: .warning)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect p: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.connectionState = .failed("Connect failed: \(error?.localizedDescription ?? "unknown")")
        }
        appendBLELog("Failed to connect: \(error?.localizedDescription ?? "unknown")", level: .error)
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
            appendBLELog("Notify error on \(characteristic.uuid): \(e.localizedDescription)", level: .error)
            return
        }
        print("[BLE] notify state \(characteristic.uuid): \(characteristic.isNotifying)")
        appendBLELog("Notify state \(characteristic.uuid) = \(characteristic.isNotifying)")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        appendBLELog("← Notify \(characteristic.uuid) (\(data.count) bytes)")
        handleTR4AControlFramesIfNeeded(data, peripheral: peripheral)
        notifyController.handleNotification(data)
    }
}
