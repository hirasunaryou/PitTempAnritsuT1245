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
        deviceModelLabel: String?,
        sessionID: UUID,
        sessionReadableID: String,
        deviceIdentity: DeviceIdentity
    ) throws -> URL {

        let base = documentsBase()
        let uploadsDir = base.appendingPathComponent("PitTempUploads", isDirectory: true)
        let day = Self.dayString(from: sessionStart)
        let dayDir = uploadsDir.appendingPathComponent(day, isDirectory: true)

        // UUID そのままだと 36 文字以上の長さになるため、
        // ユーザーが Finder / ファイルアプリで扱いやすいように短縮版を使用する。
        // 端末名（読めるラベル）と短縮 ID の両方を含めることで、
        // 人間にとってのわかりやすさと重複しにくさのバランスを取っている。
        let deviceDirName = Self.deviceDirectoryName(
            deviceIdentity: deviceIdentity,
            deviceName: deviceName,
            deviceModelLabel: deviceModelLabel
        )
        let deviceDir = dayDir.appendingPathComponent(deviceDirName, isDirectory: true)

        try FileManager.default.createDirectory(at: deviceDir, withIntermediateDirectories: true)

        let fileName = Self.fileName(
            sessionID: sessionID,
            sessionReadableID: sessionReadableID,
            meta: meta,
            deviceName: deviceName,
            deviceIdentity: deviceIdentity
        )
        let url = deviceDir.appendingPathComponent(fileName).appendingPathExtension("csv")

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // ヘッダは旧資産に合わせる
        // TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,IP_KPA,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO,SESSION_UUID,SESSION_LABEL
        // 末尾に Session 情報を追加して、後からログを辿りやすくする。
        var csv = "TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,IP_KPA,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO,SESSION_UUID,SESSION_LABEL\n"

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
                sessionISO, exportedISO, uploadedISO,
                sessionID.uuidString, sessionReadableID.replacingOccurrences(of: ",", with: " ")
            ].joined(separator: ",")
            csv += row + "\n"
        }

        try csv.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    /// デバイスごとのフォルダ名を生成するヘルパ。
    /// - Parameters:
    ///   - deviceIdentity: UUID を含む識別情報。
    ///   - deviceName: ユーザーが付けた端末名（nil の場合は識別情報の name を利用）。
    ///   - deviceModelLabel: 機種名やマーケティング名など、端末種別を示す短いラベル。
    /// - Returns: 読みやすさと一意性のバランスを取った短めのフォルダ名。
    static func deviceDirectoryName(
        deviceIdentity: DeviceIdentity,
        deviceName: String?,
        deviceModelLabel: String? = nil
    ) -> String {
        // UUID の先頭 8 文字だけ抜き出して短いままでも識別できるようにする。
        let shortID = deviceIdentity.id.sanitizedPathComponent(limit: 8)
        // 端末名がある場合は最大 24 文字に抑えて読みやすさを優先。
        // "\s+" を一気に削っておくことで、Finder などでの視認性を確保しつつ
        // 「空白混じりで余計なバグを生む」リスクを減らしている。
        // まれに "   " のような空文字同然の入力が来ることがあり、そのままだと
        // フォルダ名に端末名が含まれないため、サニタイズ後に空ならデフォルトの
        // `deviceIdentity.name` をもう一度整形して使う。
        let providedReadableName = (deviceName ?? "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .sanitizedPathComponent(limit: 24)
        let fallbackReadableName = deviceIdentity.name
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .sanitizedPathComponent(limit: 24)
        let readableName = providedReadableName.ifEmpty(fallbackReadableName)
        // 機種名などは 16 文字程度に抑えて補助情報として添える。
        let modelLabel = (deviceModelLabel ?? "").sanitizedPathComponent(limit: 16)

        // 名前・機種・ID の順で優先的に並べて、「読みやすいけれど衝突しにくい」構造を保つ。
        var pieces: [String] = []
        if !readableName.isEmpty { pieces.append(readableName) }
        if !modelLabel.isEmpty { pieces.append(modelLabel) }
        if !shortID.isEmpty { pieces.append(shortID) }

        if pieces.isEmpty { return "device" }
        return pieces.joined(separator: "-")
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
        sessionID: UUID,
        sessionReadableID: String,
        meta: MeasureMeta,
        deviceName: String?,
        deviceIdentity: DeviceIdentity
    ) -> String {
        var components: [String] = ["session", sessionReadableID.sanitizedPathComponent(limit: 48), sessionID.uuidString]

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

