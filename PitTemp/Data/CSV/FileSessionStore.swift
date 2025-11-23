// PitTemp/Data/CSV/FileSessionStore.swift
import Foundation

/// TemperatureSample の永続化を担う実装。ライブ追記を CSVExporter に委譲する。
final class FileSessionStore: SessionSampleStore {
    private var exporter: CSVExporting

    init(exporter: CSVExporting = CSVExporter()) {
        self.exporter = exporter
    }

    func append(_ sample: TemperatureSample) {
        exporter.appendLive(sample: sample)
    }

    func reset() {
        exporter = CSVExporter()
    }
}
