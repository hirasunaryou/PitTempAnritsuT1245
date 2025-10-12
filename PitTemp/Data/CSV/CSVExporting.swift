// PitTemp/Data/CSV/CSVExporting.swift

import Foundation

protocol CSVExporting {
    /// セッション集計CSVを出力してURLを返す
    func export(
        meta: MeasureMeta,
        results: [MeasureResult],
        wheelMemos: [WheelPos: String],
        sessionStart: Date
    ) throws -> URL
}
