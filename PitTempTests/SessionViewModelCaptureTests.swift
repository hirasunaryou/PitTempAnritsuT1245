import XCTest
@testable import PitTemp

@MainActor
final class SessionViewModelCaptureTests: XCTestCase {
    func testTapCellUpdatesCurrentWheelAndZone() {
        let fixtures = MeasureViewPreviewFixtures()
        let viewModel = fixtures.viewModel

        XCTAssertNil(viewModel.currentWheel)
        XCTAssertNil(viewModel.currentZone)
        XCTAssertFalse(viewModel.isCaptureActive)

        viewModel.tapCell(wheel: .FL, zone: .OUT)

        XCTAssertEqual(viewModel.currentWheel, .FL)
        XCTAssertEqual(viewModel.currentZone, .OUT)
        XCTAssertTrue(viewModel.isCaptureActive)

        viewModel.stopAll()
    }

    func testTapCellSwitchesHighlightBetweenWheels() {
        let fixtures = MeasureViewPreviewFixtures()
        let viewModel = fixtures.viewModel

        viewModel.tapCell(wheel: .FL, zone: .OUT)
        XCTAssertEqual(viewModel.currentWheel, .FL)

        viewModel.tapCell(wheel: .RR, zone: .IN)
        XCTAssertEqual(viewModel.currentWheel, .RR)
        XCTAssertEqual(viewModel.currentZone, .IN)

        viewModel.stopAll()
    }

    func testTapCellStopsWhenTappedAgain() {
        let fixtures = MeasureViewPreviewFixtures()
        let viewModel = fixtures.viewModel

        viewModel.tapCell(wheel: .FL, zone: .OUT)
        XCTAssertTrue(viewModel.isCaptureActive)

        viewModel.tapCell(wheel: .FL, zone: .OUT)
        XCTAssertFalse(viewModel.isCaptureActive)
    }
}
