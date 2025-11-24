// PitTemp/Models/SessionFileContext.swift
import Foundation

/// Google Drive / iCloud とやり取りする際に必要なメタ情報を一塊にした DTO。
/// ViewModel からは `SessionFileContext.driveMetadata` を呼ぶだけで埋まるようにする。
// Hashable を追加して、待ち行列の重複防止などで集合系の API にそのまま載せられるようにする。
// Date や UUID は Hashable に準拠しているので、派生するハッシュ実装も安全に自動生成される。
struct DriveCSVMetadata: Codable, Equatable, Hashable {
    var sessionID: UUID
    var sessionReadableID: String
    var driver: String
    var track: String
    var car: String
    var deviceID: String
    var deviceFolderName: String
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
    var deviceModelLabel: String?

    func driveMetadata(exportedAt: Date) -> DriveCSVMetadata {
        DriveCSVMetadata(
            sessionID: sessionID,
            sessionReadableID: sessionReadableID,
            driver: meta.driver,
            track: meta.track,
            car: meta.car,
            deviceID: deviceIdentity.id,
            deviceFolderName: CSVExporter.deviceDirectoryName(
                deviceIdentity: deviceIdentity,
                deviceName: deviceName,
                deviceModelLabel: deviceModelLabel
            ),
            deviceName: deviceName ?? deviceIdentity.name,
            exportedAt: exportedAt,
            sessionStartedAt: sessionBeganAt
        )
    }
}
