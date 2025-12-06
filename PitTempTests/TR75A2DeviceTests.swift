import XCTest
import CoreBluetooth
@testable import PitTemp

final class TR75A2DeviceTests: XCTestCase {
    func testCRCMatchesSpecificationSample() {
        // 01 33 00 04 00 should yield CRC16 D1 A0 per the official doc samples.
        let frame = TR7A2CommandBuilder.buildFrame(command: 0x33,
                                                   expectedDataLength: 0x0004,
                                                   payload: Data([0x00]))
        let crcBytes = Array(frame.suffix(2))
        XCTAssertEqual(crcBytes, [0xD1, 0xA0])
    }

    func testResponseParsingEmitsChannelTemperatures() {
        let device = TR75A2Device()
        let characteristic = CBMutableCharacteristic(type: CBUUID(string: "6e400008-b5a3-f393-e0a9-e50e24dcca42"),
                                                     properties: [.notify],
                                                     value: nil,
                                                     permissions: [.readable])

        // Build a fake 0x33 ACK response with Ch1=25.0℃ (raw=1250) and Ch2=30.0℃ (raw=1300).
        var responseWithoutCRC = Data([0x01, 0x33, 0x06, 0x00, 0x04, 0xE2, 0x04, 0x14, 0x05])
        let crc = TR7A2CommandBuilder.crc16CCITT(responseWithoutCRC)
        responseWithoutCRC.append(UInt8((crc >> 8) & 0xFF))
        responseWithoutCRC.append(UInt8(crc & 0xFF))

        var captured: [TemperatureFrame] = []
        device.onFrame = { frame in captured.append(frame) }

        // Default channel (Ch1)
        device.didUpdateValue(for: characteristic, data: responseWithoutCRC)
        XCTAssertEqual(captured.last?.value, 25.0)

        // Switch to Ch2 and ensure the parser surfaces the second channel.
        device.setInputChannel(2)
        device.didUpdateValue(for: characteristic, data: responseWithoutCRC)
        XCTAssertEqual(captured.last?.value, 30.0)
    }
}
