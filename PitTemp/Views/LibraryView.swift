// LibraryView.swift

import SwiftUI
import Foundation
import UniformTypeIdentifiers

// MARK: - 1行=1レコード（wflatに準拠）
struct LogRow: Identifiable {
    let id = UUID()
    var track, date, car, driver, tyre, time, lap, checker: String
    var wheel: String
    var outStr: String   // 温度（文字列）
    var clStr: String
    var inStr: String
    var memo: String
    var sessionISO: String     // SESSION_START_ISO
    var exportedISO: String    // EXPORTED_AT_ISO
    var uploadedISO: String    // UPLOADED_AT_ISO
}

extension LogRow {
    /// CSVエクスポート時の行データ
    fileprivate var canonicalCSVColumns: [String] {
        [track, date, car, driver, tyre, time, lap, checker, wheel, outStr, clStr, inStr, memo, sessionISO, exportedISO, uploadedISO]
    }
}

// 個別CSVビューのクイック並び替えキー（wflatに合わせて簡略化）
enum SortKey: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case track = "TRACK"
    case date  = "DATE"
    case car   = "CAR"
    case tyre  = "TYRE"
    case driver = "DRIVER"
    case checker = "CHECKER"
    case wheel = "WHEEL"
}

// ALLビューでユーザーが選べる列
enum Column: String, CaseIterable, Identifiable {
    case track = "TRACK", date="DATE", time="TIME", car="CAR", driver="DRIVER", tyre="TYRE"
    case lap="LAP", checker="CHECKER", wheel="WHEEL"
    case out="OUT", cl="CL", inT="IN", memo="MEMO", session = "SESSION", exported="EXPORTED", uploaded="UPLOADED"
    var id: String { rawValue }
}

// URLをそのままIdentifiableに拡張しない（将来衝突回避）ための薄いラッパ
struct FileItem: Identifiable, Hashable {
    let url: URL
    let dayFolder: String
    let modifiedAt: Date
    var id: String { url.absoluteString }
}

private struct DailyGroup: Identifiable, Hashable {
    let day: String
    let files: [FileItem]

    var id: String { day }

    var latestModified: Date {
        files.map(\.modifiedAt).max() ?? .distantPast
    }

    var fileCountText: String {
        "\(files.count) file\(files.count > 1 ? "s" : "")"
    }
}

private struct MergedCSVDocument: Transferable {
    let fileName: String
    let rows: [LogRow]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            Data(document.makeCSV().utf8)
        }
        .suggestedFileName { document in
            document.fileName
        }
    }

    private func makeCSV() -> String {
        guard !rows.isEmpty else {
            return canonicalHeader.joined(separator: ",") + "\n"
        }

        let escapedRows = rows.map { row in
            row.canonicalCSVColumns.map { Self.escape($0) }.joined(separator: ",")
        }
        return ([canonicalHeader.joined(separator: ",")] + escapedRows).joined(separator: "\n") + "\n"
    }

    private static let canonicalHeader: [String] = [
        "TRACK", "DATE", "CAR", "DRIVER", "TYRE", "TIME", "LAP", "CHECKER",
        "WHEEL", "OUT", "CL", "IN", "MEMO", "SESSION_START_ISO", "EXPORTED_AT_ISO", "UPLOADED_AT_ISO"
    ]

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

// MARK: - LibraryView
struct LibraryView: View {
    @EnvironmentObject var folderBM: FolderBookmark
    @EnvironmentObject var settings: SettingsStore

    // ファイル一覧
    @State private var files: [FileItem] = []
    @State private var dailyGroups: [DailyGroup] = []

    // 個別CSV表示用
    @State private var rows: [LogRow] = []
    @State private var sortKey: SortKey = .newest
    @State private var selectedFile: FileItem? = nil
    @State private var rawPreview: String = ""
    @State private var isMergingDailyCSV = false

    // ALL表示用
    @State private var showAllSheet = false
    @State private var searchText = ""
    @State private var selectedColumns: [Column] = [.track,.date,.time,.car,.tyre,.wheel,.out,.cl,.inT,.memo,.exported,.uploaded]
    @State private var sortColumn: Column = .date
    @State private var sortAscending: Bool = true
    @State private var showColumnSheet = false
    @State private var allSheetTitle = "All CSVs"
    @State private var shareFileName = "PitTemp_All.csv"

    // 可視→検索→ソートを適用した配列
    private var visibleSortedRows: [LogRow] {
        // 1) 検索フィルタ
        let filtered: [LogRow]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = rows
        } else {
            let q = searchText.lowercased()
            filtered = rows.filter { r in
                selectedColumns.contains(where: { col in
                    cell(r, col).lowercased().contains(q)
                })
            }
        }
        // 2) ソート
        return filtered.sorted(by: { a, b in
            let lhs = cell(a, sortColumn)
            let rhs = cell(b, sortColumn)
            if [.out, .cl, .inT].contains(sortColumn) {
                let la = Double(lhs) ?? -Double.infinity
                let rb = Double(rhs) ?? -Double.infinity
                return sortAscending ? (la < rb) : (la > rb)
            } else if [.exported, .uploaded, .session].contains(sortColumn) {
                let fa = ISO8601DateFormatter().date(from: lhs) ?? .distantPast
                let fb = ISO8601DateFormatter().date(from: rhs) ?? .distantPast
                return sortAscending ? (fa < fb) : (fa > fb)
            } else {
                return sortAscending
                    ? (lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending)
                    : (lhs.localizedCaseInsensitiveCompare(rhs) == .orderedDescending)
            }
        })
    }

    private var shareDocument: MergedCSVDocument? {
        rows.isEmpty ? nil : MergedCSVDocument(fileName: shareFileName, rows: visibleSortedRows)
    }

    var body: some View {
        ZStack {
            NavigationStack {
                List {
                    Section("Cloud") {
                        if settings.enableGoogleDriveUpload {
                            NavigationLink {
                                DriveBrowserView()
                            } label: {
                                Label("Google Drive", systemImage: "cloud")
                            }
                        } else {
                            Label("Google Drive uploads disabled", systemImage: "cloud.slash")
                                .foregroundStyle(.secondary)
                        }
                    }

                if folderBM.folderURL != nil {
                    // クイック並び替え（個別CSVビュー用）
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach([SortKey.newest,.oldest,.track,.date,.car,.tyre,.driver,.checker,.wheel], id:\.self) { key in
                                    Button(key.rawValue) { sortKey = key; applySortForSingle() }
                                        .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !dailyGroups.isEmpty {
                    Section("Daily collections") {
                        ForEach(dailyGroups) { group in
                            Button {
                                openDailyGroup(group)
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(formattedDayTitle(group.day))
                                            .font(.headline)
                                        HStack(spacing: 12) {
                                            Label(group.fileCountText, systemImage: "doc.on.doc")
                                                .font(.caption)
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock")
                                                Text(group.latestModified, format: .dateTime.year().month().day().hour().minute())
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // ファイル一覧
                ForEach(files, id: \.self) { item in
                    Button {
                        rows = parseCSV(item.url)
                        rawPreview = (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
                        selectedFile = item
                        applySortForSingle()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.url.lastPathComponent).font(.headline)
                                Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "doc.text")
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                HStack {
                    Button("All") {
                        rows = loadAll()
                        searchText.removeAll()
                        applyDynamicSort()
                        allSheetTitle = "All CSVs"
                        shareFileName = makeMergedFileName(suffix: "all")
                        showAllSheet = true
                    }

                    Button("Columns") { showColumnSheet = true }

                    Menu("Sort") {
                        Picker("Column", selection: $sortColumn) {
                            ForEach(Column.allCases) { c in Text(c.rawValue).tag(c) }
                        }
                        Toggle("Ascending", isOn: $sortAscending)
                    }

                    Button { reloadFiles() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .onChange(of: sortColumn) { _, _ in applyDynamicSort() }    // iOS17+ の2引数版
            .onChange(of: sortAscending) { _, _ in applyDynamicSort() } // 同上
            .onAppear { reloadFiles() }

            // 個別CSVの詳細
            .sheet(item: $selectedFile) { file in
                NavigationStack {
                    List {
                        Section("RESULTS") {
                            Text("\(rows.count) rows").font(.headline)
                            if !rows.isEmpty { SingleTableView(rows: rows) }
                        }
                        Section("RAW") {
                            ScrollView { Text(rawPreview).font(.footnote).textSelection(.enabled) }
                        }
                    }
                    .navigationTitle(file.url.lastPathComponent)
                    .toolbar { Button("Close") { selectedFile = nil } }
                }
            }

            // ALL表示（列選択・検索・列ヘッダで昇降切替）
            .sheet(isPresented: $showAllSheet) {
                NavigationStack {
                    VStack(spacing: 0) {
                        // 🔎 検索ボックス
                        HStack {
                            Image(systemName: "magnifyingglass")
                            TextField("Search", text: $searchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground))

                        ScrollView([.vertical, .horizontal]) {
                            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                                Section {
                                    ForEach(Array(visibleSortedRows.enumerated()), id: \.offset) { index, row in
                                        HStack(spacing: 0) {
                                            ForEach(selectedColumns) { col in
                                                Text(cell(row, col))
                                                    .font(.footnote.monospacedDigit())
                                                    .padding(.vertical, 8)
                                                    .padding(.horizontal, 6)
                                                    .frame(minWidth: 120, alignment: .leading)
                                                    .background(index.isMultiple(of: 2) ? Color(.systemBackground) : Color(.secondarySystemBackground))
                                            }
                                        }
                                        .background(index.isMultiple(of: 2) ? Color(.systemBackground) : Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .padding(.vertical, 1)
                                    }
                                } header: {
                                    HStack(spacing: 0) {
                                        ForEach(selectedColumns) { col in
                                            Button {
                                                if sortColumn == col {
                                                    sortAscending.toggle()
                                                } else {
                                                    sortColumn = col
                                                    sortAscending = true
                                                }
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Text(col.rawValue)
                                                        .font(.footnote.bold())
                                                    if sortColumn == col {
                                                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                                            .font(.caption2)
                                                    }
                                                }
                                                .frame(minWidth: 120, alignment: .leading)
                                                .padding(.vertical, 10)
                                                .padding(.horizontal, 6)
                                            }
                                            .buttonStyle(.plain)
                                            .background(Color(.tertiarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                    .padding(.bottom, 4)
                                    .background(Color(.systemGroupedBackground))
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                    .navigationTitle(allSheetTitle)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showAllSheet = false }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            if let shareDocument {
                                ShareLink(item: shareDocument) {
                                    Label("Export CSV", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }
            }

            // 列選択（複数を連続でON/OFF & 並べ替え可能）
            .sheet(isPresented: $showColumnSheet) {
                ColumnPickerSheet(allColumns: Column.allCases, selected: $selectedColumns)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .overlay {
            if isMergingDailyCSV {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Merging CSVs…")
                        .padding(20)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - ファイル一覧
    private func reloadFiles() {
        rows.removeAll(); rawPreview.removeAll()
        files.removeAll(); dailyGroups.removeAll()
        folderBM.withAccess { folder in
            // 再帰的に enumerator で .csv を全部集める
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey]
            let e = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .producesRelativePathURLs]
            )

            var found: [FileItem] = []
            while let u = e?.nextObject() as? URL {
                let rv = try? u.resourceValues(forKeys: Set(keys))
                if rv?.isRegularFile == true, u.pathExtension.lowercased() == "csv" {
                    let modified = rv?.contentModificationDate ?? .distantPast
                    let resolvedURL = u.isFileURL ? u : folder.appendingPathComponent(u.relativePath)
                    let day = dayFolderName(for: resolvedURL, baseFolder: folder)
                    found.append(FileItem(url: resolvedURL, dayFolder: day, modifiedAt: modified))
                }
            }

            // 表示順：
            // 1) *_wflat_* or *_flat_* を優先
            // 2) 更新日が新しい順
            let sorted = found.sorted { a, b in
                let af = a.url.lastPathComponent.contains("_wflat_") || a.url.lastPathComponent.contains("_flat_")
                let bf = b.url.lastPathComponent.contains("_wflat_") || b.url.lastPathComponent.contains("_flat_")
                if af != bf { return af && !bf }
                return a.modifiedAt > b.modifiedAt
            }
            files = sorted

            let grouped = Dictionary(grouping: sorted, by: { $0.dayFolder })
            dailyGroups = grouped.map { key, value in
                let ordered = value.sorted { $0.modifiedAt > $1.modifiedAt }
                return DailyGroup(day: key, files: ordered)
            }
            .sorted { lhs, rhs in
                // ISO形式日付優先、それ以外は文字列比較
                let lDate = LibraryView.isoDayFormatter.date(from: lhs.day)
                let rDate = LibraryView.isoDayFormatter.date(from: rhs.day)
                if let lDate, let rDate { return lDate > rDate }
                if let lDate { return true }
                if let rDate { return false }
                return lhs.day > rhs.day
            }
        }
    }
    // MARK: - 一括読み込み
    private func loadAll() -> [LogRow] {
        var out: [LogRow] = []
        folderBM.withAccess { _ in
            for item in files {
                out.append(contentsOf: parseCSV(item.url))
            }
        }
        return out
    }

    private func mergeRows(for group: DailyGroup) -> [LogRow] {
        var out: [LogRow] = []
        folderBM.withAccess { _ in
            for item in group.files {
                out.append(contentsOf: parseCSV(item.url))
            }
        }
        return out
    }

    private func openDailyGroup(_ group: DailyGroup) {
        guard !group.files.isEmpty else { return }
        isMergingDailyCSV = true
        DispatchQueue.global(qos: .userInitiated).async {
            let merged = mergeRows(for: group)
            DispatchQueue.main.async {
                rows = merged
                searchText.removeAll()
                sortColumn = .date
                sortAscending = false
                applyDynamicSort()
                allSheetTitle = formattedDayTitle(group.day)
                shareFileName = makeMergedFileName(suffix: group.day)
                showAllSheet = true
                isMergingDailyCSV = false
            }
        }
    }

    private func makeMergedFileName(suffix: String) -> String {
        let sanitized = suffix.replacingOccurrences(of: "[^0-9A-Za-z_-]", with: "_", options: .regularExpression)
        let timestamp = LibraryView.exportTimestampFormatter.string(from: Date())
        return "PitTemp_\(sanitized)_merged_\(timestamp).csv"
    }

    private func dayFolderName(for url: URL, baseFolder: URL) -> String {
        let basePath = baseFolder.standardizedFileURL.path
        let absolutePath = url.standardizedFileURL.path
        let trimmed: String
        if absolutePath.hasPrefix(basePath) {
            trimmed = String(absolutePath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            trimmed = url.lastPathComponent
        }
        guard !trimmed.isEmpty else { return "(Root)" }
        let components = trimmed.split(separator: "/")
        if components.count >= 2 {
            return String(components[components.count - 2])
        } else if let first = components.first {
            return String(first)
        }
        return "(Root)"
    }

    private func formattedDayTitle(_ day: String) -> String {
        if day == "(Root)" {
            return NSLocalizedString("Unsorted files", comment: "Fallback day folder name")
        }
        if let date = LibraryView.isoDayFormatter.date(from: day) {
            return LibraryView.displayDayFormatter.string(from: date)
        }
        return day
    }

    private static let isoDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static let displayDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy MMM d (EEE)"
        df.locale = Locale.current
        return df
    }()

    private static let exportTimestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmm"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    // MARK: - 個別CSVビュー用ソート（wflatに合わせる）
    private func applySortForSingle() {
        rows.sort { a, b in
            switch sortKey {
            case .newest:
                // EXPORTEDが空ならSESSIONで比較
                let la = ISO8601DateFormatter().date(from: a.exportedISO).map { $0.timeIntervalSince1970 }
                        ?? ISO8601DateFormatter().date(from: a.sessionISO).map { $0.timeIntervalSince1970 } ?? 0
                let lb = ISO8601DateFormatter().date(from: b.exportedISO).map { $0.timeIntervalSince1970 }
                        ?? ISO8601DateFormatter().date(from: b.sessionISO).map { $0.timeIntervalSince1970 } ?? 0
                return la > lb
            case .oldest:
                let la = ISO8601DateFormatter().date(from: a.exportedISO).map { $0.timeIntervalSince1970 }
                        ?? ISO8601DateFormatter().date(from: a.sessionISO).map { $0.timeIntervalSince1970 } ?? 0
                let lb = ISO8601DateFormatter().date(from: b.exportedISO).map { $0.timeIntervalSince1970 }
                        ?? ISO8601DateFormatter().date(from: b.sessionISO).map { $0.timeIntervalSince1970 } ?? 0
                return la < lb
            case .track:   return a.track.localizedCaseInsensitiveCompare(b.track) == .orderedAscending
            case .date:    return a.date.localizedCaseInsensitiveCompare(b.date) == .orderedAscending
            case .car:     return a.car.localizedCaseInsensitiveCompare(b.car) == .orderedAscending
            case .tyre:    return a.tyre.localizedCaseInsensitiveCompare(b.tyre) == .orderedAscending
            case .driver:  return a.driver.localizedCaseInsensitiveCompare(b.driver) == .orderedAscending
            case .checker: return a.checker.localizedCaseInsensitiveCompare(b.checker) == .orderedAscending
            case .wheel:   return a.wheel < b.wheel
            }
        }
    }

    // MARK: - ALL表示用ソート（任意列）
    private func applyDynamicSort() {
        rows.sort { a, b in
            let lhs = cell(a, sortColumn)
            let rhs = cell(b, sortColumn)
            if sortColumn == .out || sortColumn == .cl || sortColumn == .inT {
                let la = Double(lhs) ?? -Double.infinity
                let rb = Double(rhs) ?? -Double.infinity
                return sortAscending ? (la < rb) : (la > rb)
            } else if sortColumn == .exported || sortColumn == .uploaded || sortColumn == .session {
                let fa = ISO8601DateFormatter().date(from: lhs) ?? .distantPast
                let fb = ISO8601DateFormatter().date(from: rhs) ?? .distantPast
                return sortAscending ? (fa < fb) : (fa > fb)
            } else {
                return sortAscending
                    ? (lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending)
                    : (lhs.localizedCaseInsensitiveCompare(rhs) == .orderedDescending)
            }
        }
    }

    // 任意列→表示文字列
    private func cell(_ r: LogRow, _ c: Column) -> String {
        switch c {
        case .track: return r.track
        case .date:  return r.date
        case .time:  return r.time
        case .car:   return r.car
        case .driver:return r.driver
        case .tyre:  return r.tyre
        case .lap:   return r.lap
        case .checker:return r.checker
        case .wheel: return r.wheel
        case .out:   return r.outStr
        case .cl:    return r.clStr
        case .inT:   return r.inStr
        case .memo:  return r.memo
        case .session: return r.sessionISO
        case .exported: return r.exportedISO
        case .uploaded: return r.uploadedISO
        }
    }

    // MARK: - CSVパーサ（wflat → 旧flat → さらに旧形式の順）
    private func parseCSV(_ url: URL) -> [LogRow] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first else { return [] }

        // 1) wheel-flat 新形式（13〜16列）
        if header.hasPrefix("TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN") {
            var out: [LogRow] = []
            for line in lines.dropFirst() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let c = splitCSV(line)
                guard c.count >= 13 else { continue }
                let session  = (c.count > 13) ? c[13] : ""
                let exported = (c.count > 14) ? c[14] : ""
                let uploaded = (c.count > 15) ? c[15] : ""
                out.append(LogRow(
                    track: c[0], date: c[1], car: c[2], driver: c[3], tyre: c[4], time: c[5], lap: c[6], checker: c[7],
                    wheel: c[8], outStr: c[9], clStr: c[10], inStr: c[11], memo: c[12],
                    sessionISO: session, exportedISO: exported, uploadedISO: uploaded
                ))
            }
            return out
        }

        // 2) 旧flat（行=wheel-zone、列にPEAKC…）→ wflatへ変換集約
        if header.hasPrefix("TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,ZONE,PEAKC,START,END,VIA,MEMO") {
            // wheel毎に集約
            var acc: [String: (track:String,date:String,car:String,driver:String,tyre:String,time:String,lap:String,checker:String,out:String,cl:String,inS:String,memo:String,session:String,exported:String,uploaded:String)] = [:]
            for line in lines.dropFirst() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let c = splitCSV(line)
                guard c.count >= 15 else { continue }
                let wheel = c[8], zone = c[9], peak = c[10]
                var e = acc[wheel] ?? (c[0],c[1],c[2],c[3],c[4],c[5],c[6],c[7],"","","",c[14], "", "", "")
                switch zone.uppercased() {
                case "OUT": e.out = peak
                case "CL":  e.cl  = peak
                case "IN":  e.inS = peak
                default: break
                }
                acc[wheel] = e
            }
            return acc.map { (wheel, v) in
                LogRow(track: v.track, date: v.date, car: v.car, driver: v.driver, tyre: v.tyre, time: v.time, lap: v.lap, checker: v.checker,
                       wheel: wheel, outStr: v.out, clStr: v.cl, inStr: v.inS, memo: v.memo,
                       sessionISO: v.session, exportedISO: v.exported, uploadedISO: v.uploaded)
            }
        }

        // 3) さらに旧形式 …必要なら以前のパーサを移植
        return []
    }

    private func splitCSV(_ line: String) -> [String] {
        var out: [String] = [], cur = ""; var inQ = false
        for ch in line {
            if ch == "\"" { inQ.toggle() }
            else if ch == "," && !inQ { out.append(cur); cur.removeAll() }
            else { cur.append(ch) }
        }
        out.append(cur)
        return out.map { $0.replacingOccurrences(of: "\"\"", with: "\"") }
    }
}

struct DriveBrowserView: View {
    @EnvironmentObject var driveService: GoogleDriveService
    @State private var selection = Set<String>()
    @State private var sortOption: DriveSortOption = .modifiedNewest
    @State private var searchText: String = ""
    @State private var isDownloading = false
    @State private var downloadMessage: String? = nil

    private var filteredFiles: [GoogleDriveService.DriveCSVFile] {
        let files = driveService.files
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [GoogleDriveService.DriveCSVFile]
        if trimmed.isEmpty {
            base = files
        } else {
            base = files.filter { file in
                let haystack = [
                    file.name,
                    file.driver,
                    file.track,
                    file.car,
                    file.deviceID,
                    file.deviceName,
                    file.sessionID?.uuidString ?? "",
                    file.dayFolder
                ].map { $0.lowercased() }
                let needle = trimmed.lowercased()
                return haystack.contains { $0.contains(needle) }
            }
        }

        return base.sorted { lhs, rhs in
            switch sortOption {
            case .modifiedNewest:
                let lhsDate = lhs.modifiedTime ?? lhs.createdTime ?? .distantPast
                let rhsDate = rhs.modifiedTime ?? rhs.createdTime ?? .distantPast
                return lhsDate > rhsDate
            case .driver:
                return lhs.driver.localizedCaseInsensitiveCompare(rhs.driver) == .orderedAscending
            case .track:
                return lhs.track.localizedCaseInsensitiveCompare(rhs.track) == .orderedAscending
            case .car:
                return lhs.car.localizedCaseInsensitiveCompare(rhs.car) == .orderedAscending
            case .sessionID:
                return (lhs.sessionID?.uuidString ?? "") < (rhs.sessionID?.uuidString ?? "")
            case .device:
                return lhs.deviceID.localizedCaseInsensitiveCompare(rhs.deviceID) == .orderedAscending
            }
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filteredFiles) { file in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(file.name)
                            .font(.headline)
                        Spacer()
                        if let modified = file.modifiedTime ?? file.createdTime {
                            Text(modified, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text("Driver")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(file.driver.ifEmpty("-"))
                                .font(.caption)
                        }
                        GridRow {
                            Text("Track")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(file.track.ifEmpty("-"))
                                .font(.caption)
                        }
                        GridRow {
                            Text("Car")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(file.car.ifEmpty("-"))
                                .font(.caption)
                        }
                        GridRow {
                            Text("Device")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(file.deviceName.ifEmpty(file.deviceID.ifEmpty("-")))
                                .font(.caption)
                        }
                        if let sessionID = file.sessionID {
                            GridRow {
                                Text("Session")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(sessionID.uuidString)
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        GridRow {
                            Text("Folder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(file.dayFolder)
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Drive CSVs")
        .toolbar { toolbarContent }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .task { await driveService.refreshFileList() }
        .alert("Download complete", isPresented: Binding(
            get: { downloadMessage != nil },
            set: { if !$0 { downloadMessage = nil } }
        )) {
            Button("OK", role: .cancel) { downloadMessage = nil }
        } message: {
            Text(downloadMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Picker("Sort", selection: $sortOption) {
                    ForEach(DriveSortOption.allCases) { option in
                        Label(option.title, systemImage: option.icon)
                            .tag(option)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            EditButton()

            Button {
                Task { await driveService.refreshFileList() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            Button {
                Task { await downloadSelection() }
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
            .disabled(selection.isEmpty || isDownloading)
        }
    }

    private func downloadSelection() async {
        guard !selection.isEmpty else { return }
        isDownloading = true
        defer { isDownloading = false }

        var successCount = 0
        var failures: [String] = []
        for id in selection {
            guard let file = driveService.files.first(where: { $0.id == id }) else { continue }
            do {
                let destination = try await driveService.download(file: file)
                successCount += 1
                print("Downloaded \(file.name) -> \(destination.path)")
            } catch {
                failures.append("\(file.name): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            downloadMessage = "Downloaded \(successCount). Failed: \n" + failures.joined(separator: "\n")
        } else {
            downloadMessage = "Downloaded \(successCount) file(s) to DriveDownloads folder."
        }
    }
}

private enum DriveSortOption: String, CaseIterable, Identifiable {
    case modifiedNewest
    case driver
    case track
    case car
    case sessionID
    case device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modifiedNewest: return "Newest first"
        case .driver: return "Driver"
        case .track: return "Track"
        case .car: return "Car"
        case .sessionID: return "Session ID"
        case .device: return "Device"
        }
    }

    var icon: String {
        switch self {
        case .modifiedNewest: return "clock.arrow.circlepath"
        case .driver: return "person"
        case .track: return "flag.checkered"
        case .car: return "car"
        case .sessionID: return "number"
        case .device: return "iphone"
        }
    }
}

// MARK: - 個別CSVのシンプルテーブル
private struct SingleTableView: View {
    let rows: [LogRow]
    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(r.track)  \(r.date)  \(r.car) / \(r.tyre)")
                            .font(.subheadline).bold()
                        Spacer()
                        Text(r.wheel).font(.subheadline)
                    }
                    HStack {
                        Text("OUT \(r.outStr.isEmpty ? "-" : r.outStr)  CL \(r.clStr.isEmpty ? "-" : r.clStr)  IN \(r.inStr.isEmpty ? "-" : r.inStr)")
                            .monospacedDigit()
                        Text("by \(r.driver)").foregroundStyle(.secondary)
                        Spacer()
                        Text(r.exportedISO.isEmpty ? r.sessionISO : r.exportedISO)
                            .foregroundStyle(.secondary).font(.footnote)
                    }
                    if !r.memo.isEmpty {
                        Text("Memo: \(r.memo)").font(.footnote)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            }
        }
    }
}

// MARK: - 列ピッカー（複数トグル & 並べ替え）
private struct ColumnPickerSheet: View {
    let allColumns: [Column]
    @Binding var selected: [Column]

    @Environment(\.dismiss) private var dismiss
    @State private var working: [Column] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Select All") { working = allColumns; selected = working }
                        Spacer()
                        Button("Select None") { working.removeAll(); selected = working }
                    }
                }
                Section("Columns") {
                    ForEach(working, id: \.self) { col in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                            Toggle(col.rawValue, isOn: Binding(
                                get: { selected.contains(col) },
                                set: { isOn in
                                    if isOn {
                                        if !selected.contains(col) { selected.append(col) }
                                    } else {
                                        selected.removeAll { $0 == col }
                                    }
                                }
                            ))
                        }
                    }
                    .onMove { from, to in
                        working.move(fromOffsets: from, toOffset: to)
                        selected.sort { a, b in
                            (working.firstIndex(of: a) ?? 0) < (working.firstIndex(of: b) ?? 0)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Columns")
            .toolbar { Button("Close") { dismiss() } }
            .onAppear {
                let rest = allColumns.filter { !selected.contains($0) }
                working = selected + rest
            }
        }
    }
}
