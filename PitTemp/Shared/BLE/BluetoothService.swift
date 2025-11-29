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
    // TR4A 受信組み立て用バッファ（20byte刻みで飛んでくる notify を1フレームにまとめる）。
    private var tr4aReceiveBuffer = Data()
    // TR4A の登録コード（パスコード）。REFUSE(0x0F) 応答時に 0x76 で投げる。UInt32 を保持してビルド時のエンディアンミスを避ける。
    private var tr4aRegistrationCode: UInt32?
    private var tr4aAuthInFlight = false
    private var tr4aAuthSucceeded = false

    // Parser / UseCase（TR4AかAnritsuかでパースルートを変える。ログ連携のためParser参照も保持）
    private let temperatureUseCase: TemperatureIngesting
    private var parserForLogging: TemperaturePacketParser?

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
        // 既定の UseCase が TemperaturePacketParser を使っている場合、後でロガーを差し込めるよう参照を保持する。
        if let parserBacked = temperatureUseCase as? TemperatureIngestUseCase,
           let parser = parserBacked.parser as? TemperaturePacketParser {
            self.parserForLogging = parser
        } else if let parser = temperatureUseCase as? TemperaturePacketParser {
            // テストなどで直に parser を注入したケース。
            self.parserForLogging = parser
        }

        self.temperatureUseCase = temperatureUseCase
        super.init()
        parserForLogging?.logger = { [weak self] message in
            self?.appendBLELog("Parse: \(message)")
        }
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
        // TR4A/TD系では TIME コマンドの仕様が異なるため、Anritsu プロファイルのみで利用する。
        guard activeProfile == .anritsu else {
            appendBLELog("Skip time sync: not supported for profile \(activeProfile.key)")
            return
        }
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

    /// TR4A の登録コード（パスコード）を設定する。空文字や変換失敗時は解除として扱う。
    func setTR4ARegistrationCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tr4aRegistrationCode = nil
            tr4aAuthSucceeded = false
            appendBLELog("TR4A registration code cleared")
            return
        }

        // 「0x」付きは16進、それ以外は10進として受け付ける。UInt32 に収まらなければ無効。
        let normalized = trimmed.lowercased()
        let radix: Int = normalized.hasPrefix("0x") ? 16 : 10
        let digits = normalized.replacingOccurrences(of: "0x", with: "")

        guard let value = UInt32(digits, radix: radix) else {
            appendBLELog("Invalid TR4A registration code input: \(code)", level: .warning)
            return
        }

        tr4aRegistrationCode = value
        tr4aAuthSucceeded = false
        appendBLELog("TR4A registration code stored (radix=\(radix), digits=\(digits.count))")
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
            self.appendBLELog("Cache discovery: \(entry.name) profile=\(entry.profile.key) RSSI=\(entry.rssi)")
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
            // 初回接続時に時刻同期（必要なら Settings で ON/OFF 化）。
            // TR4A 系は TIME コマンド仕様が異なり、MTU 23 で 25Byte を一括送ると分割処理が必要になるため
            // 現段階では Anritsu プロファイルのみに限定する。TR4A に対応する場合は専用フォーマットで再実装すること。
            if self.activeProfile == .anritsu {
                self.setDeviceTime()
            }
            self.appendBLELog("Notify=\(read?.uuid.uuidString ?? "nil"), Write=\(write?.uuid.uuidString ?? "nil") selected")

            // 登録コードが設定されている場合、TR4A では最初に認証を飛ばしておくと REFUSE(0x0F) で足踏みしない。
            if self.activeProfile.requiresPollingForRealtime, let write, let pCode = self.tr4aRegistrationCode {
                self.sendTR4APasscodeIfNeeded(code: pCode, peripheral: peripheral, write: write, reason: "on-ready")
            }
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
                let props = self.describeProperties(c.properties)
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
        appendBLELog("Switch active profile → \(profile.key)")
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
        appendBLELog("→ BREAK 0x00 then command (delay=\(delayMs)ms, type=\(writeType == .withoutResponse ? "no-rsp" : "with-rsp")) frame=\(hexString(frame))")
        peripheral.writeValue(Data([0x00]), for: write, type: writeType)
        bleQueue.asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
            guard peripheral.state == .connected else { return }
            peripheral.writeValue(frame, for: write, type: writeType)
        }
    }

    /// 0x76 パスコード認証フレームを構築して送信する。UInt32 を LE で埋め込み、CRC16 はビッグエンディアン。
    func sendTR4APasscodeIfNeeded(code: UInt32, peripheral: CBPeripheral, write: CBCharacteristic, reason: String) {
        guard peripheral.state == .connected else { return }
        guard !tr4aAuthInFlight else { return }
        guard !tr4aAuthSucceeded else { return }

        var frame = Data([0x01, 0x76, 0x00, 0x04, 0x00])
        frame.append(UInt8(code & 0xFF))
        frame.append(UInt8((code >> 8) & 0xFF))
        frame.append(UInt8((code >> 16) & 0xFF))
        frame.append(UInt8((code >> 24) & 0xFF))
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))

        tr4aAuthInFlight = true
        appendBLELog("→ Send 0x76 passcode (reason=\(reason))")
        sendTR4ACommandWithBreak(frame, peripheral: peripheral, write: write)
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

    /// TR4A 通知チャンクを蓄積し、SOHフレーム単位で NotifyController へ橋渡しする。
    /// - Note: 解析途中で破棄されると現場デバッグが困難になるため、CRC/長さが不正な場合も警告としてログを残す。
    func processTR4ANotification(chunk: Data, peripheral: CBPeripheral) {
        tr4aReceiveBuffer.append(chunk)

        // SOH(0x01) が先頭に来るまで捨てる（初期ゴミ対策）。
        if let sohIndex = tr4aReceiveBuffer.firstIndex(of: 0x01), sohIndex > 0 {
            appendBLELog("Drop leading \(sohIndex)B before SOH: \(hexString(tr4aReceiveBuffer.prefix(sohIndex)))", level: .warning)
            tr4aReceiveBuffer.removeFirst(sohIndex)
        } else if tr4aReceiveBuffer.first != 0x01 {
            return
        }

        while tr4aReceiveBuffer.count >= 5 {
            let sizeLE = UInt16(tr4aReceiveBuffer[3]) | (UInt16(tr4aReceiveBuffer[4]) << 8)
            let totalNeeded = 5 + Int(sizeLE) + 2 // payload + CRC16

            if totalNeeded <= 0 || totalNeeded > 256 {
                appendBLELog("TR4A frame length invalid (len=\(sizeLE)); clearing buffer", level: .warning)
                tr4aReceiveBuffer.removeAll()
                return
            }

            guard tr4aReceiveBuffer.count >= totalNeeded else { return }

            let frame = tr4aReceiveBuffer.prefix(totalNeeded)
            tr4aReceiveBuffer.removeFirst(totalNeeded)
            processTR4AFrame(Data(frame), peripheral: peripheral)
        }
    }

    /// 1フレーム分の TR4A SOH 応答を解析し、設定処理とパースへ回す。
    func processTR4AFrame(_ frame: Data, peripheral: CBPeripheral) {
        // フレーム最小サイズに届いていない場合は hex を残して復帰。環境依存で断片的な notify が混じることがあるため。
        guard frame.count >= 5 else {
            appendBLELog("TR4A frame too small (\(frame.count)B): \(hexString(frame))", level: .warning)
            return
        }
        let command = frame[1]
        let status = frame[2]
        let sizeLE = UInt16(frame[3]) | (UInt16(frame[4]) << 8)
        let payloadStart = 5
        let payloadEnd = payloadStart + Int(sizeLE)
        guard frame.count >= payloadEnd + 2 else {
            appendBLELog(
                "TR4A frame truncated cmd=0x\(String(format: "%02X", command)) status=0x\(String(format: "%02X", status)) len=\(sizeLE) hex=\(hexString(frame))",
                level: .warning
            )
            return
        }

        let payload = frame[payloadStart..<payloadEnd]
        // CRC16-CCITT(0xFFFF init) を SOH〜payload までで検証する。CRC不一致でも hex を残し、現場で比較できるようにする。
        let receivedCRC = UInt16(frame[payloadEnd]) << 8 | UInt16(frame[payloadEnd + 1])
        let computedCRC = crc16CCITT(frame.prefix(payloadEnd))
        if receivedCRC != computedCRC {
            appendBLELog(
                "TR4A frame CRC/len invalid cmd=0x\(String(format: "%02X", command)) status=0x\(String(format: "%02X", status)) len=\(sizeLE) receivedCRC=0x\(String(format: "%04X", receivedCRC)) expectedCRC=0x\(String(format: "%04X", computedCRC)) hex=\(hexString(frame))",
                level: .warning
            )
            return
        }

        appendBLELog("Parsed TR4A frame cmd=0x\(String(format: "%02X", command)) status=0x\(String(format: "%02X", status)) len=\(sizeLE) payload=\(hexString(Data(payload)))")

        handleTR4AControlFramesIfNeeded(command: command, status: status, payload: Data(payload), peripheral: peripheral)
        notifyController.handleNotification(frame)
    }

    /// 0x85/0x3C など TR4A 固有の制御レスポンスを横取りし、設定変更ワークフローに反映する。
    func handleTR4AControlFramesIfNeeded(command: UInt8, status: UInt8, payload: Data, peripheral: CBPeripheral) {
        guard activeProfile.requiresPollingForRealtime else { return }

        if command == 0x33, status == 0x0F {
            appendBLELog("TR4A 0x33 REFUSE (status=0x0F). Registration code likely required.", level: .warning)
            tr4aAuthInFlight = false // 応答が返らず inFlight が張り付いた場合も再送できるようにする。
            if let write = writeChar, let code = tr4aRegistrationCode {
                sendTR4APasscodeIfNeeded(code: code, peripheral: peripheral, write: write, reason: "0x33 refused")
            } else {
                appendBLELog("Registration code not set; waiting for user input in Settings > Bluetooth", level: .warning)
            }
        }

        if command == 0x76 {
            tr4aAuthInFlight = false
            if status == 0x06 {
                tr4aAuthSucceeded = true
                appendBLELog("TR4A passcode accepted (0x76 ACK)")
            } else {
                tr4aAuthSucceeded = false
                appendBLELog("TR4A passcode rejected (status=0x\(String(format: "%02X", status)))", level: .warning)
            }
        }

        if command == 0x85, status == 0x06 {
            // 64byte の設定テーブルをキャッシュし、待機中の記録間隔更新があれば上書きする。
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

    /// デバッグ用に Data を16進文字列へ展開する簡易ユーティリティ。
    func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
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
        tr4aReceiveBuffer.removeAll()
        tr4aAuthInFlight = false
        tr4aAuthSucceeded = false
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
        appendBLELog("← Notify \(characteristic.uuid) (\(data.count) bytes): \(hexString(data))")

        // TR4A 系は20Bチャンクをまとめる必要があるため、専用バッファで組み立てる。
        if activeProfile.requiresPollingForRealtime {
            processTR4ANotification(chunk: data, peripheral: peripheral)
            return
        }

        notifyController.handleNotification(data)
    }
}
