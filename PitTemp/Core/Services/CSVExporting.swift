//
//  CSVExporting.swift
//  Core/Services
//
//  既存コード（MeasureMeta + [MeasureResult] + wheelMemos + sessionStart）に合わせたプロトコル
//

import Foundation

protocol CSVExporting {
    /// アプリ内のセッション情報からCSVを書き出し、保存先URLを返す
    func export(
        meta: MeasureMeta,
        results: [MeasureResult],
        wheelMemos: [WheelPos: String],
        sessionStart: Date
    ) throws -> URL
}
