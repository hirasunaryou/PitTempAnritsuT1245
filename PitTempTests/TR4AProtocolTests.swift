import XCTest
@testable import PitTemp

final class TR4AProtocolTests: XCTestCase {
    func testEncodeCurrentValueCommandIncludesCRCAndBreak() {
        let data = TR4AFrameCodec.encode(command: .getCurrentValue, sequence: 0x01)
        let expected: [UInt8] = [0x00, 0x01, 0x33, 0x01, 0x00, 0x00, 0x3B, 0x58]
        XCTAssertEqual(data, Data(expected))
    }

    func testDecodeFrameWithPayload() {
        // 0xB3 = response to 0x33. Payload: status=ACK, type=0, ch=1, temp=0x04D2(12.34℃), state1=0x01, state2=0x04
        var buffer = Data([0x01, 0xB3, 0x02, 0x07, 0x00, 0x00, 0x00, 0x01, 0xD2, 0x04, 0x01, 0x04, 0xA6, 0xF5])
        let decoded = TR4AFrameCodec.decode(buffer: &buffer)
        XCTAssertTrue(decoded.errors.isEmpty)
        XCTAssertEqual(decoded.frames.count, 1)
        let frame = decoded.frames[0]
        XCTAssertEqual(frame.status, .ack)
        let payload = frame.decodeCurrentValue()
        XCTAssertEqual(payload?.channel, 1)
        XCTAssertEqual(payload?.temperatureC, 12.34)
        XCTAssertEqual(payload?.isRecording, true)
        XCTAssertEqual(payload?.isSecurityOn, true)
    }

    func testRegistrationCodeToBCD() throws {
        let bcd = try TR4ARegistrationCodeConverter.bcdBytes(from: "74976167")
        XCTAssertEqual(bcd, Data([0x74, 0x97, 0x61, 0x67]))
    }
}

