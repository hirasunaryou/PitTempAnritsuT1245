//  SessionViewModelCaptureTests.swift
//  PitTempTests
//  Role: SessionViewModel の基本挙動（タップ遷移・ライブ値更新）を検証するユニットテスト。
//  Dependencies: Swift concurrency の MainActor とプレビュー用フィクスチャ。
//  Threading: MainActor で UI ステートを読むため、テストメソッドも @MainActor 指定。

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
        XCTAssertNil(viewModel.currentWheel)
        XCTAssertNil(viewModel.currentZone)
    }

    func testLiveTemperatureTracksLatestSample() {
        let fixtures = MeasureViewPreviewFixtures()
        let viewModel = fixtures.viewModel

        XCTAssertNil(viewModel.liveTemperatureC)

        let sample = TemperatureSample(time: Date(), value: 83.4)
        viewModel.ingestBluetoothSample(sample)

        XCTAssertEqual(viewModel.liveTemperatureC, 83.4, accuracy: 0.0001)
    }
}
