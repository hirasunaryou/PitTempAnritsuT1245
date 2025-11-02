import Foundation
import Testing
@testable import PitTemp

@MainActor
struct SessionViewModelManualTests {

    @Test
    func manualCommitTriggersAutosaveSnapshot() async throws {
        let autosave = AutosaveStoreSpy()
        let settings = StubSettings()
        let vm = SessionViewModel(
            exporter: CSVExporterStub(),
            settings: settings,
            autosaveStore: autosave
        )

        let timestamp = Date(timeIntervalSince1970: 1_234_567)
        vm.commitManualValue(
            wheel: .FL,
            zone: .IN,
            value: 85.2,
            memo: "Manual memo",
            timestamp: timestamp
        )

        try await Task.sleep(nanoseconds: 400_000_000)

        let snapshot = try #require(autosave.savedSnapshots.last)
        #expect(snapshot.results.count == 1)

        let result = snapshot.results[0]
        #expect(result.wheel == .FL)
        #expect(result.zone == .IN)
        #expect(result.via == "manual")
        #expect(result.peakC == 85.2)
        #expect(result.startedAt == timestamp)
        #expect(result.endedAt == timestamp)

        #expect(snapshot.wheelMemos[.FL] == "Manual memo")
    }
}

private final class AutosaveStoreSpy: SessionAutosaveHandling {
    private(set) var savedSnapshots: [SessionSnapshot] = []

    func save(_ snapshot: SessionSnapshot) {
        savedSnapshots.append(snapshot)
    }

    func load() -> SessionSnapshot? { nil }

    func clear() {}

    func archiveLatest() {}
}

private struct StubSettings: SessionSettingsProviding {
    var validatedDurationSec: Int = 10
    var chartWindowSec: Double = 6
    var advanceWithGreater: Bool = false
    var advanceWithRightArrow: Bool = false
    var advanceWithReturn: Bool = true
    var minAdvanceSec: Double = 0.3
    var zoneOrderSequence: [Zone] = [.IN, .CL, .OUT]
    var autofillDateTime: Bool = false
}

private struct CSVExporterStub: CSVExporting {
    func exportWFlat(
        meta: MeasureMeta,
        results: [MeasureResult],
        wheelMemos: [WheelPos : String],
        sessionStart: Date,
        deviceName: String?
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try "stub".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func appendLive(sample: TemperatureSample) {}
}
