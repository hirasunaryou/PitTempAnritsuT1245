import Foundation
import CoreBluetooth

/// TR4/TR45 シリーズのBLE実装。
/// - Note: TR45固有の9Fラップ + データフレーム分割をサンプルコード準拠で実装する。
final class TR4Device: ThermometerDevice {
    let profile: BLEDeviceProfile = .tr45
    weak var peripheral: CBPeripheral?
    var onFrame: ((TemperatureFrame) -> Void)?
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?

    // サービス/キャラクタリスティック
    private var headerWriteChar: CBCharacteristic?
    private var dataWriteChar: CBCharacteristic?
    private var notifyHeaderChar: CBCharacteristic?
    private var notifyDataChar: CBCharacteristic?
    private var responseChar: CBCharacteristic?

    // 送信用バッファ
    private var pendingBlocks: [Data] = []
    private var isSendingBlocks = false

    // 受信用バッファ
    private var expectedLength: Int = 0
    private var assembledPayload = Data()
    private var recvNextBlockNum: UInt16 = 0

    func connect(using central: CBCentralManager, to peripheral: CBPeripheral) {
        Logger.shared.log("Connecting to TR4/TR45", category: .ui)
        self.peripheral = peripheral
        peripheral.discoverServices([profile.serviceUUID])
    }

    func startMeasurement() {
        guard let peripheral, let headerWriteChar, let dataWriteChar else {
            onError?("TR4Device not ready for measurement")
            return
        }
        guard !isSendingBlocks else { return }

        let soh = buildBaseCommand()
        let nineF = wrapWith9F(soh)
        let framed = addDataFrameChecksum(nineF)
        let packets = fragment(framed)

        pendingBlocks = packets.blocks
        isSendingBlocks = true

        // ヘッダー送信（withResponse）。完了後 didWriteValue でブロックを流す。
        Logger.shared.log("TR4 TX header → \(packets.header.hexEncodedString())", category: .bleTx)
        peripheral.writeValue(packets.header, for: headerWriteChar, type: .withResponse)
    }

    func disconnect(using central: CBCentralManager?) {
        Logger.shared.log("Disconnecting TR4/TR45", category: .ui)
        pendingBlocks.removeAll()
        isSendingBlocks = false
        expectedLength = 0
        assembledPayload.removeAll()
        recvNextBlockNum = 0
        headerWriteChar = nil
        dataWriteChar = nil
        notifyHeaderChar = nil
        notifyDataChar = nil
        responseChar = nil
        peripheral = nil
    }

    func didDiscoverServices(peripheral: CBPeripheral, error: Error?) {
        if let e = error {
            onError?("Service discovery failed: \(e.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == profile.serviceUUID }) else {
            return
        }
        let characteristicUUIDs: [CBUUID] = [
            CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca42"), // dcmd write
            CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca42"), // ddat write
            CBUUID(string: "6e400005-b5a3-f393-e0a9-e50e24dcca42"), // ucmd notify
            CBUUID(string: "6e400006-b5a3-f393-e0a9-e50e24dcca42"), // udat notify
            CBUUID(string: "6e400007-b5a3-f393-e0a9-e50e24dcca42")  // ures write
        ]
        peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
    }

    func didDiscoverCharacteristics(for service: CBService, error: Error?) {
        if let e = error {
            onError?("Char discovery failed: \(e.localizedDescription)")
            return
        }

        service.characteristics?.forEach { ch in
            switch ch.uuid.uuidString.lowercased() {
            case "6e400002-b5a3-f393-e0a9-e50e24dcca42": headerWriteChar = ch
            case "6e400003-b5a3-f393-e0a9-e50e24dcca42": dataWriteChar = ch
            case "6e400005-b5a3-f393-e0a9-e50e24dcca42": notifyHeaderChar = ch
            case "6e400006-b5a3-f393-e0a9-e50e24dcca42": notifyDataChar = ch
            case "6e400007-b5a3-f393-e0a9-e50e24dcca42": responseChar = ch
            default: break
            }
        }

        if let nh = notifyHeaderChar { service.peripheral?.setNotifyValue(true, for: nh) }
        if let nd = notifyDataChar { service.peripheral?.setNotifyValue(true, for: nd) }

        if headerWriteChar != nil, dataWriteChar != nil, notifyHeaderChar != nil, notifyDataChar != nil, responseChar != nil {
            onReady?()
        }
    }

    func didUpdateValue(for characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        Logger.shared.log("TR4 RX ← \(data.hexEncodedString())", category: .bleRx)
        didReceiveNotification(from: characteristic.uuid, data: data)
    }

    func didWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        if let e = error {
            onError?("Write failed: \(e.localizedDescription)")
            isSendingBlocks = false
            pendingBlocks.removeAll()
            return
        }

        if characteristic.uuid.uuidString.lowercased() == "6e400002-b5a3-f393-e0a9-e50e24dcca42" {
            // ヘッダー送信完了。最初のデータブロックを送る。
            sendNextBlock()
        } else if characteristic.uuid.uuidString.lowercased() == "6e400003-b5a3-f393-e0a9-e50e24dcca42" {
            // 各ブロック送信完了で次のブロックを送る。
            sendNextBlock()
        }
    }
}

// MARK: - Private helpers
private extension TR4Device {
    func sendNextBlock() {
        guard let peripheral, let dataWriteChar else { return }
        guard !pendingBlocks.isEmpty else {
            isSendingBlocks = false
            return
        }
        let next = pendingBlocks.removeFirst()
        Logger.shared.log("TR4 TX body\(next.first ?? 0) → \(next.hexEncodedString())", category: .bleTx)
        peripheral.writeValue(next, for: dataWriteChar, type: .withResponse)
    }

    func didReceiveNotification(from uuid: CBUUID, data: Data) {
        let lower = uuid.uuidString.lowercased()
        if lower == "6e400005-b5a3-f393-e0a9-e50e24dcca42" {
            // Header
            Logger.shared.log("TR4 RX header ← \(data.hexEncodedString())", category: .bleRx)
            guard data.count >= 4 else { return }
            guard data[0] == 0x01, data[1] == 0x01 else { return }
            expectedLength = Int(UInt16(data[2]) | (UInt16(data[3]) << 8))
            recvNextBlockNum = 0
            assembledPayload.removeAll(keepingCapacity: true)
        } else if lower == "6e400006-b5a3-f393-e0a9-e50e24dcca42" {
            Logger.shared.log("TR4 RX data ← \(data.hexEncodedString())", category: .bleRx)
            guard data.count == 20 else { return }
            let blockNum = UInt16(data[0]) | (UInt16(data[1]) << 8)
            guard blockNum == recvNextBlockNum else { return }

            let from = 4
            let remaining = expectedLength - assembledPayload.count
            let to = min(from + remaining, data.count)
            if to > from {
                assembledPayload.append(contentsOf: data[from..<to])
            }
            recvNextBlockNum &+= 1

            if assembledPayload.count >= expectedLength, expectedLength > 0 {
                parseResponse(assembledPayload)
                expectedLength = 0
                assembledPayload.removeAll(keepingCapacity: true)
            }
        }
    }

    func parseResponse(_ payload: Data) {
        guard payload.count >= 3 else { return }
        let sumLo = payload[payload.count - 2]
        let sumHi = payload[payload.count - 1]
        let body = payload.dropLast(2)
        var calc: UInt16 = 0
        body.forEach { calc &+= UInt16($0) }
        let expectedSum = UInt16(sumLo) | (UInt16(sumHi) << 8)
        guard calc & 0xFFFF == expectedSum else {
            onError?("TR4 checksum mismatch")
            return
        }

        let nineF = body
        guard nineF.count >= 7 else { return }
        guard nineF[0] == 0x01, nineF[1] == 0x9F, nineF[2] == 0x06 else { return }

        let len = Int(UInt16(nineF[3]) | (UInt16(nineF[4]) << 8))
        let scmdRange = 5 ..< min(5 + len, nineF.count)
        guard scmdRange.count >= 7, scmdRange.upperBound <= nineF.count else { return }
        let scmd = nineF[scmdRange]
        guard scmd.count >= 7 else { return }
        guard scmd[0] == 0x01, scmd[1] == 0x33 else { return }

        let raw = UInt16(scmd[5]) | (UInt16(scmd[6]) << 8)
        if raw == 0xEEEE { return }

        let value = (Double(Int16(bitPattern: raw)) - 1000.0) / 10.0
        onFrame?(TemperatureFrame(time: Date(), deviceID: nil, value: value, status: nil))
        sendAck()
    }

    func sendAck() {
        guard let peripheral, let responseChar else { return }
        let ack = Data([0x01, 0x00, 0x00, 0x00])
        Logger.shared.log("TR4 TX ACK → \(ack.hexEncodedString())", category: .bleTx)
        peripheral.writeValue(ack, for: responseChar, type: .withResponse)
    }

    /// SOH(0x01) + 0x33 + Sub(0) + Len(0x04,0x00) + Data 4B + Checksum(sum LE)
    func buildBaseCommand() -> Data {
        var frame = Data([0x01, 0x33, 0x00, 0x04, 0x00])
        frame.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        let sum = frame.reduce(UInt16(0)) { $0 &+ UInt16($1) }
        frame.append(UInt8(sum & 0xFF))
        frame.append(UInt8((sum >> 8) & 0xFF))
        return frame
    }

    /// 9F コマンドでラップし CRC16-BE を付与する。
    func wrapWith9F(_ base: Data) -> Data {
        let len = UInt16(base.count + 4)
        var frame = Data([0x01, 0x9F, 0x00, UInt8(len & 0xFF), UInt8((len >> 8) & 0xFF), 0x00, 0x00, 0x00, 0x00])
        frame.append(base)
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    /// データフレーム用チェックサム(SUM)を末尾に付与する。
    func addDataFrameChecksum(_ frame: Data) -> Data {
        var sum: UInt16 = 0
        frame.forEach { sum &+= UInt16($0) }
        var result = frame
        result.append(UInt8(sum & 0xFF))
        result.append(UInt8((sum >> 8) & 0xFF))
        return result
    }

    /// ヘッダー + 16バイトチャンクに分割されたデータブロックへ変換。
    func fragment(_ sendData: Data) -> (header: Data, blocks: [Data]) {
        var header = Data([0x01, 0x01, UInt8(sendData.count & 0xFF), UInt8((sendData.count >> 8) & 0xFF)])
        header.append(Data(repeating: 0x00, count: 16))

        var blocks: [Data] = []
        let chunkSize = 16
        var offset = 0
        var blockNum: UInt16 = 0
        while offset < sendData.count {
            var frame = Data(repeating: 0x00, count: 20)
            frame[0] = UInt8(blockNum & 0xFF)
            frame[1] = UInt8((blockNum >> 8) & 0xFF)
            frame[2] = 0x00
            frame[3] = 0x00

            let upper = min(offset + chunkSize, sendData.count)
            let range = offset..<upper
            frame.replaceSubrange(4..<(4 + range.count), with: sendData[range])
            blocks.append(frame)
            offset += range.count
            blockNum &+= 1
        }

        return (header, blocks)
    }

    /// CCITT CRC16 (poly 0x1021, 初期値0) を計算する。
    func crc16CCITT(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0x0000
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
        return crc & 0xFFFF
    }
}
