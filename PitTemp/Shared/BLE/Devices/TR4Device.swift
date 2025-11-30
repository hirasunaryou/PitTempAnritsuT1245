//  TR4Device.swift
//  PitTemp
//  Role: T&D TR45(TR4シリーズ)の独自パケット送受信を実装するデバイスクラス。

import Foundation
import CoreBluetooth

/// TR4/TR45向けのBLEデバイス実装（9Fラップ + パケット分割対応）
final class TR4Device: NSObject, ThermometerDevice {
    let profile: BLEDeviceProfile = .tr4a
    weak var peripheral: CBPeripheral?
    var onReady: ((CBPeripheral) -> Void)?
    var onFrame: ((TemperatureFrame) -> Void)?
    var onFailure: ((String) -> Void)?

    // UUID定義（仕様書準拠）
    private let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca42")
    private let writeHeaderUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca42")
    private let writeDataUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca42")
    private let notifyHeaderUUID = CBUUID(string: "6e400005-b5a3-f393-e0a9-e50e24dcca42")
    private let notifyDataUUID = CBUUID(string: "6e400006-b5a3-f393-e0a9-e50e24dcca42")

    private var headerWriteChar: CBCharacteristic?
    private var dataWriteChar: CBCharacteristic?
    private var headerNotifyChar: CBCharacteristic?
    private var dataNotifyChar: CBCharacteristic?

    // 受信バッファ
    private var expectedLength: Int = 0
    private var assembledPayload = Data()

    func didConnect(_ peripheral: CBPeripheral) {
        Logger.shared.log("TR4 didConnect: discovering service", category: .system)
        peripheral.discoverServices([serviceUUID])
    }

    func didDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        if let e = error { onFailure?("Service discovery: \(e.localizedDescription)"); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            Logger.shared.log("TR4 service not found yet", category: .system)
            return
        }
        let chars = [writeHeaderUUID, writeDataUUID, notifyHeaderUUID, notifyDataUUID]
        peripheral.discoverCharacteristics(chars, for: service)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        if let e = error { onFailure?("Char discovery: \(e.localizedDescription)"); return }
        service.characteristics?.forEach { ch in
            switch ch.uuid {
            case writeHeaderUUID: headerWriteChar = ch
            case writeDataUUID: dataWriteChar = ch
            case notifyHeaderUUID: headerNotifyChar = ch
            case notifyDataUUID: dataNotifyChar = ch
            default: break
            }
        }
        guard let peripheral = service.peripheral else { return }
        if let header = headerNotifyChar { peripheral.setNotifyValue(true, for: header) }
        if let data = dataNotifyChar { peripheral.setNotifyValue(true, for: data) }
        Logger.shared.log("TR4 notify enabled header: \(String(describing: headerNotifyChar?.uuid)), data: \(String(describing: dataNotifyChar?.uuid))", category: .system)
        onReady?(peripheral)
    }

    func startMeasurement() {
        guard let p = peripheral, let header = headerWriteChar, let data = dataWriteChar else {
            Logger.shared.log("TR4 startMeasurement skipped (chars not ready)", category: .system)
            return
        }
        // 1) 基本SOHデータ
        let base = buildBaseCommand()
        // 2) 9F ラップ
        let wrapped = wrapWith9F(base)
        // 3) パケット分割送信
        let packets = fragment(wrapped)
        Logger.shared.log("TR4 TX header → \(hexString(packets.header))", category: .bleTx)
        p.writeValue(packets.header, for: header, type: .withResponse)
        Logger.shared.log("TR4 TX body0 → \(hexString(packets.body0))", category: .bleTx)
        p.writeValue(packets.body0, for: data, type: .withResponse)
        Logger.shared.log("TR4 TX body1 → \(hexString(packets.body1))", category: .bleTx)
        p.writeValue(packets.body1, for: data, type: .withResponse)
    }

    func didReceiveNotification(from characteristic: CBCharacteristic, data: Data) {
        Logger.shared.log("TR4 notify \(characteristic.uuid) ← \(hexString(data))", category: .bleRx)
        if characteristic.uuid == notifyHeaderUUID {
            expectedLength = data.count > 2 ? Int(data[2]) : 0
            assembledPayload.removeAll(keepingCapacity: true)
        } else if characteristic.uuid == notifyDataUUID {
            guard data.count > 2 else { return }
            let block = data[0]
            _ = block // ブロック番号が飛んだ場合の処理を今後追加しやすくするため保持
            let payloadSlice = data.dropFirst(2) // BlockNum(1) + Reserved(1) をスキップ
            assembledPayload.append(payloadSlice)
        }

        // ヘッダー情報がある場合、期待長を超えない範囲で評価
        if expectedLength > 0, assembledPayload.count >= expectedLength {
            parseResponse(assembledPayload)
            assembledPayload.removeAll()
            expectedLength = 0
        }
    }

    func disconnect(using central: CBCentralManager) {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        headerWriteChar = nil
        dataWriteChar = nil
        headerNotifyChar = nil
        dataNotifyChar = nil
        assembledPayload.removeAll()
        expectedLength = 0
    }
}

private extension TR4Device {
    /// SOH(0x01)+CMD(0x33)+Sub(0x00)+Len(0x04,0x00)+Data(0)4B+CRC2B
    func buildBaseCommand() -> Data {
        var frame = Data([0x01, 0x33, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00])
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    /// 9Fコマンドでラップし、パスワードやCRCを付与した22Bのフレームを作る。
    func wrapWith9F(_ base: Data) -> Data {
        var frame = Data()
        frame.append(0x01)        // SOH
        frame.append(0x9F)        // CMD
        frame.append(0x00)        // SUB
        frame.append(0x0F)        // LEN(15)
        frame.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Pass(4B)
        frame.append(base)
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    /// 3パケットに分割。ヘッダーは...0002、ボディは...0003へ送信する。
    func fragment(_ wrapped: Data) -> (header: Data, body0: Data, body1: Data) {
        var header = Data([0x01, 0x01, 0x18]) // Type, SubType, TotalLen(24)
        header.append(contentsOf: Array(repeating: UInt8(0x00), count: 17))

        var body0 = Data([0x00, 0x00]) // BlockNum=0, Reserved=0
        body0.append(wrapped.prefix(16))

        var body1 = Data([0x01, 0x00]) // BlockNum=1, Reserved=0
        body1.append(wrapped.dropFirst(16))
        while body1.count < 18 { body1.append(0x00) } // Padding
        return (header, body0, body1)
    }

    /// 受信済みペイロードをパースし、温度フレームへ変換する。
    func parseResponse(_ payload: Data) {
        // 9Fレスポンスの中に基本コマンドがそのまま返る前提で、Int16値を抽出する。
        // 仕様書上のData領域先頭2バイトをInt16(LE)として扱い、変換式を適用する。
        guard payload.count >= 6 else { return }

        let rawValue = Int16(bitPattern: UInt16(payload[4]) | (UInt16(payload[5]) << 8))
        if rawValue == Int16(bitPattern: 0xEEEE) { return }

        let value = (Double(rawValue) - 1000.0) / 10.0
        let frame = TemperatureFrame(time: Date(), deviceID: nil, value: value, status: nil)
        onFrame?(frame)
    }

    /// CRC16-CCITT(0x1021, 初期値0xFFFF)計算。
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
