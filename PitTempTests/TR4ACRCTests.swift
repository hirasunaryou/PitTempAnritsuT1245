import XCTest
@testable import PitTemp

final class TR4ACRCTests: XCTestCase {
    func testXmodemVectorsFromSpec() {
        // Example from TR4A spec: passcode 0x12345678 should yield CRC 0x0DBF.
        let samplePasscode = data(fromHex: "01 76 00 04 00 78 56 34 12")
        XCTAssertEqual(TR4ACRC.xmodem(samplePasscode), 0x0DBF)

        // Additional vectors observed in field logs to guard against regressions.
        let passcode74976167BCD = data(fromHex: "01 76 00 04 00 74 97 61 67")
        XCTAssertEqual(TR4ACRC.xmodem(passcode74976167BCD), 0x8C32)

        let currentValue = data(fromHex: "01 33 00 04 00 00 00 00 00")
        XCTAssertEqual(TR4ACRC.xmodem(currentValue), 0x632B)
    }

    func testRegistrationCodeParsingUsesBCD() {
        XCTAssertEqual(BluetoothService.parseTR4ARegistrationCode("74976167"), [0x74, 0x97, 0x61, 0x67])
        XCTAssertNil(BluetoothService.parseTR4ARegistrationCode("0x74976167"))
        XCTAssertNil(BluetoothService.parseTR4ARegistrationCode(""))
    }

    func testPasscodeFrameBuildingMatchesSpec() {
        let frame = BluetoothService.buildTR4APasscodeFrame(passcodeBCD: [0x74, 0x97, 0x61, 0x67])
        XCTAssertEqual(frame, data(fromHex: "01 76 00 04 00 74 97 61 67 32 8C"))
    }

    // MARK: - Helpers
    private func data(fromHex hex: String) -> Data {
        let cleaned = hex.replacingOccurrences(of: " ", with: "")
        var bytes = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<nextIndex]
            bytes.append(UInt8(byteString, radix: 16)!)
            index = nextIndex
        }
        return bytes
    }
}
