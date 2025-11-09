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
