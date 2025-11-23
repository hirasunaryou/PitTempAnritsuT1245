import XCTest
@testable import PitTemp

/// TemperaturePacketParser の振る舞いを固定するユニットテスト。
/// センサログには非ASCIIが混ざるため、ASCII抽出と符号・桁数の扱いを明示的に検証する。
final class TemperaturePacketParserTests: XCTestCase {

    func testExtractsFrameFromAsciiAfterFilteringNoise() {
        // 先頭にバイナリノイズ(0x00,0xFF)が付いた想定。ASCIIのみを拾えているかを確認。
        let bytes: [UInt8] = [0x00, 0xFF] + Array("001+00243".utf8) + [0x00]
        let frames = TemperaturePacketParser().parseFrames(Data(bytes))

        // deviceID=001, +24.3℃ が安全に抽出されることを期待。
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.deviceID, 1)
        XCTAssertEqual(frames.first?.value, 24.3, accuracy: 0.0001)
    }

    func testParsesStatusFlagsAlongsideSignedValue() {
        // 符号付き温度とステータス文字列（B-OUT）が含まれるパケットの例。
        let data = Data("099-00000B-OUT".utf8)
        let frames = TemperaturePacketParser().parseFrames(data)

        // deviceID=99（直前の数字列）、温度は -0.0℃、ステータスは .bout になる。
        XCTAssertEqual(frames.first?.deviceID, 99)
        XCTAssertEqual(frames.first?.value, -0.0, accuracy: 0.0001)
        XCTAssertEqual(frames.first?.status, .bout)
    }

    func testIgnoresTooShortAsciiPayload() {
        // ASCII 断片が 8 バイト未満の場合はフレームにしない安全側の挙動。
        let frames = TemperaturePacketParser().parseFrames(Data("12".utf8))
        XCTAssertTrue(frames.isEmpty)
    }
}
