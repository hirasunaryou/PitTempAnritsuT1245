// PitTemp/Models/SessionFileContext.swift
import Foundation

/// Google Drive / iCloud とやり取りする際に必要なメタ情報を一塊にした DTO。
/// ViewModel からは `SessionFileContext.driveMetadata` を呼ぶだけで埋まるようにする。
struct DriveCSVMetadata: Codable, Equatable {
    var sessionID: UUID
    var sessionReadableID: String
    var driver: String
    var track: String
    var car: String
    var deviceID: String
    var deviceName: String
    var exportedAt: Date
    var sessionStartedAt: Date

    var dayFolderName: String {
        DateFormatter.cachedDayFormatter.string(from: sessionStartedAt)
    }
}

/// CSVExporter に渡す各種コンテキスト値をまとめた構造体。
/// `SessionFileCoordinator` と組み合わせることで、呼び出し側は DTO の生成だけに専念できる。
struct SessionFileContext {
    var meta: MeasureMeta
    var sessionID: UUID
    var sessionReadableID: String
    var sessionBeganAt: Date
    var deviceIdentity: DeviceIdentity
    var deviceName: String?

    func driveMetadata(exportedAt: Date) -> DriveCSVMetadata {
        DriveCSVMetadata(
            sessionID: sessionID,
            sessionReadableID: sessionReadableID,
            driver: meta.driver,
            track: meta.track,
            car: meta.car,
            deviceID: deviceIdentity.id,
            deviceName: deviceName ?? deviceIdentity.name,
            exportedAt: exportedAt,
            sessionStartedAt: sessionBeganAt
        )
    }
}
