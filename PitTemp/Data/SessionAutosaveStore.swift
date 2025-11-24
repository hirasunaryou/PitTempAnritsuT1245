//
//  SessionAutosaveStore.swift
//  PitTemp
//
//  自動保存されたセッションを JSON として Documents/PitTempAutosaves/latest.json に保持する。
//  再起動時の復元や、手動 CSV 送信前のバックアップ用途に使用する。
//

import Foundation

protocol SessionAutosaveHandling {
    func save(_ snapshot: SessionSnapshot)
    func load() -> SessionSnapshot?
    func clear()
    func archiveLatest()
    func hasSnapshot() -> Bool
}

struct SessionSnapshot: Codable {
    var meta: MeasureMeta
    var results: [MeasureResult]
    var wheelMemos: [WheelPos: String]
    var wheelPressures: [WheelPos: Double]
    var sessionBeganAt: Date?
    var sessionID: SessionID
    var originDeviceID: String
    var originDeviceName: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case meta
        case results
        case wheelMemos
        case wheelPressures
        case sessionBeganAt
        case sessionID
        case originDeviceID
        case originDeviceName
        case createdAt
    }

    init(meta: MeasureMeta,
         results: [MeasureResult],
         wheelMemos: [WheelPos: String],
         wheelPressures: [WheelPos: Double] = [:],
         sessionBeganAt: Date?,
         sessionID: SessionID,
         originDeviceID: String,
         originDeviceName: String,
         createdAt: Date = Date()) {
        self.meta = meta
        self.results = results
        self.wheelMemos = wheelMemos
        self.wheelPressures = wheelPressures
        self.sessionBeganAt = sessionBeganAt
        self.sessionID = sessionID
        self.originDeviceID = originDeviceID
        self.originDeviceName = originDeviceName
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meta = try container.decode(MeasureMeta.self, forKey: .meta)
        results = try container.decode([MeasureResult].self, forKey: .results)
        sessionBeganAt = try container.decodeIfPresent(Date.self, forKey: .sessionBeganAt)
        if let encoded = try container.decodeIfPresent(String.self, forKey: .sessionID) {
            // 旧データ（UUID文字列）を含め、新仕様のSessionIDに巻き取る
            sessionID = SessionID(rawValue: encoded)
        } else if let uuid = try container.decodeIfPresent(UUID.self, forKey: .sessionID) {
            sessionID = SessionID.fromUUID(uuid)
        } else {
            sessionID = SessionID.generate(op: .measure, deviceAbbrev: "MIGRATED", context: "legacy")
        }
        originDeviceID = try container.decodeIfPresent(String.self, forKey: .originDeviceID) ?? ""
        originDeviceName = try container.decodeIfPresent(String.self, forKey: .originDeviceName) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        let rawMap = try container.decode([WheelPos.RawValue: String].self, forKey: .wheelMemos)
        wheelMemos = Dictionary(uniqueKeysWithValues: rawMap.compactMap { key, value in
            WheelPos(rawValue: key).map { ($0, value) }
        })

        if let rawPressures = try container.decodeIfPresent([WheelPos.RawValue: Double].self, forKey: .wheelPressures) {
            wheelPressures = Dictionary(uniqueKeysWithValues: rawPressures.compactMap { key, value in
                WheelPos(rawValue: key).map { ($0, value) }
            })
        } else {
            wheelPressures = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(meta, forKey: .meta)
        try container.encode(results, forKey: .results)
        try container.encodeIfPresent(sessionBeganAt, forKey: .sessionBeganAt)
        try container.encode(sessionID.rawValue, forKey: .sessionID)
        try container.encode(originDeviceID, forKey: .originDeviceID)
        try container.encode(originDeviceName, forKey: .originDeviceName)
        try container.encode(createdAt, forKey: .createdAt)

        let rawMap = Dictionary(uniqueKeysWithValues: wheelMemos.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawMap, forKey: .wheelMemos)

        if !wheelPressures.isEmpty {
            let pressureMap = Dictionary(uniqueKeysWithValues: wheelPressures.map { ($0.key.rawValue, $0.value) })
            try container.encode(pressureMap, forKey: .wheelPressures)
        }
    }
}

final class SessionAutosaveStore: SessionAutosaveHandling {
    private let fileManager: FileManager
    private let autosaveURL: URL
    private let archiveDirectory: URL
    private let autosaveCSVURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let uiLogger: UILogPublishing?
    private let dataWriter: (Data, URL) throws -> Void

    typealias DataWriter = (Data, URL) throws -> Void

    init(fileManager: FileManager = .default,
         autosaveDirectory: URL? = nil,
         uiLogger: UILogPublishing? = nil,
         dataWriter: @escaping DataWriter = { data, url in
             try data.write(to: url, options: .atomic)
         }) {
        self.fileManager = fileManager
        self.uiLogger = uiLogger
        self.dataWriter = dataWriter
        let base = autosaveDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let autosaveDir = base.appendingPathComponent("PitTempAutosaves", isDirectory: true)
        self.autosaveURL = autosaveDir.appendingPathComponent("latest.json")
        self.archiveDirectory = autosaveDir.appendingPathComponent("archive", isDirectory: true)
        self.autosaveCSVURL = autosaveDir.appendingPathComponent("latest.csv")

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if !fileManager.fileExists(atPath: autosaveDir.path) {
            try? fileManager.createDirectory(at: autosaveDir, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: archiveDirectory.path) {
            try? fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        }
    }

    func save(_ snapshot: SessionSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            try dataWriter(data, autosaveURL)
            try writeCSV(snapshot)
        } catch {
            print("[Autosave] save failed:", error)
            uiLogger?.publish(UILogEntry(
                message: "Failed to autosave session: \(error.localizedDescription)",
                level: .error,
                category: .autosave
            ))
        }
    }

    func load() -> SessionSnapshot? {
        guard fileManager.fileExists(atPath: autosaveURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: autosaveURL)
            return try decoder.decode(SessionSnapshot.self, from: data)
        } catch {
            print("[Autosave] load failed:", error)
            uiLogger?.publish(UILogEntry(
                message: "Failed to load autosave snapshot: \(error.localizedDescription)",
                level: .error,
                category: .autosave
            ))
            return nil
        }
    }

    func clear() {
        guard fileManager.fileExists(atPath: autosaveURL.path) else { return }
        do {
            try fileManager.removeItem(at: autosaveURL)
            if fileManager.fileExists(atPath: autosaveCSVURL.path) {
                try fileManager.removeItem(at: autosaveCSVURL)
            }
        } catch {
            print("[Autosave] clear failed:", error)
            uiLogger?.publish(UILogEntry(
                message: "Failed to clear autosave snapshot: \(error.localizedDescription)",
                level: .error,
                category: .autosave
            ))
        }
    }

    func archiveLatest() {
        guard fileManager.fileExists(atPath: autosaveURL.path) else { return }

        do {
            let data = try Data(contentsOf: autosaveURL)
            let snapshot = try decoder.decode(SessionSnapshot.self, from: data)
            let day = DateFormatter.cachedDayFormatter.string(from: snapshot.createdAt)
            let dayDirectory = archiveDirectory.appendingPathComponent(day, isDirectory: true)
            if !fileManager.fileExists(atPath: dayDirectory.path) {
                try fileManager.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
            }

            let safeID = snapshot.sessionID.rawValue.safeFileToken()
            let destination = dayDirectory
                .appendingPathComponent("session-\(safeID)")
                .appendingPathExtension("json")
            let destinationCSV = dayDirectory
                .appendingPathComponent("session-\(safeID)")
                .appendingPathExtension("csv")

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try data.write(to: destination, options: .atomic)

            if fileManager.fileExists(atPath: autosaveCSVURL.path) {
                let csvData = try Data(contentsOf: autosaveCSVURL)
                if fileManager.fileExists(atPath: destinationCSV.path) {
                    try fileManager.removeItem(at: destinationCSV)
                }
                try csvData.write(to: destinationCSV, options: .atomic)
            }

            NotificationCenter.default.post(
                name: .pitSessionHistoryUpdated,
                object: nil,
                userInfo: ["url": destination]
            )
        } catch {
            print("[Autosave] archive failed:", error)
            uiLogger?.publish(UILogEntry(
                message: "Failed to archive autosave snapshot: \(error.localizedDescription)",
                level: .error,
                category: .autosave
            ))
        }
    }

    func hasSnapshot() -> Bool {
        fileManager.fileExists(atPath: autosaveURL.path)
    }

    private func writeCSV(_ snapshot: SessionSnapshot) throws {
        struct Accumulator { var out = ""; var center = ""; var inner = ""; var ip = "" }
        var perWheel: [WheelPos: Accumulator] = [:]
        for result in snapshot.results {
            let value = result.peakC.isFinite ? String(format: "%.1f", result.peakC) : ""
            var acc = perWheel[result.wheel] ?? Accumulator()
            switch result.zone {
            case .OUT: acc.out = value
            case .CL: acc.center = value
            case .IN: acc.inner = value
            }
            perWheel[result.wheel] = acc
        }

        for (wheel, pressure) in snapshot.wheelPressures {
            var acc = perWheel[wheel] ?? Accumulator()
            acc.ip = String(format: "%.1f", pressure)
            perWheel[wheel] = acc
        }

        var csv = "TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,IP_KPA,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO\n"

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let sessionStart = snapshot.sessionBeganAt ?? snapshot.createdAt
        let sessionISO = iso.string(from: sessionStart)
        let exportedISO = iso.string(from: snapshot.createdAt)
        let uploadedISO = ""

        let order: [WheelPos] = [.FL, .FR, .RL, .RR]
        for wheel in order {
            guard let acc = perWheel[wheel] else { continue }
            let memo = snapshot.wheelMemos[wheel]?.replacingOccurrences(of: ",", with: " ") ?? ""
            let row = [
                snapshot.meta.track,
                snapshot.meta.date,
                snapshot.meta.car,
                snapshot.meta.driver,
                snapshot.meta.tyre,
                snapshot.meta.time,
                snapshot.meta.lap,
                snapshot.meta.checker,
                wheel.rawValue,
                acc.out,
                acc.center,
                acc.inner,
                acc.ip,
                memo,
                sessionISO,
                exportedISO,
                uploadedISO
            ].joined(separator: ",")
            csv += row + "\n"
        }

        do {
            try csv.write(to: autosaveCSVURL, atomically: true, encoding: .utf8)
        } catch {
            print("[Autosave] write csv failed:", error)
            uiLogger?.publish(UILogEntry(
                message: "Failed to write autosave CSV: \(error.localizedDescription)",
                level: .error,
                category: .autosave
            ))
            throw error
        }
    }
}

extension DateFormatter {
    static let cachedDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
