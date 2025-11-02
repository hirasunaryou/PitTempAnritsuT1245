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
}

struct SessionSnapshot: Codable {
    var meta: MeasureMeta
    var results: [MeasureResult]
    var wheelMemos: [WheelPos: String]
    var sessionBeganAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case meta
        case results
        case wheelMemos
        case sessionBeganAt
        case createdAt
    }

    init(meta: MeasureMeta,
         results: [MeasureResult],
         wheelMemos: [WheelPos: String],
         sessionBeganAt: Date?,
         createdAt: Date = Date()) {
        self.meta = meta
        self.results = results
        self.wheelMemos = wheelMemos
        self.sessionBeganAt = sessionBeganAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meta = try container.decode(MeasureMeta.self, forKey: .meta)
        results = try container.decode([MeasureResult].self, forKey: .results)
        sessionBeganAt = try container.decodeIfPresent(Date.self, forKey: .sessionBeganAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        let rawMap = try container.decode([WheelPos.RawValue: String].self, forKey: .wheelMemos)
        wheelMemos = Dictionary(uniqueKeysWithValues: rawMap.compactMap { key, value in
            WheelPos(rawValue: key).map { ($0, value) }
        })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(meta, forKey: .meta)
        try container.encode(results, forKey: .results)
        try container.encodeIfPresent(sessionBeganAt, forKey: .sessionBeganAt)
        try container.encode(createdAt, forKey: .createdAt)

        let rawMap = Dictionary(uniqueKeysWithValues: wheelMemos.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawMap, forKey: .wheelMemos)
    }
}

final class SessionAutosaveStore: SessionAutosaveHandling {
    private let fileManager: FileManager
    private let autosaveURL: URL
    private let archiveDirectory: URL
    private let autosaveCSVURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
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
            try data.write(to: autosaveURL, options: .atomic)
            writeCSV(snapshot)
        } catch {
            print("[Autosave] save failed:", error)
        }
    }

    func load() -> SessionSnapshot? {
        guard fileManager.fileExists(atPath: autosaveURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: autosaveURL)
            return try decoder.decode(SessionSnapshot.self, from: data)
        } catch {
            print("[Autosave] load failed:", error)
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
        }
    }

    func archiveLatest() {
        guard fileManager.fileExists(atPath: autosaveURL.path) else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = archiveDirectory.appendingPathComponent("session-\(timestamp).json")
        let destinationCSV = archiveDirectory.appendingPathComponent("session-\(timestamp).csv")

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: autosaveURL, to: destination)
            if fileManager.fileExists(atPath: autosaveCSVURL.path) {
                if fileManager.fileExists(atPath: destinationCSV.path) {
                    try fileManager.removeItem(at: destinationCSV)
                }
                try fileManager.copyItem(at: autosaveCSVURL, to: destinationCSV)
            }
        } catch {
            print("[Autosave] archive failed:", error)
        }
    }

    private func writeCSV(_ snapshot: SessionSnapshot) {
        struct Accumulator { var out = ""; var center = ""; var inner = "" }
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

        var csv = "TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO\n"

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let sessionStart = snapshot.sessionBeganAt ?? snapshot.createdAt
        let sessionISO = iso.string(from: sessionStart)
        let exportedISO = iso.string(from: snapshot.createdAt)
        let uploadedISO = ""

        let order: [WheelPos] = [.FL, .FR, .RL, .RR]
        for wheel in order where perWheel[wheel] != nil {
            let acc = perWheel[wheel]!
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
        }
    }
}
