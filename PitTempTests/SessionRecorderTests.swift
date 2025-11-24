import Combine
import XCTest
@testable import PitTemp

/// SessionRecorder の境界挙動を検証するユニットテスト。
/// HOLD連打による連続サンプルと、ポーリング再開時のリセット動作をそれぞれ固定する。
final class SessionRecorderTests: XCTestCase {

    func testKeepsSlidingWindowDuringContinuousStream() {
        let store = StoreSpy()
        // maxKeep を小さくしてリングバッファ的な振る舞いを強制し、端数の落ち方を明確に確認する。
        let recorder = SessionRecorder(store: store, maxKeep: 3)
        let subject = PassthroughSubject<TemperatureSample, Never>()
        recorder.bind(to: subject.eraseToAnyPublisher())

        // HOLDによる高速連続送信を模した5件を流す。先頭2件はバッファから押し出されるはず。
        (0..<5).forEach { idx in
            let sample = TemperatureSample(time: Date(timeIntervalSince1970: Double(idx)), value: Double(idx))
            subject.send(sample)
        }

        // Main キューでの集約が終わるのを同期する。処理が走らないとサンプル配列が更新されないため。
        let drain = expectation(description: "drain main queue")
        DispatchQueue.main.async { drain.fulfill() }
        wait(for: [drain], timeout: 1.0)

        XCTAssertEqual(recorder.samples.count, 3, "最大保持数を超えた古いサンプルが捨てられる")
        XCTAssertEqual(recorder.samples.map { $0.value }, [2, 3, 4], "最新3件だけが残る")
        XCTAssertEqual(store.appended.count, 5, "永続層には連続送信分すべて落とし込む")
    }

    func testResetStopsFurtherRecordingForPollingResume() {
        let store = StoreSpy()
        let recorder = SessionRecorder(store: store, maxKeep: 5)
        let subject = PassthroughSubject<TemperatureSample, Never>()
        recorder.bind(to: subject.eraseToAnyPublisher())

        // 1件受信したあとポーリング（DATA 単発）運用に切り替える想定で reset。
        subject.send(TemperatureSample(time: Date(), value: 10.0))
        recorder.reset()
        subject.send(TemperatureSample(time: Date(), value: 20.0))

        let drain = expectation(description: "drain main queue")
        DispatchQueue.main.async { drain.fulfill() }
        wait(for: [drain], timeout: 1.0)

        XCTAssertTrue(recorder.samples.isEmpty, "reset 後はサンプル配列をクリアしておく")
        XCTAssertEqual(store.resetCallCount, 1, "永続層も新しいファイルに切り替える")
        XCTAssertTrue(store.appended.isEmpty, "購読解除により reset 後のノイズは反映しない")
    }
}

private final class StoreSpy: SessionSampleStore {
    private(set) var appended: [TemperatureSample] = []
    private(set) var resetCallCount = 0

    func append(_ sample: TemperatureSample) {
        appended.append(sample)
    }

    func reset() {
        resetCallCount += 1
        appended.removeAll()
    }
}
