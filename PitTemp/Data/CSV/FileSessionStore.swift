// PitTemp/Data/CSV/FileSessionStore.swift
import Foundation

/// TemperatureSample の永続化を担う実装。ライブ追記を CSVExporter に委譲する。
///
/// - Note: ストリームの途中で `reset()` が呼ばれた場合は、新しい `CSVExporter`
///   インスタンスを丸ごと差し替えて「新規ファイルに書き出し直す」動きを明示する。
final class FileSessionStore: SessionSampleStore {
    /// 実際の I/O を握るコンポーネント。プロトコル経由で差し替え可能にしてテスト性を担保。
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
