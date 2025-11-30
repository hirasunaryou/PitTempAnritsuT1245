import XCTest
@testable import PitTemp

final class TR4AProtocolTests: XCTestCase {
    func testEncodeAndDecodeRoundTrip() throws {
        let payload = Data([0x00, 0x10, 0x01])
        let encoded = TR4AProtocol.encode(command: .getCurrentValue, sequence: 0x01, payload: payload)
        XCTAssertEqual(encoded.first, 0x01)
        guard let decoded = TR4AProtocol.decode(encoded) else {
            XCTFail("Failed to decode frame")
            return
        }
        XCTAssertEqual(decoded.command, .getCurrentValue)
        XCTAssertEqual(decoded.sequence, 0x01)
        XCTAssertEqual(decoded.payload, payload)
        XCTAssertTrue(decoded.status.isAck)
    }

    func testAssemblerConcatenatesFragments() {
        let payload = Data([0x00, 0x01])
        let frame = TR4AProtocol.encode(command: .passcode, sequence: 0x02, payload: payload)
        let firstHalf = frame.prefix(4)
        let secondHalf = frame.suffix(from: 4)

        let assembler = TR4AAssembler()
        XCTAssertTrue(assembler.append(firstHalf).isEmpty)
        let frames = assembler.append(Data(secondHalf))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.command, .passcode)
    }

    func testBCDConversion() {
        let bytes = RegistrationCodeStore.bcdBytes(from: "74976167")
        XCTAssertEqual(bytes, [0x74, 0x97, 0x61, 0x67])
        XCTAssertNil(RegistrationCodeStore.bcdBytes(from: "12"))
    }
}
