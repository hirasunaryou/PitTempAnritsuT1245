import XCTest
@testable import PitTemp

/// NotifyController の Hz 平滑化ロジックを検証する。
/// HOLD 連打相当の短い間隔で通知が来た場合に、高い Hz を出せることを確認し、
/// 「連続モード検知」の前提となるメトリクス計測を固定化する。
final class NotifyControllerTests: XCTestCase {

    func testHzIsRaisedWhenNotificationsArriveBackToBack() async throws {
        let expectation = expectation(description: "Hz updates for continuous notifications")
        let controller = NotifyController(parser: TemperaturePacketParser(), mainQueue: DispatchQueue(label: "notify.test")) { _ in }
        controller.onHzUpdate = { hz in
            // 約0.12秒間隔なら 8Hz 付近。連続送信とみなせる閾値 3Hz 超を狙う。
            if hz > 3.0 { expectation.fulfill() }
        }

        let payload = Data("001+00010".utf8)
        controller.handleNotification(payload)
        try? await Task.sleep(nanoseconds: 120_000_000)
        controller.handleNotification(payload)

        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
