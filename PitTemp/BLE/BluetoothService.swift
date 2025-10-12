//
//  BluetoothService.swift
//  PitTemp
//

import Foundation
import CoreBluetooth
import Combine

/// BLEから温度を受け取り、DoubleとしてPublishするサービス
final class BluetoothService: NSObject, ObservableObject {

    enum ConnectionState: Equatable {
        case idle, scanning, connecting, ready, failed(String)
    }

    // 公開状態（UI側は Main スレッド）
    @Published var connectionState: ConnectionState = .idle
    @Published var latestTemperature: Double?
    @Published var deviceName: String?

    // 可視化用
    @Published var writeCount: Int = 0
    @Published var notifyCountUI: Int = 0
    @Published var notifyHz: Double = 0

    /// VMへ橋渡し
    let temperatureStream = PassthroughSubject<TemperatureSample, Never>()

    // UUID（安立仕様）
    private let serviceUUID   = CBUUID(string: "ada98080-888b-4e9f-9a7f-07ddc240f3ce")
    private let readCharUUID  = CBUUID(string: "ada98081-888b-4e9f-9a7f-07ddc240f3ce")  // Notify
    private let writeCharUUID = CBUUID(string: "ada98082-888b-4e9f-9a7f-07ddc240f3ce")  // Write

    // フィルタ
    private let allowedNamePrefixes = ["AnritsuM-"]

    // CoreBluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var readChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?

    // 受信処理は専用キュー
    private let bleQueue = DispatchQueue(label: "BLE.AnritsuT1245")

    // Parser
    private let parser = TemperaturePacketParser()

    // 書き込み可否
    private var hasWrite: Bool { writeChar != nil }

    // ポーリング（GCD）
    private var pollSrc: DispatchSourceTimer?

    // Notify計測
    private var notifyCountBG = 0
    private var lastNotifyAt: Date?
    private var emaInterval: Double?
    private let emaAlpha = 0.25

    // 自動判定（HOLD連続/ポーリング）用
    private var autoSrc: DispatchSourceTimer?
    private var lastCountForAuto = 0
    private var streamModeUntil: Date?
    private var fastTicks = 0
    private var slowTicks = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - Public

    func startScan() {
        guard central.state == .poweredOn else { return }
        DispatchQueue.main.async { self.connectionState = .scanning }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() { central.stopScan() }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil; readChar = nil; writeChar = nil
        stopPolling(); stopAuto()
        DispatchQueue.main.async { self.connectionState = .idle }
    }

    func requestOnce() {
        guard let p = peripheral, let w = writeChar else { return }
        let cmd = parser.buildDATARequest()
        let type: CBCharacteristicWriteType = w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        p.writeValue(cmd, for: w, type: type)
        DispatchQueue.main.async { self.writeCount &+= 1 }
    }

    func setDeviceTime(to date: Date = Date()) {
        guard let p = peripheral, let w = writeChar else { return }
        let cmd = parser.buildTIMESet(date: date)
        p.writeValue(cmd, for: w, type: .withResponse)
    }

    func startPolling(hz: Double = 5.0) {
        guard hasWrite else { return }
        if pollSrc != nil { return }
        let intervalMs = max(1, Int(1000.0 / hz))
        let src = DispatchSource.makeTimerSource(queue: bleQueue)
        src.schedule(deadline: .now() + .milliseconds(200),
                     repeating: .milliseconds(intervalMs),
                     leeway: .milliseconds(20))
        src.setEventHandler { [weak self] in
            guard let self else { return }
            self.requestOnce()
            if let t = self.lastNotifyAt, Date().timeIntervalSince(t) > 1.5 {
                print("[BLE] watchdog: no notify > 1.5s")
            }
        }
        pollSrc = src
        src.activate()
        print("[BLE] start polling \(hz)Hz")
    }

    func stopPolling() {
        pollSrc?.cancel()
        pollSrc = nil
    }

    // MARK: - Auto (HOLD/ポーリング自動切替)

    private func startAuto() {
        stopAuto()
        let src = DispatchSource.makeTimerSource(queue: bleQueue)
        src.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1), leeway: .milliseconds(50))
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let delta = self.notifyCountBG - self.lastCountForAuto
            self.lastCountForAuto = self.notifyCountBG
            let hz = max(0, delta)
            DispatchQueue.main.async { self.notifyHz = Double(hz) }

            if hz >= 3 { self.fastTicks += 1; self.slowTicks = 0 }
            else if hz < 2 { self.slowTicks += 1; self.fastTicks = 0 }
            else { self.fastTicks = 0; self.slowTicks = 0 }

            if self.fastTicks >= 2 {
                self.fastTicks = 0
                self.stopPolling()
                self.streamModeUntil = Date().addingTimeInterval(3.0) // クールダウン
            }

            if let until = self.streamModeUntil, Date() < until { return }

            if self.slowTicks >= 2 && self.pollSrc == nil && self.hasWrite {
                self.slowTicks = 0
                self.startPolling(hz: 5)
            }
        }
        autoSrc = src
        src.activate()
    }

    private func stopAuto() {
        autoSrc?.cancel()
        autoSrc = nil
    }
}

// MARK: - CoreBluetooth
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

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        print("[BLE] connected to \(p.name ?? "?")")
        p.delegate = self
        p.discoverServices(nil) // まず全部
        startAuto()
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
        guard let services = peripheral.services, !services.isEmpty else { return }
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
        if readChar != nil {
            DispatchQueue.main.async { self.connectionState = .ready }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
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

        // BGカウンタ & 時刻
        notifyCountBG &+= 1
        let now = Date()
        lastNotifyAt = now

        // EMAでHzを滑らかに
        if let prev = emaInterval {
            // prevは平均間隔(s)
            let dt = max(0.0, now.timeIntervalSinceNow + prev) // 安全側に
            let new = prev * (1 - emaAlpha) + dt * emaAlpha
            emaInterval = new
            if new > 0 { DispatchQueue.main.async { self.notifyHz = 1.0 / new } }
        } else {
            emaInterval = 0.3
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
