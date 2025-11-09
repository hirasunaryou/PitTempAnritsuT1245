import Foundation

struct SessionHistorySummary: Identifiable, Equatable {
    let fileURL: URL
    let createdAt: Date
    let sessionBeganAt: Date?
    let track: String
    let date: String
    let car: String
    let driver: String
    let tyre: String
    let lap: String
    let resultCount: Int

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
        return "Saved: \(captured) · Driver: \(driverText) · Tyre: \(tyreText) · Lap: \(lapText) · \(cells)"
    }
}

final class SessionHistoryStore: ObservableObject {
    @Published private(set) var summaries: [SessionHistorySummary] = []

    private let fileManager: FileManager
    private let archiveDirectory: URL
    private let decoder = JSONDecoder()
    private var historyObserver: Any?

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
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
            let urls = (try? self.fileManager.contentsOfDirectory(
                at: self.archiveDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            var items: [SessionHistorySummary] = []
            for url in urls where url.pathExtension.lowercased() == "json" {
                guard let data = try? Data(contentsOf: url) else { continue }
                guard let snapshot = try? self.decoder.decode(SessionSnapshot.self, from: data) else { continue }
                let summary = SessionHistorySummary(
                    fileURL: url,
                    createdAt: snapshot.createdAt,
                    sessionBeganAt: snapshot.sessionBeganAt,
                    track: snapshot.meta.track,
                    date: snapshot.meta.date,
                    car: snapshot.meta.car,
                    driver: snapshot.meta.driver,
                    tyre: snapshot.meta.tyre,
                    lap: snapshot.meta.lap,
                    resultCount: snapshot.results.count
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
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
