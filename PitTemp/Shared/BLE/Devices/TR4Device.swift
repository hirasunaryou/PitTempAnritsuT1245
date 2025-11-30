import Foundation
import CoreBluetooth

/// TR45 (TR4シリーズ) の 0x33 現在値取得を実装した ThermometerDevice。
final class TR4Device: NSObject, ThermometerDevice {
    let profile: BLEDeviceProfile = .tr4
    let requiresPollingForRealtime: Bool = true

    private enum Constants {
        static let serviceUUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca42")
        static let headerWriteUUID = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca42")
        static let dataWriteUUID = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca42")
        // D 側の応答 (dres) も TR4 仕様では Notification を受け取る必要がある。
        static let dResponseUUID = CBUUID(string: "6e400004-b5a3-f393-e0a9-e50e24dcca42")
        static let headerNotifyUUID = CBUUID(string: "6e400005-b5a3-f393-e0a9-e50e24dcca42")
        static let dataNotifyUUID = CBUUID(string: "6e400006-b5a3-f393-e0a9-e50e24dcca42")
        static let responseUUID = CBUUID(string: "6e400007-b5a3-f393-e0a9-e50e24dcca42")
    }

    private var peripheral: CBPeripheral?
    private var headerWriteChar: CBCharacteristic?
    private var dataWriteChar: CBCharacteristic?
    // 送信結果を知らせる D 側レスポンス用 characteristic。
    private var dResponseChar: CBCharacteristic?
    private var headerNotifyChar: CBCharacteristic?
    private var dataNotifyChar: CBCharacteristic?
    private var responseChar: CBCharacteristic?

    private var sendQueue: [(Data, CBCharacteristic)] = []
    private var sendingIndex: Int = 0

    private var expectedLength: Int = 0
    private var assembledPayload = Data()
    private var recvNextBlockNum: UInt16 = 0

    var onFrame: ((TemperatureFrame) -> Void)?
    var onReady: (() -> Void)?

    // MARK: - ThermometerDevice
    func bind(peripheral: CBPeripheral) { self.peripheral = peripheral }

    func connect() {
        // TR45 では接続直後はサービス探索のみ行う。
    }

    func discoverCharacteristics(on peripheral: CBPeripheral, service: CBService) {
        let uuids: [CBUUID] = [Constants.headerWriteUUID,
                               Constants.dataWriteUUID,
                               Constants.dResponseUUID,
                               Constants.headerNotifyUUID,
                               Constants.dataNotifyUUID,
                               Constants.responseUUID]
        peripheral.discoverCharacteristics(uuids, for: service)
    }

    func didDiscoverCharacteristics(error: Error?) {
        guard error == nil else { return }
        guard let service = peripheral?.services?.first(where: { $0.uuid == Constants.serviceUUID }) else { return }

        service.characteristics?.forEach { ch in
            switch ch.uuid {
            case Constants.headerWriteUUID: headerWriteChar = ch
            case Constants.dataWriteUUID: dataWriteChar = ch
            case Constants.dResponseUUID: dResponseChar = ch
            case Constants.headerNotifyUUID: headerNotifyChar = ch
            case Constants.dataNotifyUUID: dataNotifyChar = ch
            case Constants.responseUUID: responseChar = ch
            default: break
            }
        }

        // TR4 仕様に従い、D レスポンス / U コマンド / U データの全てで Notification を有効化する。
        if let dres = dResponseChar { peripheral?.setNotifyValue(true, for: dres) }
        if let header = headerNotifyChar { peripheral?.setNotifyValue(true, for: header) }
        if let data = dataNotifyChar { peripheral?.setNotifyValue(true, for: data) }
        onReady?()
    }

    func didUpdateValue(for characteristic: CBCharacteristic, data: Data) {
        switch characteristic.uuid {
        case Constants.dResponseUUID:
            // D 側応答 (dres)。2 バイトでステータスを通知するので、成功時のみ静かに通過させる。
            Logger.shared.log("TR4 RX dres ← \(data.hexString)", category: .bleReceive)
            if !(data.count == 2 && data[0] == 0x01 && data[1] == 0x00) {
                // 送信エラー相当。今はログで気付けるようにする。
                Logger.shared.log("TR4 dres error status: \(data.hexString)", category: .bleReceive)
            }
        case Constants.headerNotifyUUID:
            Logger.shared.log("TR4 RX header ← \(data.hexString)", category: .bleReceive)
            guard data.count >= 4, data[0] == 0x01, data[1] == 0x01 else { return }
            expectedLength = Int(UInt16(low: data[2], high: data[3]))
            recvNextBlockNum = 0
            assembledPayload.removeAll(keepingCapacity: true)
        case Constants.dataNotifyUUID:
            Logger.shared.log("TR4 RX data ← \(data.hexString)", category: .bleReceive)
            guard data.count == 20, expectedLength > 0 else { return }
            let blockNum = UInt16(low: data[0], high: data[1])
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
            }
        default:
            // 想定外の characteristic から通知された場合もデバッグできるよう残す。
            Logger.shared.log("TR4 RX unknown (\(characteristic.uuid.uuidString)) ← \(data.hexString)", category: .bleReceive)
        }
    }

    func didWriteValue(for characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Logger.shared.log("TR4 write error: \(error.localizedDescription)", category: .bleSend)
        }
        sendingIndex += 1
        sendNextIfNeeded()
    }

    func setDeviceTime(_ date: Date) {
        // TR45 側では時刻同期コマンドの仕様が異なるため、ここでは送信しない。
    }

    func startMeasurement() {
        guard let header = headerWriteChar, let dataChar = dataWriteChar else { return }
        let soh = buildBaseCommand()
        let nineF = wrapWith9F(soh)
        let framed = addDataFrameChecksum(nineF)
        let packets = fragment(framed)

        sendQueue = []
        sendingIndex = 0
        if let first = packets.first {
            sendQueue.append((first, header))
            Logger.shared.log("TR4 TX header → \(first.hexString)", category: .bleSend)
        }
        for (index, body) in packets.dropFirst().enumerated() {
            sendQueue.append((body, dataChar))
            Logger.shared.log("TR4 TX body\(index) → \(body.hexString)", category: .bleSend)
        }
        sendNextIfNeeded()
    }

    func disconnect() {
        peripheral = nil
        headerWriteChar = nil
        dataWriteChar = nil
        dResponseChar = nil
        headerNotifyChar = nil
        dataNotifyChar = nil
        responseChar = nil
        sendQueue.removeAll()
        assembledPayload.removeAll()
        expectedLength = 0
        recvNextBlockNum = 0
    }

    // MARK: - Helpers
    private func sendNextIfNeeded() {
        guard sendingIndex < sendQueue.count else { return }
        let packet = sendQueue[sendingIndex]
        peripheral?.writeValue(packet.0, for: packet.1, type: .withResponse)
    }

    private func buildBaseCommand() -> Data {
        var frame = Data([0x01, 0x33, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00])
        let sum = frame.reduce(0) { $0 &+ UInt16($1) }
        frame.append(UInt8(sum & 0xFF))
        frame.append(UInt8((sum >> 8) & 0xFF))
        return frame
    }

    private func wrapWith9F(_ base: Data) -> Data {
        let len = UInt16(base.count + 4)
        var frame = Data([0x01, 0x9F, 0x00, UInt8(len & 0xFF), UInt8((len >> 8) & 0xFF), 0x00, 0x00, 0x00, 0x00])
        frame.append(base)
        let crc = crc16CCITT(frame)
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return frame
    }

    private func addDataFrameChecksum(_ frame: Data) -> Data {
        let sum = frame.reduce(0) { $0 &+ UInt16($1) }
        var newFrame = frame
        newFrame.append(UInt8(sum & 0xFF))
        newFrame.append(UInt8((sum >> 8) & 0xFF))
        return newFrame
    }

    private func fragment(_ sendData: Data) -> [Data] {
        var packets: [Data] = []
        var header = Data(count: 20)
        header[0] = 0x01
        header[1] = 0x01
        header[2] = UInt8(sendData.count & 0xFF)
        header[3] = UInt8((sendData.count >> 8) & 0xFF)
        packets.append(header)

        var blockNum: UInt16 = 0
        var offset = 0
        while offset < sendData.count {
            var frame = Data(count: 20)
            frame[0] = UInt8(blockNum & 0xFF)
            frame[1] = UInt8((blockNum >> 8) & 0xFF)
            frame[2] = 0x00
            frame[3] = 0x00
            let chunk = sendData.subdata(in: offset..<min(offset + 16, sendData.count))
            frame.replaceSubrange(4..<4 + chunk.count, with: chunk)
            packets.append(frame)
            offset += 16
            blockNum &+= 1
        }
        return packets
    }

    private func parseResponse(_ payload: Data) {
        guard payload.count >= 4 else { return }
        let sumLE = UInt16(low: payload[payload.count - 2], high: payload[payload.count - 1])
        let calcSum = payload.dropLast(2).reduce(0) { $0 &+ UInt16($1) } & 0xFFFF
        guard sumLE == calcSum else { return }

        let nineF = payload.dropLast(2)
        guard nineF.count >= 7 else { return }
        guard nineF[nineF.startIndex] == 0x01, nineF[nineF.startIndex + 1] == 0x9F, nineF[nineF.startIndex + 2] == 0x06 else { return }
        let len = Int(UInt16(low: nineF[nineF.startIndex + 3], high: nineF[nineF.startIndex + 4]))
        let sohRangeStart = nineF.startIndex + 5
        guard nineF.count >= sohRangeStart + len else { return }
        let scmd = nineF[sohRangeStart..<sohRangeStart + len]
        guard scmd.count >= 7, scmd[scmd.startIndex] == 0x01, scmd[scmd.startIndex + 1] == 0x33 else { return }
        let raw = UInt16(low: scmd[scmd.startIndex + 5], high: scmd[scmd.startIndex + 6])
        guard raw != 0xEEEE else { return }

        let value = (Double(Int16(bitPattern: raw)) - 1000.0) / 10.0
        onFrame?(TemperatureFrame(time: Date(), deviceID: nil, value: value, status: nil))

        if let resp = responseChar {
            var ack = Data(repeating: 0x00, count: 20)
            ack[0] = 0x01
            peripheral?.writeValue(ack, for: resp, type: .withResponse)
        }
    }

    private func crc16CCITT(_ data: Data) -> UInt16 {
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
        return crc
    }
}

private extension UInt16 {
    init(low: UInt8, high: UInt8) { self = UInt16(low) | (UInt16(high) << 8) }
}
