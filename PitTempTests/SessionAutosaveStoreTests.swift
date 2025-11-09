import Foundation
import Testing
@testable import PitTemp

struct SessionAutosaveStoreTests {
    private enum TestError: Error { case writeFailed }

    @Test
    func saveFailureReportsToUILog() async throws {
        let logger = UILogSinkSpy()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SessionAutosaveStore(
            fileManager: FileManager.default,
            autosaveDirectory: tempDir,
            uiLogger: logger,
            dataWriter: { _, _ in throw TestError.writeFailed }
        )

        let snapshot = SessionSnapshot(
            meta: MeasureMeta(),
            results: [],
            wheelMemos: [:],
            wheelPressures: [:],
            sessionBeganAt: nil,
            sessionID: UUID(),
            originDeviceID: "TEST",
            originDeviceName: "Test Device"
        )

        store.save(snapshot)

        let entry = try #require(logger.entries.last)
        #expect(entry.level == .error)
        #expect(entry.category == .autosave)
        #expect(entry.message.contains("Failed to autosave session"))
    }
}

private final class UILogSinkSpy: UILogPublishing {
    private(set) var entries: [UILogEntry] = []

    func publish(_ entry: UILogEntry) {
        entries.append(entry)
    }
}
