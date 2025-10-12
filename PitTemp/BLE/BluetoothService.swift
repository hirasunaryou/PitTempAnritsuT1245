//
//  BluetoothService.swift
//  PitTemp
//

import Foundation
import CoreBluetooth
import Combine

/// BLEから温度を受け取り、DoubleとしてPublishするサービス。
final class BluetoothService: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case idle, scanning, connecting, ready, failed(String)
    }

    // 公開状態（UIは Main で触る）
    @Published var connectionState: ConnectionState = .idle
    @Published var latestTemperature: Double?
    @Published var deviceName: String?
    let temperatureStream = PassthroughSubject<TemperatureSample, Never>()

    // UUID（安立様仕様）
    private let serviceUUID   = CBUUID(string: "ada98080-888b-4e9f-9a7f-07ddc240f3ce")
    private let readCharUUID  = CBUUID(string: "ada98081-888b-4e9f-9a7f-07ddc240f3ce")  // Notify
    private let writeCharUUID = CBUUID(string: "ada98082-888b-4e9f-9a7f-07ddc240f3ce")  // Write

    // デバイス名フィルタ
    private let allowedNamePrefixes = ["AnritsuM-"]

    // CoreBluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var readChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?

    // 受信処理用の専用キュー
    private let bleQueue = DispatchQueue(label: "BLE.AnritsuT1245")

    // Parser
    private let parser = TemperaturePacketParser()

    // 追加
    private var autoPollOnReady = false
    private var wroteNotReadyCount = 0
    private var hasWrite: Bool { writeChar != nil }

    // ポーリングをRunLoopではなくGCDで
    private var pollSrc: DispatchSourceTimer?

    // 観測用カウンタ
    @Published var writeCount: Int = 0
    @Published var notifyCountUI: Int = 0  // UI表示用（Mainで増やす）
    private var notifyCountBG: Int = 0     // 実カウンタ（BGキュー）
    private var lastNotifyAt: Date?

    // 実測レート可視化
    @Published var notifyHz: Double = 0
    private var prevNotifyAt: Date?
    private var emaInterval: Double?   // 単位: 秒（指数移動平均）
    private let emaAlpha = 0.25        // 平滑係数

    // 自動チューニング用
    private var autoTuneSrc: DispatchSourceTimer?
    private var lastCountForAuto: Int = 0

    // 連続ストリーム検知後のクールダウン（この間はポーリング開始しない）
    private var streamModeUntil: Date?
    // 連続判定のヒステリシス用
    private var fastTicks = 0   // >=3Hz の秒が連続何回か
    private var slowTicks = 0   // < 2Hz の秒が連続何回か

    
    
    override init() {
        super.init()
        // 受信は専用キューで処理、UI更新だけ Main へ渡す
        central = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - Public API

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil; readChar = nil; writeChar = nil
        stopPolling()
        stopAutoTune()                             // ← 追加
        DispatchQueue.main.async { self.connectionState = .idle }
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        print("[BLE] connected to \(p.name ?? "?")")
        startAutoTune()                            // ← 追加
        p.delegate = self
        p.discoverServices(nil)
    }
    private func startAutoTune() {
        stopAutoTune()
        let src = DispatchSource.makeTimerSource(queue: bleQueue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let delta = self.notifyCountBG - self.lastCountForAuto
            self.lastCountForAuto = self.notifyCountBG
            let hz = max(0, delta)
            DispatchQueue.main.async { self.notifyHz = Double(hz) }

            // 直近が速い/遅いの連続カウント（ヒステリシス）
            if hz >= 3 { self.fastTicks += 1; self.slowTicks = 0 }
            else if hz < 2 { self.slowTicks += 1; self.fastTicks = 0 }
            else { self.fastTicks = 0; self.slowTicks = 0 }

            // 速い状態が続いたら「連続ストリーム」とみなして停止＆クールダウン3秒
            if self.fastTicks >= 2 {  // 連続2秒 >=3Hz で確定
                self.fastTicks = 0
                self.stopPolling()
                self.streamModeUntil = Date().addingTimeInterval(3.0)
                // print("[BLE] stream mode: stop polling (cooldown)")
            }

            // クールダウン中は開始しない
            if let until = self.streamModeUntil, Date() < until {
                return
            }

            // 遅い状態が続いたら 5Hz ポーリング開始
            if self.slowTicks >= 2 && self.pollSrc == nil && self.hasWrite {
                self.slowTicks = 0
                self.startPolling(hz: 5)
            }
        }
        src.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1), leeway: .milliseconds(50))
        autoTuneSrc = src
        src.activate()
    }

    private func stopAutoTune() {
        autoTuneSrc?.cancel()
        autoTuneSrc = nil
    }

    
    func startScan() {
        guard central.state == .poweredOn else { return }
        DispatchQueue.main.async { self.connectionState = .scanning }
        // アドバタイズにサービスを載せない端末も拾えるように全探索
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() { central.stopScan() }



    // 単発要求
    func requestOnce() {
        guard let p = peripheral, let w = writeChar else { return }
        let cmd = parser.buildDATARequest()
        let type: CBCharacteristicWriteType = w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.writeValue(cmd, for: w, type: type)
        DispatchQueue.main.async { self.writeCount &+= 1 }
    }


    // 時刻設定
    func setDeviceTime(to date: Date = Date()) {
        guard let p = peripheral, let w = writeChar else { return }
        let cmd = parser.buildTIMESet(date: date)
        print("[BLE] -> TIME \(hex(cmd))")
        p.writeValue(cmd, for: w, type: .withResponse)
    }

    // ポーリング開始/停止
    func startPolling(hz: Double = 5.0) {
        if hasWrite == false {
            autoPollOnReady = true
            print("[BLE] poll requested; will start when writeChar is ready")
            return
        }
        if pollSrc != nil { return } // 重複防止

        let interval = DispatchTimeInterval.milliseconds(Int(1000.0 / hz))
        let src = DispatchSource.makeTimerSource(queue: bleQueue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.requestOnce()
            // サイレンス監視（1.5秒以上受信なければログ）
            if let t = self.lastNotifyAt, Date().timeIntervalSince(t) > 1.5 {
                print("[BLE] watchdog: no notify > 1.5s")
            }
        }
        src.schedule(deadline: .now() + .milliseconds(200), repeating: interval, leeway: .milliseconds(20))
        pollSrc = src
        src.activate()
        print("[BLE] start polling GCD \(hz)Hz")
    }

    func stopPolling() {
        pollSrc?.cancel()
        pollSrc = nil
    }




    

    // MARK: - 小物
    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
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
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                   ?? p.name ?? "Unknown"
        guard allowedNamePrefixes.contains(where: { name.hasPrefix($0) }) else { return }
        stopScan()
        peripheral = p
        DispatchQueue.main.async {
            self.deviceName = name
            self.connectionState = .connecting
        }
        print("[BLE] found \(name), connecting…")
        central.connect(p, options: nil)
    }


    

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect p: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.connectionState = .failed("Connect failed: \(error?.localizedDescription ?? "unknown")")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error {
            DispatchQueue.main.async { self.connectionState = .failed("Service discovery: \(e.localizedDescription)") }
            return
        }
        let services = peripheral.services ?? []
        print("[BLE] services:", services.map { $0.uuid.uuidString })

        guard let svc = services.first(where: { $0.uuid == serviceUUID }) else {
            print("[BLE] target service not found yet")
            return
        }
        peripheral.discoverCharacteristics([readCharUUID, writeCharUUID], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let e = error {
            DispatchQueue.main.async { self.connectionState = .failed("Char discovery: \(e.localizedDescription)") }
            return
        }
        service.characteristics?.forEach { ch in
            if ch.uuid == readCharUUID { readChar = ch; peripheral.setNotifyValue(true, for: ch) }
            if ch.uuid == writeCharUUID { writeChar = ch }
        }
        wroteNotReadyCount = 0 // リセット
        if readChar != nil {
            DispatchQueue.main.async { self.connectionState = .ready }
        }
        if autoPollOnReady && hasWrite {
            autoPollOnReady = false
            startPolling(hz: 5)
        }
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

        // UIカウンタ
        DispatchQueue.main.async { self.notifyCountUI &+= 1 }

        // BGカウンタと時刻
        notifyCountBG &+= 1
        lastNotifyAt = Date()

        // インターバルとEMA（Hz表示の滑らか化）
        let now = Date()
        if let prev = prevNotifyAt {
            let dt = now.timeIntervalSince(prev)           // 秒
            if dt > 0 {
                if let ema = emaInterval {
                    emaInterval = ema * (1 - emaAlpha) + dt * emaAlpha
                } else {
                    emaInterval = dt
                }
                if let iv = emaInterval, iv > 0 {
                    let hz = 1.0 / iv
                    DispatchQueue.main.async { self.notifyHz = hz }
                }
            }
        }
        prevNotifyAt = now

        // HOLD（連続通知）検知：300ms未満なら連続モードと見なし、ポーリング停止
        if let prev = prevNotifyAt, now.timeIntervalSince(prev) < 0.30, pollSrc != nil {
            stopPolling()
            print("[BLE] continuous stream detected (HOLD). stop polling.")
        }

        // 解析 → UIへ
        let frames = parser.parseFrames(data)
        guard !frames.isEmpty else { return }
        DispatchQueue.main.async {
            for f in frames {
                self.latestTemperature = f.value
                self.temperatureStream.send(TemperatureSample(time: f.time, value: f.value))
            }
        }
    }


}
