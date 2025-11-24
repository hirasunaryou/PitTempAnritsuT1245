import XCTest
@testable import PitTemp

private final class StubParser: TemperaturePacketParsing {
    var parsedData: Data?
    var timePayloadDate: Date?
    var framesToReturn: [TemperatureFrame] = []

    func parseFrames(_ data: Data) -> [TemperatureFrame] {
        parsedData = data
        return framesToReturn
    }

    func buildTIMESet(date: Date) -> Data {
        timePayloadDate = date
        return Data("TIME".utf8)
    }
}

final class TemperatureIngestUseCaseTests: XCTestCase {

    func testDelegatesParsingToParser() {
        let parser = StubParser()
        let useCase = TemperatureIngestUseCase(parser: parser)
        parser.framesToReturn = [TemperatureFrame(time: Date(), deviceID: 1, value: 12.3, status: nil)]

        let frames = useCase.frames(from: Data("RAW".utf8))

        XCTAssertEqual(parser.parsedData, Data("RAW".utf8))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.value, 12.3)
    }

    func testBuildsTimePayloadThroughParser() {
        let parser = StubParser()
        let useCase = TemperatureIngestUseCase(parser: parser)
        let date = Date(timeIntervalSince1970: 1)

        _ = useCase.makeTimeSyncPayload(for: date)

        XCTAssertEqual(parser.timePayloadDate, date)
    }
}
