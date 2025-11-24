// PitTemp/Data/CSV/CSVExporter.swift
import Foundation

/// ライブ追記（time,value）と集計CSV(export)の両方に対応する実装
final class CSVExporter: CSVExporting {

    // ---- ライブ追記（PitTempLogs）用 ----
    private var handle: FileHandle?
    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// ライブ追記：TemperatureSample を 1 行ずつ書く
    func appendLive(sample: TemperatureSample) {
        ensureStreamingHandle()
        guard let h = handle else { return }
        let line = "\(dateFmt.string(from: sample.time)),\(sample.value)\n"
        if let d = line.data(using: .utf8) {
            do { try h.write(contentsOf: d) } catch { /* optional log */ }
        }
    }

    deinit {
        if let h = handle {
            do { try h.close() } catch { /* ignore */ }
        }
    }

    // MARK: - 旧形式（wflat）
    func exportWFlat(
        meta: MeasureMeta,
        results: [MeasureResult],
        wheelMemos: [WheelPos: String],
        wheelPressures: [WheelPos: Double],
        sessionStart: Date,
        deviceName: String?,
        sessionID: SessionID,
        deviceIdentity: DeviceIdentity
    ) throws -> URL {

        let base = documentsBase()
        let uploadsDir = base.appendingPathComponent("PitTempUploads", isDirectory: true)
        let day = Self.dayString(from: sessionStart)
        let dayDir = uploadsDir.appendingPathComponent(day, isDirectory: true)
        let deviceDir = dayDir.appendingPathComponent(deviceIdentity.id.sanitizedPathComponent(), isDirectory: true)

        try FileManager.default.createDirectory(at: deviceDir, withIntermediateDirectories: true)

        let fileName = Self.fileName(
            sessionID: sessionID,
            meta: meta,
            deviceName: deviceName,
            deviceIdentity: deviceIdentity
        )
        let url = deviceDir.appendingPathComponent(fileName).appendingPathExtension("csv")

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // ヘッダは旧資産に合わせる
        // TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,IP_KPA,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO
        var csv = "TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,IP_KPA,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO\n"

        // wheelごとに OUT/CL/IN を詰める
        struct Acc { var out="", cl="", inS="", ip="" }
        var perWheel: [WheelPos:Acc] = [:]
        for r in results {
            var a = perWheel[r.wheel] ?? Acc()
            switch r.zone {
            case .OUT: a.out = r.peakC.isFinite ? String(format: "%.1f", r.peakC) : ""
            case .CL:  a.cl  = r.peakC.isFinite ? String(format: "%.1f", r.peakC) : ""
            case .IN:  a.inS = r.peakC.isFinite ? String(format: "%.1f", r.peakC) : ""
            }
            perWheel[r.wheel] = a
        }

        for (wheel, pressure) in wheelPressures {
            var acc = perWheel[wheel] ?? Acc()
            acc.ip = String(format: "%.1f", pressure)
            perWheel[wheel] = acc
        }

        let iso = ISO8601DateFormatter()
        let sessionISO  = iso.string(from: sessionStart)
        let exportedISO = iso.string(from: Date())
        let uploadedISO = "" // Upload時にアプリ側で埋める想定（空でOK）

        // wheel順で安定化
        let order: [WheelPos] = [.FL,.FR,.RL,.RR]
        for w in order {
            guard let a = perWheel[w] else { continue }
            let memo = wheelMemos[w] ?? ""
            let row = [
                meta.track, meta.date, meta.car, meta.driver, meta.tyre, meta.time, meta.lap, meta.checker,
                w.rawValue, a.out, a.cl, a.inS, a.ip,
                memo.replacingOccurrences(of: ",", with: " "),
                sessionISO, exportedISO, uploadedISO
            ].joined(separator: ",")
            csv += row + "\n"
        }

        try csv.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    // 共通: iCloud Documents or ローカル Documents
    private func documentsBase() -> URL {
        if let ubiq = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") {
            return ubiq
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func dayString(from date: Date) -> String {
        if #available(iOS 15.0, *) {
            return DateFormatter.cachedDayFormatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
    }

    private static func fileName(
        sessionID: SessionID,
        meta: MeasureMeta,
        deviceName: String?,
        deviceIdentity: DeviceIdentity
    ) -> String {
        var components: [String] = ["session", sessionID.rawValue.sanitizedPathComponent(limit: 72)]

        let driver = meta.driver.sanitizedPathComponent()
        let track = meta.track.sanitizedPathComponent()
        let car = meta.car.sanitizedPathComponent()
        let device = (deviceName ?? deviceIdentity.name).sanitizedPathComponent()

        if !driver.isEmpty { components.append(driver) }
        if !track.isEmpty { components.append(track) }
        if !car.isEmpty { components.append(car) }
        if !device.isEmpty { components.append(device) }

        return components.joined(separator: "-")
    }

    // ---- ヘルパ ----

    /// ライブ追記用ファイルのハンドルを lazy に準備
    private func ensureStreamingHandle() {
        if handle != nil { return }
        let base = documentsBase()
        let day = Self.dayString(from: Date())
        let dir = base.appendingPathComponent("PitTempLogs/\(day)")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("session-\(Int(Date().timeIntervalSince1970)).csv")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(
                    atPath: url.path,
                    contents: "time,value\n".data(using: .utf8)
                )
            }
            let h = try FileHandle(forWritingTo: url)
            try h.seekToEnd()
            handle = h
        } catch {
            handle = nil // 準備失敗時は以降の appendLive を無視
        }
    }
}

private extension String {
    func sanitizedPathComponent(limit: Int = 48) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let collapsed = trimmed.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "_",
            options: .regularExpression
        )

        let deduped = collapsed
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))

        if limit > 0 && deduped.count > limit {
            let index = deduped.index(deduped.startIndex, offsetBy: limit)
            return String(deduped[..<index])
        }

        return deduped
    }
}

