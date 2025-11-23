// PitTemp/Models/SessionFileContext.swift
import Foundation

struct DriveCSVMetadata: Codable, Equatable {
    var sessionID: UUID
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

struct SessionFileContext {
    var meta: MeasureMeta
    var sessionID: UUID
    var sessionBeganAt: Date
    var deviceIdentity: DeviceIdentity
    var deviceName: String?

    func driveMetadata(exportedAt: Date) -> DriveCSVMetadata {
        DriveCSVMetadata(
            sessionID: sessionID,
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
