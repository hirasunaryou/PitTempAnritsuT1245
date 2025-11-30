import Foundation
import CoreBluetooth

/// TR45 (TR4 シリーズ) 専用の分割コマンド実装。
final class TR4Device: ThermometerDevice {
    let peripheral: CBPeripheral
    let name: String
    let identifier: String
    let profile: BLEDeviceProfile = .tr45

    var onReady: ((CBCharacteristic?, CBCharacteristic?) -> Void)?
    var onTemperature: ((TemperatureFrame) -> Void)?
    var onFailed: ((String) -> Void)?
    var onNotifyCount: ((Int) -> Void)?
    var onNotifyHz: ((Double) -> Void)?

    private let logger = Logger.shared

    private var headerWrite: CBCharacteristic?
    private var dataWrite: CBCharacteristic?
    private var headerNotify: CBCharacteristic?
    private var dataNotify: CBCharacteristic?

    private var inboundBuffer = Data()
    private var expectedLength: Int?

    private var notifyCountBG: Int = 0
    private var prevNotifyAt: Date?
    private var emaInterval: Double?
    private let emaAlpha = 0.25

    private let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca42")
    private let headerWriteUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca42")
    private let dataWriteUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca42")
    private let headerNotifyUUID = CBUUID(string: "6e400005-b5a3-f393-e0a9-e50e24dcca42")
    private let dataNotifyUUID = CBUUID(string: "6e400006-b5a3-f393-e0a9-e50e24dcca42")

    init(peripheral: CBPeripheral, name: String) {
        self.peripheral = peripheral
        self.name = name
        self.identifier = peripheral.identifier.uuidString
    }

    func connect(using central: CBCentralManager) {
        central.connect(peripheral, options: nil)
    }

    func startMeasurement() {
        guard let headerWrite, let dataWrite else { return }
        sendCurrentValueCommand(headerWrite: headerWrite, dataWrite: dataWrite)
    }

    func disconnect(using central: CBCentralManager) { }

    func didDiscoverServices(error: Error?) {
        if let e = error { onFailed?("Service discovery: \(e.localizedDescription)"); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            onFailed?("TR45 service not found")
            return
        }
        let targets = [headerWriteUUID, dataWriteUUID, headerNotifyUUID, dataNotifyUUID]
        peripheral.discoverCharacteristics(targets, for: service)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        if let e = error { onFailed?("Char discovery: \(e.localizedDescription)"); return }
        service.characteristics?.forEach { ch in
            switch ch.uuid {
            case headerWriteUUID: headerWrite = ch
            case dataWriteUUID: dataWrite = ch
            case headerNotifyUUID:
                headerNotify = ch; peripheral.setNotifyValue(true, for: ch)
            case dataNotifyUUID:
                dataNotify = ch; peripheral.setNotifyValue(true, for: ch)
            default: break
            }
        }
        onReady?(headerNotify, headerWrite)
    }

    func didUpdateValue(for characteristic: CBCharacteristic, data: Data) {
        updateNotifyMetrics()
        switch characteristic.uuid {
        case headerNotifyUUID:
            handleHeader(data)
        case dataNotifyUUID:
            handleDataBlock(data)
        default:
            break
        }
    }
}

private extension TR4Device {
    func sendCurrentValueCommand(headerWrite: CBCharacteristic, dataWrite: CBCharacteristic) {
        let base = buildBaseCommand()
        let wrapped = wrapIn9F(base)
        let fragments = splitForTR45(payload: wrapped)

        peripheral.writeValue(fragments.header, for: headerWrite, type: .withResponse)
        logger.log("TR45 header send: \(fragments.header.hexEncodedString())", category: .bleTx)
        peripheral.writeValue(fragments.body1, for: dataWrite, type: .withResponse)
        logger.log("TR45 body#0 send: \(fragments.body1.hexEncodedString())", category: .bleTx)
        peripheral.writeValue(fragments.body2, for: dataWrite, type: .withResponse)
        logger.log("TR45 body#1 send: \(fragments.body2.hexEncodedString())", category: .bleTx)
    }

    func buildBaseCommand() -> Data {
        var frame = Data([0x01, 0x33, 0x00, 0x04, 0x00])
        frame.append(contentsOf: [UInt8](repeating: 0x00, count: 4))
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    func wrapIn9F(_ base: Data) -> Data {
        var frame = Data([0x01, 0x9F, 0x00, 0x0F, 0x00])
        frame.append(contentsOf: [UInt8](repeating: 0x00, count: 4))
        frame.append(base)
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    func splitForTR45(payload: Data) -> (header: Data, body1: Data, body2: Data) {
        var header = Data([0x01, 0x01, 0x18, 0x00])
        header.append(contentsOf: [UInt8](repeating: 0x00, count: 17))

        let firstBodyChunk = payload.prefix(16)
        var body1 = Data([0x00, 0x00])
        body1.append(firstBodyChunk)

        let secondChunk = payload.dropFirst(firstBodyChunk.count)
        var body2 = Data([0x01, 0x00])
        body2.append(secondChunk)
        while body2.count < body1.count { body2.append(0x00) }

        return (header, body1, body2)
    }

    func handleHeader(_ data: Data) {
        logger.log("TR45 header notify: \(data.hexEncodedString())", category: .bleRx)
        if data.count >= 4 {
            let len = Int(data[2]) | (Int(data[3]) << 8)
            expectedLength = len
            inboundBuffer.removeAll(keepingCapacity: true)
        }
    }

    func handleDataBlock(_ data: Data) {
        logger.log("TR45 data notify: \(data.hexEncodedString())", category: .bleRx)
        guard data.count >= 2 else { return }
        inboundBuffer.append(data.dropFirst(2))
        if let expectedLength, inboundBuffer.count >= expectedLength {
            parseTemperature(from: inboundBuffer)
            inboundBuffer.removeAll()
            self.expectedLength = nil
        }
    }

    func parseTemperature(from payload: Data) {
        // 9F 包を開いて内側 SOH のデータ部を読む。
        guard payload.count >= 18 else { return }
        let innerStart = 9 // SOH(1) 9F(1) Sub(1) Len(2) Pass(4)
        guard payload.count > innerStart + 5 else { return }
        let dataLength = Int(UInt16(payload[innerStart + 3]) | (UInt16(payload[innerStart + 4]) << 8))
        let dataStart = innerStart + 5
        guard payload.count >= dataStart + dataLength else { return }
        let dataField = payload[dataStart..<dataStart + dataLength]
        guard dataField.count >= 2 else { return }

        let raw = Int16(bitPattern: UInt16(dataField[dataField.startIndex])
                        | (UInt16(dataField[dataField.startIndex + 1]) << 8))
        if raw == Int16(bitPattern: 0xEEEE) { return }
        let celsius = (Double(raw) - 1000.0) / 10.0
        let frame = TemperatureFrame(time: Date(), deviceID: 0, value: celsius, status: nil)
        onTemperature?(frame)
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

    func updateNotifyMetrics() {
        notifyCountBG &+= 1
        onNotifyCount?(notifyCountBG)
        let now = Date()
        if let prev = prevNotifyAt {
            let dt = now.timeIntervalSince(prev)
            if dt > 0 {
                if let ema = emaInterval {
                    emaInterval = ema * (1 - emaAlpha) + dt * emaAlpha
                } else { emaInterval = dt }
                if let iv = emaInterval, iv > 0 { onNotifyHz?(1.0 / iv) }
            }
        }
        prevNotifyAt = now
    }
}
