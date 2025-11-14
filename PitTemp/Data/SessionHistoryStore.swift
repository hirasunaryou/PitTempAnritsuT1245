import Foundation

struct SessionHistorySummary: Identifiable, Equatable {
    let fileURL: URL
    let createdAt: Date
    let sessionBeganAt: Date?
    let sessionID: UUID
    let track: String
    let date: String
    let car: String
    let driver: String
    let tyre: String
    let lap: String
    let checker: String
    let resultCount: Int
    let zonePeaks: [WheelPos: [Zone: Double]]
    let wheelPressures: [WheelPos: Double]
    let originDeviceID: String
    let originDeviceName: String
    let isFromCurrentDevice: Bool

    var id: String { fileURL.lastPathComponent }

    var displayTitle: String {
        let primary = car.ifEmpty("Unknown car")
        let trackText = track.ifEmpty("-")
        return "\(primary) · \(trackText)"
    }

    var displayDetail: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let captured = formatter.string(from: createdAt)
        let driverText = driver.ifEmpty("-")
        let tyreText = tyre.ifEmpty("-")
        let lapText = lap.ifEmpty("-")
        let cells = resultCount == 1 ? "1 cell" : "\(resultCount) cells"
        let device = originDeviceDisplayName.ifEmpty("Unknown device")
        let deviceScope = isFromCurrentDevice ? "This device" : "External"
        return "Saved: \(captured) · Driver: \(driverText) · Tyre: \(tyreText) · Lap: \(lapText) · Device: \(device) (\(deviceScope)) · \(cells)"
    }

    var hasTemperatures: Bool { !zonePeaks.isEmpty }
    var hasPressures: Bool { !wheelPressures.isEmpty }

    var originDeviceDisplayName: String {
        let trimmed = originDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let idTrimmed = originDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !idTrimmed.isEmpty { return idTrimmed }
        return ""
    }

    var originDeviceShortID: String {
        let trimmed = originDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed }
        return String(trimmed.prefix(8))
    }

    func temperature(for wheel: WheelPos, zone: Zone) -> Double? {
        zonePeaks[wheel]?[zone]
    }

    func formattedTemperature(for wheel: WheelPos, zone: Zone) -> String {
        guard let value = temperature(for: wheel, zone: zone), value.isFinite else { return "-" }
        return SessionHistorySummary.temperatureFormatter.string(from: NSNumber(value: value)) ?? "-"
    }

    func formattedPressure(for wheel: WheelPos) -> String {
        guard let value = wheelPressures[wheel], value.isFinite else { return "-" }
        return SessionHistorySummary.pressureFormatter.string(from: NSNumber(value: value)) ?? "-"
    }

    func matches(search query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let lower = needle.lowercased()
        let haystack = [
            displayTitle,
            track,
            date,
            car,
            driver,
            checker,
            tyre,
            lap,
            sessionID.uuidString,
            originDeviceID,
            originDeviceName,
            SessionHistorySummary.searchDateFormatter.string(from: createdAt),
        ].map { $0.lowercased() }
        return haystack.contains { $0.contains(lower) }
    }

    private static let temperatureFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.positiveSuffix = "℃"
        formatter.negativeSuffix = "℃"
        formatter.zeroSymbol = "0.0℃"
        return formatter
    }()

    private static let pressureFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.positiveSuffix = " kPa"
        formatter.negativeSuffix = " kPa"
        formatter.zeroSymbol = "0.0 kPa"
        return formatter
    }()

    private static let searchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func zonePeaks(from results: [MeasureResult]) -> [WheelPos: [Zone: Double]] {
        var matrix: [WheelPos: [Zone: (Date, Double)]] = [:]
        for result in results {
            guard result.peakC.isFinite else { continue }
            var wheelMap = matrix[result.wheel, default: [:]]
            if let existing = wheelMap[result.zone], existing.0 >= result.endedAt {
                continue
            }
            wheelMap[result.zone] = (result.endedAt, result.peakC)
            matrix[result.wheel] = wheelMap
        }

        var peaks: [WheelPos: [Zone: Double]] = [:]
        for (wheel, zoneMap) in matrix {
            var wheelPeaks: [Zone: Double] = [:]
            for (zone, record) in zoneMap {
                wheelPeaks[zone] = record.1
            }
            peaks[wheel] = wheelPeaks
        }
        return peaks
    }

    static func makeLiveSummary(from snapshot: SessionSnapshot, isFromCurrentDevice: Bool = true) -> SessionHistorySummary {
        let placeholderDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "pittemp-live-\(snapshot.sessionID.uuidString).json"
        let placeholderURL = placeholderDirectory.appendingPathComponent(filename, isDirectory: false)

        return SessionHistorySummary(
            fileURL: placeholderURL,
            createdAt: snapshot.createdAt,
            sessionBeganAt: snapshot.sessionBeganAt,
            sessionID: snapshot.sessionID,
            track: snapshot.meta.track,
            date: snapshot.meta.date,
            car: snapshot.meta.car,
            driver: snapshot.meta.driver,
            tyre: snapshot.meta.tyre,
            lap: snapshot.meta.lap,
            checker: snapshot.meta.checker,
            resultCount: snapshot.results.count,
            zonePeaks: zonePeaks(from: snapshot.results),
            wheelPressures: snapshot.wheelPressures,
            originDeviceID: snapshot.originDeviceID,
            originDeviceName: snapshot.originDeviceName,
            isFromCurrentDevice: isFromCurrentDevice
        )
    }
}

struct SessionHistoryImportReport {
    struct Failure: Identifiable {
        let url: URL
        let reason: String
        var id: URL { url }
    }

    var importedCount: Int = 0
    var failures: [Failure] = []

    var hasFailures: Bool { !failures.isEmpty }
}

final class SessionHistoryStore: ObservableObject {
    @Published private(set) var summaries: [SessionHistorySummary] = []

    private let fileManager: FileManager
    private let archiveDirectory: URL
    private let deviceIdentity: DeviceIdentity
    private var historyObserver: Any?

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.deviceIdentity = DeviceIdentity.current()
        if let baseDirectory {
            archiveDirectory = baseDirectory
                .appendingPathComponent("PitTempAutosaves", isDirectory: true)
                .appendingPathComponent("archive", isDirectory: true)
        } else {
            let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            archiveDirectory = base
                .appendingPathComponent("PitTempAutosaves", isDirectory: true)
                .appendingPathComponent("archive", isDirectory: true)
        }

        refresh()

        historyObserver = NotificationCenter.default.addObserver(
            forName: .pitSessionHistoryUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let historyObserver {
            NotificationCenter.default.removeObserver(historyObserver)
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let urls: [URL]
            if let enumerator = self.fileManager.enumerator(
                at: self.archiveDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                urls = enumerator.compactMap { element in
                    guard let url = element as? URL else { return nil }
                    return url
                }
            } else {
                urls = []
            }

            let decoder = JSONDecoder()
            var items: [SessionHistorySummary] = []
            let localDeviceID = self.deviceIdentity.id.trimmingCharacters(in: .whitespacesAndNewlines)
            for url in urls where url.pathExtension.lowercased() == "json" {
                guard let data = try? Data(contentsOf: url) else { continue }
                guard let snapshot = try? decoder.decode(SessionSnapshot.self, from: data) else { continue }
                let trimmedDeviceID = snapshot.originDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
                let isLocal = !trimmedDeviceID.isEmpty && !localDeviceID.isEmpty && trimmedDeviceID == localDeviceID

                let summary = SessionHistorySummary(
                    fileURL: url,
                    createdAt: snapshot.createdAt,
                    sessionBeganAt: snapshot.sessionBeganAt,
                    sessionID: snapshot.sessionID,
                    track: snapshot.meta.track,
                    date: snapshot.meta.date,
                    car: snapshot.meta.car,
                    driver: snapshot.meta.driver,
                    tyre: snapshot.meta.tyre,
                    lap: snapshot.meta.lap,
                    checker: snapshot.meta.checker,
                    resultCount: snapshot.results.count,
                    zonePeaks: SessionHistorySummary.zonePeaks(from: snapshot.results),
                    wheelPressures: snapshot.wheelPressures,
                    originDeviceID: snapshot.originDeviceID,
                    originDeviceName: snapshot.originDeviceName,
                    isFromCurrentDevice: isLocal
                )
                items.append(summary)
            }

            items.sort { $0.createdAt > $1.createdAt }

            DispatchQueue.main.async {
                self.summaries = items
            }
        }
    }

    func snapshot(for summary: SessionHistorySummary) -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: summary.fileURL) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(SessionSnapshot.self, from: data)
    }

    func previous(after summary: SessionHistorySummary?) -> SessionHistorySummary? {
        guard !summaries.isEmpty else { return nil }
        guard let summary else { return summaries.first }
        guard let idx = summaries.firstIndex(of: summary) else { return summaries.first }
        let nextIdx = idx + 1
        return nextIdx < summaries.count ? summaries[nextIdx] : nil
    }

    func newer(before summary: SessionHistorySummary?) -> SessionHistorySummary? {
        guard !summaries.isEmpty else { return nil }
        guard let summary else { return summaries.first }
        guard let idx = summaries.firstIndex(of: summary) else { return summaries.first }
        let prevIdx = idx - 1
        return prevIdx >= 0 ? summaries[prevIdx] : nil
    }

    func importSnapshots(from urls: [URL]) -> SessionHistoryImportReport {
        let decoder = JSONDecoder()
        var report = SessionHistoryImportReport()

        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            guard url.pathExtension.lowercased() == "json" else {
                report.failures.append(.init(url: url, reason: "Unsupported file type"))
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                let snapshot = try decoder.decode(SessionSnapshot.self, from: data)
                let destination = uniqueDestinationURL(for: snapshot, original: url)
                try data.write(to: destination, options: .atomic)
                report.importedCount += 1
            } catch {
                report.failures.append(.init(url: url, reason: error.localizedDescription))
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }

        return report
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}

private extension SessionHistoryStore {
    func uniqueDestinationURL(for snapshot: SessionSnapshot, original: URL) -> URL {
        _ = original
        let day = DateFormatter.cachedDayFormatter.string(from: snapshot.createdAt)
        let dayDirectory = archiveDirectory.appendingPathComponent(day, isDirectory: true)
        if !fileManager.fileExists(atPath: dayDirectory.path) {
            try? fileManager.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
        }

        let destination = dayDirectory
            .appendingPathComponent("session-\(snapshot.sessionID.uuidString)")
            .appendingPathExtension("json")

        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }

        return destination
    }
}
