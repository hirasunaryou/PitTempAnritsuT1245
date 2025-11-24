// PitTemp/Data/CSV/CSVExporting.swift
import Foundation

protocol CSVExporting {
    /// 旧形式（Library互換：1行=wheel、OUT/CL/INの3列）
    func exportWFlat(
        meta: MeasureMeta,
        results: [MeasureResult],
        wheelMemos: [WheelPos: String],
        wheelPressures: [WheelPos: Double],
        sessionStart: Date,
        deviceName: String?,
        deviceModelLabel: String?,
        sessionID: UUID,
        sessionReadableID: String,
        deviceIdentity: DeviceIdentity
    ) throws -> URL

    /// ライブ追記（任意実装）
    func appendLive(sample: TemperatureSample)
}
