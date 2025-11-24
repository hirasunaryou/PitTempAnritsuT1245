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
    fileprivate func canonicalCSVColumns(in timeZone: TimeZone) -> [String] {
        var columns = [track, date, car, driver, tyre, time, lap, checker, wheel, outStr, clStr, inStr, memo, sessionISO, exportedISO, uploadedISO]

        if let referenceDate = LibraryTimestampFormatter.referenceDate(for: self) {
            columns[1] = LibraryTimestampFormatter.exportDayString(from: referenceDate, timeZone: timeZone)
            columns[5] = LibraryTimestampFormatter.exportTimeString(from: referenceDate, timeZone: timeZone)
        }

        columns[13] = LibraryTimestampFormatter.exportISOString(from: sessionISO, timeZone: timeZone)
        columns[14] = LibraryTimestampFormatter.exportISOString(from: exportedISO, timeZone: timeZone)
        columns[15] = LibraryTimestampFormatter.exportISOString(from: uploadedISO, timeZone: timeZone)

        return columns
    }
}

private enum LibraryTimeZoneOption: String, CaseIterable, Identifiable {
    case tokyo
    case device
    case utc

    var id: String { rawValue }

    var timeZone: TimeZone {
        switch self {
        case .tokyo:
            return TimeZone(identifier: "Asia/Tokyo") ?? .current
        case .device:
            return .current
        case .utc:
            return TimeZone(secondsFromGMT: 0) ?? .current
        }
    }

    var localizedName: String {
        switch self {
        case .tokyo:
            return "Japan Standard Time"
        case .device:
            return NSLocalizedString("Device local time", comment: "Time zone menu item")
        case .utc:
            return "Coordinated Universal Time"
        }
    }

    func label(for date: Date = Date()) -> String {
        let tz = timeZone
        let abbreviation = tz.abbreviation(for: date) ?? tz.identifier
        let offset = tz.secondsFromGMT(for: date)
        let hours = offset / 3600
        let minutes = abs(offset / 60) % 60
        let sign = offset >= 0 ? "+" : "-"
        return "\(abbreviation) (UTC\(sign)\(String(format: "%02d:%02d", abs(hours), minutes)))"
    }

    func abbreviation(for date: Date = Date()) -> String {
        timeZone.abbreviation(for: date) ?? fileSuffix
    }

    var fileSuffix: String {
        switch self {
        case .tokyo:
            return "JST"
        case .device:
            return "LOCAL"
        case .utc:
            return "UTC"
        }
    }
}

private enum ShareFileSource {
    case generated(suffix: String)
    case fixed(name: String)
}

private struct LibraryTimestampFormatter {
    private static let parserWithFraction: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private static let parserWithoutFraction: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    private static var exportISOFormatterCache: [String: ISO8601DateFormatter] = [:]
    private static var exportDayFormatterCache: [String: DateFormatter] = [:]
    private static var exportTimeFormatterCache: [String: DateFormatter] = [:]
    private static var displayFormatterCache: [String: DateFormatter] = [:]
    private static var displayDateFormatterCache: [String: DateFormatter] = [:]
    private static var displayTimeFormatterCache: [String: DateFormatter] = [:]

    static func parse(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        if let date = parserWithFraction.date(from: iso) {
            return date
        }
        return parserWithoutFraction.date(from: iso)
    }

    static func exportISOString(from iso: String, timeZone: TimeZone) -> String {
        guard let date = parse(iso) else { return iso }
        let formatter = exportISOFormatter(for: timeZone)
        return formatter.string(from: date)
    }

    static func exportDayString(from date: Date, timeZone: TimeZone) -> String {
        let formatter = exportDayFormatter(for: timeZone)
        return formatter.string(from: date)
    }

    static func exportTimeString(from date: Date, timeZone: TimeZone) -> String {
        let formatter = exportTimeFormatter(for: timeZone)
        return formatter.string(from: date)
    }

    static func displayTimestamp(from iso: String, timeZone: TimeZone) -> String {
        guard let date = parse(iso) else { return iso }
        let formatter = displayTimestampFormatter(for: timeZone)
        let formatted = formatter.string(from: date)
        let abbreviation = timeZone.abbreviation(for: date) ?? timeZone.identifier
        return "\(formatted) (\(abbreviation))"
    }

    static func displayDate(from date: Date, timeZone: TimeZone) -> String {
        let formatter = displayDateFormatter(for: timeZone)
        return formatter.string(from: date)
    }

    static func displayTime(from date: Date, timeZone: TimeZone) -> String {
        let formatter = displayTimeFormatter(for: timeZone)
        return formatter.string(from: date)
    }

    static func referenceDate(for row: LogRow) -> Date? {
        if let exported = parse(row.exportedISO) {
            return exported
        }
        if let session = parse(row.sessionISO) {
            return session
        }
        return parse(row.uploadedISO)
    }

    private static func exportISOFormatter(for timeZone: TimeZone) -> ISO8601DateFormatter {
        let key = timeZone.identifier
        if let cached = exportISOFormatterCache[key] {
            return cached
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        formatter.timeZone = timeZone
        exportISOFormatterCache[key] = formatter
        return formatter
    }

    private static func exportDayFormatter(for timeZone: TimeZone) -> DateFormatter {
        let key = timeZone.identifier
        if let cached = exportDayFormatterCache[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        exportDayFormatterCache[key] = formatter
        return formatter
    }

    private static func exportTimeFormatter(for timeZone: TimeZone) -> DateFormatter {
        let key = timeZone.identifier
        if let cached = exportTimeFormatterCache[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        exportTimeFormatterCache[key] = formatter
        return formatter
    }

    private static func displayTimestampFormatter(for timeZone: TimeZone) -> DateFormatter {
        let key = timeZone.identifier
        if let cached = displayFormatterCache[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        displayFormatterCache[key] = formatter
        return formatter
    }

    private static func displayDateFormatter(for timeZone: TimeZone) -> DateFormatter {
        let key = timeZone.identifier
        if let cached = displayDateFormatterCache[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        displayDateFormatterCache[key] = formatter
        return formatter
    }

    private static func displayTimeFormatter(for timeZone: TimeZone) -> DateFormatter {
        let key = timeZone.identifier
        if let cached = displayTimeFormatterCache[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        displayTimeFormatterCache[key] = formatter
        return formatter
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

    static let defaultVisibleColumns: [Column] = [
        .track,
        .date,
        .time,
        .car,
        .tyre,
        .wheel,
        .out,
        .cl,
        .inT,
        .memo,
        .exported,
        .uploaded
    ]
}

private struct ActiveFilterToken: Identifiable, Hashable {
    let column: Column
    let text: String
    var id: String { "\(column.id)|\(text)" }
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
    let timeZone: TimeZone

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            Data(document.csvContent().utf8)
        }
        .suggestedFileName { document in
            document.fileName
        }
    }

    fileprivate func csvContent() -> String {
        guard !rows.isEmpty else {
            return Self.canonicalHeader.joined(separator: ",") + "\n"
        }

        let escapedRows = rows.map { row in
            row.canonicalCSVColumns(in: timeZone).map { Self.escape($0) }.joined(separator: ",")
        }
        return ([Self.canonicalHeader.joined(separator: ",")] + escapedRows).joined(separator: "\n") + "\n"
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
    @State private var summaryFiles: [FileItem] = []

    // 個別CSV表示用
    @State private var rows: [LogRow] = []
    @State private var sortKey: SortKey = .newest
    @State private var selectedFile: FileItem? = nil
    @State private var rawPreview: String = ""
    @State private var isMergingDailyCSV = false

    // ALL表示用
    @State private var showAllSheet = false
    @State private var searchText = ""
    @State private var selectedColumns: [Column] = Column.defaultVisibleColumns
    @State private var sortColumn: Column = .date
    @State private var sortAscending: Bool = true
    @State private var showColumnSheet = false
    @State private var pendingColumnSheet = false
    @State private var allSheetTitle = "All CSVs"
    @State private var timeZoneOption: LibraryTimeZoneOption = .tokyo
    @State private var shareSource: ShareFileSource = .generated(suffix: "all")
    @State private var columnFilters: [Column: String] = [:]
    @State private var filterEditorColumn: Column? = nil

    // 可視→検索→ソートを適用した配列
    private var visibleSortedRows: [LogRow] {
        // 1) 検索フィルタ
        let trimmedFilters = columnFilters.compactMapValues { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let columnFiltered: [LogRow]
        if trimmedFilters.isEmpty {
            columnFiltered = rows
        } else {
            columnFiltered = rows.filter { r in
                trimmedFilters.allSatisfy { (column, keyword) in
                    displayValue(r, column).localizedCaseInsensitiveContains(keyword)
                }
            }
        }

        let filtered: [LogRow]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = columnFiltered
        } else {
            let q = searchText.lowercased()
            filtered = columnFiltered.filter { r in
                selectedColumns.contains(where: { col in
                    displayValue(r, col).lowercased().contains(q)
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
                let fa = LibraryTimestampFormatter.parse(lhs) ?? .distantPast
                let fb = LibraryTimestampFormatter.parse(rhs) ?? .distantPast
                return sortAscending ? (fa < fb) : (fa > fb)
            } else {
                return sortAscending
                    ? (lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending)
                    : (lhs.localizedCaseInsensitiveCompare(rhs) == .orderedDescending)
            }
        })
    }

    private var shareDocument: MergedCSVDocument? {
        guard !rows.isEmpty else { return nil }
        return MergedCSVDocument(fileName: resolvedShareFileName, rows: visibleSortedRows, timeZone: timeZoneOption.timeZone)
    }

    private var resolvedShareFileName: String {
        switch shareSource {
        case .generated(let suffix):
            return makeMergedFileName(suffix: suffix, option: timeZoneOption)
        case .fixed(let name):
            return name
        }
    }

    var body: some View {
        NavigationStack {
            libraryList
                .navigationTitle("Library")
                .toolbar { libraryToolbar }
                .onChange(of: sortColumn) { _, _ in applyDynamicSort() }    // iOS17+ の2引数版
                .onChange(of: sortAscending) { _, _ in applyDynamicSort() } // 同上
                .onAppear { reloadFiles() }
        }
        .sheet(item: $selectedFile, content: singleFileSheet)
        .sheet(isPresented: $showAllSheet, content: allFilesSheet)
        .sheet(isPresented: $showColumnSheet) {
            ColumnPickerSheet(allColumns: Column.allCases, selected: $selectedColumns)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $filterEditorColumn) { column in
            ColumnFilterEditorSheet(
                column: column,
                initialText: columnFilters[column] ?? "",
                suggestions: buildSuggestions(for: column),
                onApply: { value in applyFilter(value, for: column) },
                onClear: { clearFilter(for: column) }
            )
        }
        .onChange(of: showAllSheet) { _, isPresented in
            if !isPresented, pendingColumnSheet {
                pendingColumnSheet = false
                showColumnSheet = true
            }
        }
        .overlay(mergeOverlay)
    }

    @ViewBuilder
    private var libraryList: some View {
        List {
            cloudSection

            if folderBM.folderURL != nil {
                quickSortSection
            }

            dailyCollectionsSection
            summarySection

            ForEach(files, id: \.self, content: fileRow)
        }
    }

    @ViewBuilder
    private var cloudSection: some View {
        Section("Cloud") {
            if settings.enableGoogleDriveUpload {
                NavigationLink {
                    DriveBrowserView()
                } label: {
                    Label("Google Drive", systemImage: "cloud")
                }
                .padding(.vertical, 4)
            } else {
                Label("Google Drive uploads disabled", systemImage: "cloud.slash")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var quickSortSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([SortKey.newest, .oldest, .track, .date, .car, .tyre, .driver, .checker, .wheel], id: \.self) { key in
                        Button(key.rawValue) {
                            sortKey = key
                            applySortForSingle()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var dailyCollectionsSection: some View {
        if !dailyGroups.isEmpty {
            Section("Daily collections") {
                ForEach(dailyGroups) { group in
                    Button { openDailyGroup(group) } label: { dailyCollectionRow(for: group) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if !summaryFiles.isEmpty {
            Section("Daily merged CSVs") {
                ForEach(summaryFiles) { item in
                    Button { openSummaryFile(item) } label: { summaryRow(for: item) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func dailyCollectionRow(for group: DailyGroup) -> some View {
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

    @ViewBuilder
    private func summaryRow(for item: FileItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(formattedDayTitle(item.dayFolder))
                    .font(.headline)
                HStack(spacing: 12) {
                    Label(item.url.lastPathComponent, systemImage: "doc.plaintext")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(item.modifiedAt, format: .dateTime.year().month().day().hour().minute())
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

    @ViewBuilder
    private func fileRow(for item: FileItem) -> some View {
        Button {
            rows = parseCSV(item.url)
            rawPreview = (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
            selectedFile = item
            applySortForSingle()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(item.url.lastPathComponent)
                        .font(.headline)
                    Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "doc.text")
            }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button("All") {
                rows = loadAll()
                searchText.removeAll()
                applyDynamicSort()
                allSheetTitle = "All CSVs"
                shareSource = .generated(suffix: "all")
                showAllSheet = true
            }

            Button("Columns") { openColumnPicker(closeAllSheetFirst: false) }

            Menu("Sort") {
                Picker("Column", selection: $sortColumn) {
                    ForEach(Column.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                Toggle("Ascending", isOn: $sortAscending)
            }

            Button { reloadFiles() } label: { Image(systemName: "arrow.clockwise") }
        }
    }

    @ViewBuilder
    private func singleFileSheet(file: FileItem) -> some View {
        NavigationStack {
            List {
                Section("RESULTS") {
                    Text("\(rows.count) rows")
                        .font(.headline)
                    if !rows.isEmpty {
                        SingleTableView(rows: rows, timeZone: timeZoneOption)
                    }
                }
                Section("RAW") {
                    ScrollView {
                        Text(rawPreview)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(file.url.lastPathComponent)
            .toolbar {
                Button("Close") { selectedFile = nil }
            }
        }
    }

    @ViewBuilder
    private func allFilesSheet() -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader

                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(visibleSortedRows.enumerated()), id: \.offset) { index, row in
                                rowView(row, index: index)
                            }
                        } header: {
                            headerRow
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(allSheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showAllSheet = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let shareDocument {
                        ShareLink(item: shareDocument, preview: SharePreview(Text(shareDocument.fileName))) {
                            Label("Export CSV (\(timeZoneOption.abbreviation()))", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer(minLength: 8)

                Menu {
                    ForEach(LibraryTimeZoneOption.allCases) { option in
                        Button {
                            timeZoneOption = option
                        } label: {
                            if option == timeZoneOption {
                                Label(option.label(), systemImage: "checkmark")
                            } else {
                                Text(option.label())
                            }
                        }
                    }
                } label: {
                    Label(timeZoneOption.abbreviation(), systemImage: "globe")
                        .labelStyle(.titleAndIcon)
                }

                Button {
                    openColumnPicker(closeAllSheetFirst: true)
                } label: {
                    Label("Columns", systemImage: "square.grid.2x2")
                }
            }

            Text(String(format: NSLocalizedString("Times shown in %@", comment: "Time zone description"), timeZoneOption.label()))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !activeFilterTokens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(activeFilterTokens) { token in
                            HStack(spacing: 4) {
                                Text("\(token.column.rawValue): \(token.text)")
                                    .font(.caption)
                                Button {
                                    clearFilter(for: token.column)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
    }

    private func rowView(_ row: LogRow, index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(selectedColumns) { col in
                Text(displayValue(row, col))
                    .font(.footnote.monospacedDigit())
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 120, alignment: .leading)
                    .background(
                        (index.isMultiple(of: 2) ? Color(.systemBackground) : Color(.secondarySystemBackground))
                            .overlay(
                                isFilterActive(col) ? Color.accentColor.opacity(0.08) : Color.clear
                            )
                    )
            }
        }
        .background(index.isMultiple(of: 2) ? Color(.systemBackground) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.vertical, 1)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(selectedColumns) { col in
                Button {
                    handleSortTap(for: col)
                } label: {
                    HStack(spacing: 6) {
                        Text(col.rawValue)
                            .font(.footnote.bold())
                        if sortColumn == col {
                            Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                        }
                        if isFilterActive(col) {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .font(.caption2)
                        }
                    }
                    .frame(minWidth: 120, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .background(isFilterActive(col) ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .highPriorityGesture(TapGesture(count: 2).onEnded { hideColumn(col) })
                .contextMenu {
                    if selectedColumns.count > 1 {
                        Button {
                            hideColumn(col)
                        } label: {
                            Label("Hide column", systemImage: "eye.slash")
                        }
                    }
                    Button {
                        openFilterEditor(for: col)
                    } label: {
                        Label(isFilterActive(col) ? "Edit filter" : "Filter…", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    if isFilterActive(col) {
                        Button(role: .destructive) {
                            clearFilter(for: col)
                        } label: {
                            Label("Clear filter", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .background(Color(.systemGroupedBackground))
    }

    private var activeFilterTokens: [ActiveFilterToken] {
        columnFilters.compactMap { key, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ActiveFilterToken(column: key, text: trimmed)
        }
        .sorted { lhs, rhs in
            let visibleOrder = selectedColumns
            let fallbackOrder = Column.allCases
            let lIndex = visibleOrder.firstIndex(of: lhs.column) ?? fallbackOrder.firstIndex(of: lhs.column) ?? 0
            let rIndex = visibleOrder.firstIndex(of: rhs.column) ?? fallbackOrder.firstIndex(of: rhs.column) ?? 0
            if lIndex == rIndex {
                return lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
            }
            return lIndex < rIndex
        }
    }

    private func handleSortTap(for column: Column) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    private func hideColumn(_ column: Column) {
        guard selectedColumns.count > 1 else { return }
        if let idx = selectedColumns.firstIndex(of: column) {
            selectedColumns.remove(at: idx)
        }
        if sortColumn == column, let first = selectedColumns.first {
            sortColumn = first
            sortAscending = true
        }
        clearFilter(for: column)
    }

    private func openColumnPicker(closeAllSheetFirst: Bool) {
        if closeAllSheetFirst, showAllSheet {
            pendingColumnSheet = true
            showAllSheet = false
        } else {
            pendingColumnSheet = false
            showColumnSheet = true
        }
    }

    private func isFilterActive(_ column: Column) -> Bool {
        guard let value = columnFilters[column]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !value.isEmpty
    }

    private func openFilterEditor(for column: Column) {
        filterEditorColumn = column
    }

    private func applyFilter(_ value: String, for column: Column) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            columnFilters.removeValue(forKey: column)
        } else {
            columnFilters[column] = trimmed
        }
    }

    private func clearFilter(for column: Column) {
        columnFilters.removeValue(forKey: column)
    }

    private func buildSuggestions(for column: Column) -> [String] {
        var seen: Set<String> = []
        var unique: [String] = []
        for raw in rows.map({ displayValue($0, column) }) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                unique.append(trimmed)
            }
            if unique.count >= 12 { break }
        }
        return unique
    }

    @ViewBuilder
    private var mergeOverlay: some View {
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
                    if resolvedURL.deletingLastPathComponent().lastPathComponent == LibraryView.summaryFolderName {
                        continue
                    }
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
                let leftDate = LibraryView.isoDayFormatter.date(from: lhs.day)
                let rightDate = LibraryView.isoDayFormatter.date(from: rhs.day)
                switch (leftDate, rightDate) {
                case let (l?, r?):
                    return l > r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (nil, nil):
                    return lhs.day > rhs.day
                }
            }
        }
        refreshSummaryFiles()
        let groupsSnapshot = dailyGroups
        scheduleDailySummarySync(for: groupsSnapshot)
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
        let latest = group.latestModified
        DispatchQueue.global(qos: .userInitiated).async {
            let merged = mergeRows(for: group)
            let wroteSummary = persistDailySummaryIfNeeded(rows: merged, day: group.day, latest: latest)
            DispatchQueue.main.async {
                rows = merged
                searchText.removeAll()
                sortColumn = .date
                sortAscending = false
                applyDynamicSort()
                allSheetTitle = formattedDayTitle(group.day)
                shareSource = .generated(suffix: group.day)
                showAllSheet = true
                isMergingDailyCSV = false
                if wroteSummary {
                    refreshSummaryFiles()
                }
            }
        }
    }

    private func openSummaryFile(_ item: FileItem) {
        let parsed = parseCSV(item.url)
        rows = parsed
        searchText.removeAll()
        sortColumn = .date
        sortAscending = false
        applyDynamicSort()
        allSheetTitle = formattedDayTitle(item.dayFolder)
        shareSource = .fixed(name: item.url.lastPathComponent)
        showAllSheet = true
    }

    private func makeMergedFileName(suffix: String, option: LibraryTimeZoneOption) -> String {
        let sanitized = suffix.replacingOccurrences(of: "[^0-9A-Za-z_-]", with: "_", options: .regularExpression)
        let now = Date()
        let timestamp = LibraryTimestampFormatter.exportDayString(from: now, timeZone: option.timeZone)
            + "_"
            + LibraryTimestampFormatter.exportTimeString(from: now, timeZone: option.timeZone).replacingOccurrences(of: ":", with: "")
        return "PitTemp_\(sanitized)_merged_\(timestamp)_\(option.fileSuffix).csv"
    }

    private func refreshSummaryFiles() {
        DispatchQueue.global(qos: .utility).async {
            let items = folderBM.withAccess { base -> [FileItem] in
                let summaryFolder = base.appendingPathComponent(LibraryView.summaryFolderName, isDirectory: true)
                let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
                guard FileManager.default.fileExists(atPath: summaryFolder.path) else { return [] }
                guard let urls = try? FileManager.default.contentsOfDirectory(
                    at: summaryFolder,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles]
                ) else {
                    return []
                }
                return urls.compactMap { url -> FileItem? in
                    guard url.pathExtension.lowercased() == "csv" else { return nil }
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    guard values?.isRegularFile == true else { return nil }
                    let dayKey = summaryDayKey(from: url) ?? url.deletingPathExtension().lastPathComponent
                    let modified = values?.contentModificationDate ?? .distantPast
                    return FileItem(url: url, dayFolder: dayKey, modifiedAt: modified)
                }
                .sorted { $0.modifiedAt > $1.modifiedAt }
            } ?? []

            DispatchQueue.main.async {
                summaryFiles = items
            }
        }
    }

    private func scheduleDailySummarySync(for groups: [DailyGroup]) {
        guard !groups.isEmpty, folderBM.folderURL != nil else { return }
        DispatchQueue.global(qos: .utility).async {
            var didWriteAny = false
            for group in groups {
                let latest = group.latestModified
                let needsUpdate = folderBM.withAccess { base -> Bool in
                    let summaryURL = LibraryView.summaryFileURL(for: group.day, baseFolder: base)
                    if FileManager.default.fileExists(atPath: summaryURL.path) {
                        let values = try? summaryURL.resourceValues(forKeys: [.contentModificationDateKey])
                        let summaryDate = values?.contentModificationDate ?? .distantPast
                        return summaryDate < latest
                    } else {
                        return true
                    }
                } ?? false

                guard needsUpdate else { continue }

                let merged = mergeRows(for: group)
                if persistDailySummaryIfNeeded(rows: merged, day: group.day, latest: latest) {
                    didWriteAny = true
                }
            }

            if didWriteAny {
                DispatchQueue.main.async {
                    refreshSummaryFiles()
                }
            }
        }
    }

    @discardableResult
    private func persistDailySummaryIfNeeded(rows: [LogRow], day: String, latest: Date) -> Bool {
        folderBM.withAccess { base -> Bool in
            let summaryURL = LibraryView.summaryFileURL(for: day, baseFolder: base)
            let fm = FileManager.default
            let shouldWrite: Bool
            if fm.fileExists(atPath: summaryURL.path) {
                let values = try? summaryURL.resourceValues(forKeys: [.contentModificationDateKey])
                let summaryDate = values?.contentModificationDate ?? .distantPast
                shouldWrite = summaryDate < latest
            } else {
                shouldWrite = true
            }

            guard shouldWrite else { return false }

            do {
                try fm.createDirectory(
                    at: summaryURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                let document = MergedCSVDocument(
                    fileName: summaryURL.lastPathComponent,
                    rows: rows,
                    timeZone: LibraryTimeZoneOption.tokyo.timeZone
                )
                guard let data = document.csvContent().data(using: .utf8) else { return false }
                try data.write(to: summaryURL, options: .atomic)
                return true
            } catch {
                print("[Summary] write failed:", error)
                return false
            }
        } ?? false
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

    private static let summaryFolderName = "DailyMerged"
    private static let summaryFileSuffix = "_PitTempDaily"

    private static func summaryFileURL(for day: String, baseFolder: URL) -> URL {
        let sanitized = sanitizedDayKey(day)
        let folder = baseFolder.appendingPathComponent(summaryFolderName, isDirectory: true)
        return folder.appendingPathComponent("\(sanitized)\(summaryFileSuffix).csv")
    }

    private static func sanitizedDayKey(_ day: String) -> String {
        let sanitized = day.replacingOccurrences(of: "[^0-9A-Za-z_-]", with: "_", options: .regularExpression)
        let collapsed = sanitized.replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "Daily" : trimmed
    }

    private func summaryDayKey(from url: URL) -> String? {
        let base = url.deletingPathExtension().lastPathComponent
        guard base.hasSuffix(LibraryView.summaryFileSuffix) else { return nil }
        let dayPart = String(base.dropLast(LibraryView.summaryFileSuffix.count))
        return dayPart.isEmpty ? nil : dayPart
    }

    // MARK: - 個別CSVビュー用ソート（wflatに合わせる）
    private func applySortForSingle() {
        rows.sort { a, b in
            switch sortKey {
            case .newest:
                // EXPORTEDが空ならSESSIONで比較
                let la = LibraryTimestampFormatter.parse(a.exportedISO)
                    ?? LibraryTimestampFormatter.parse(a.sessionISO)
                    ?? .distantPast
                let lb = LibraryTimestampFormatter.parse(b.exportedISO)
                    ?? LibraryTimestampFormatter.parse(b.sessionISO)
                    ?? .distantPast
                return la > lb
            case .oldest:
                let la = LibraryTimestampFormatter.parse(a.exportedISO)
                    ?? LibraryTimestampFormatter.parse(a.sessionISO)
                    ?? .distantPast
                let lb = LibraryTimestampFormatter.parse(b.exportedISO)
                    ?? LibraryTimestampFormatter.parse(b.sessionISO)
                    ?? .distantPast
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
                let fa = LibraryTimestampFormatter.parse(lhs) ?? .distantPast
                let fb = LibraryTimestampFormatter.parse(rhs) ?? .distantPast
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

    private func displayValue(_ row: LogRow, _ column: Column) -> String {
        let tz = timeZoneOption.timeZone
        switch column {
        case .date:
            if let reference = LibraryTimestampFormatter.referenceDate(for: row) {
                return LibraryTimestampFormatter.displayDate(from: reference, timeZone: tz)
            }
            return row.date
        case .time:
            if let reference = LibraryTimestampFormatter.referenceDate(for: row) {
                return LibraryTimestampFormatter.displayTime(from: reference, timeZone: tz)
            }
            return row.time
        case .session:
            return LibraryTimestampFormatter.displayTimestamp(from: row.sessionISO, timeZone: tz)
        case .exported:
            return LibraryTimestampFormatter.displayTimestamp(from: row.exportedISO, timeZone: tz)
        case .uploaded:
            return LibraryTimestampFormatter.displayTimestamp(from: row.uploadedISO, timeZone: tz)
        default:
            return cell(row, column)
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
                    file.sessionReadableID,
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
                        if !file.sessionReadableID.isEmpty {
                            GridRow {
                                Text("Session label")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(file.sessionReadableID)
                                    .font(.caption.monospaced())
                            }
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
    let timeZone: LibraryTimeZoneOption
    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(r.track)  \(dayText(for: r))  \(r.car) / \(r.tyre)")
                            .font(.subheadline).bold()
                        Spacer()
                        Text(r.wheel).font(.subheadline)
                    }
                    HStack {
                        Text("OUT \(r.outStr.isEmpty ? "-" : r.outStr)  CL \(r.clStr.isEmpty ? "-" : r.clStr)  IN \(r.inStr.isEmpty ? "-" : r.inStr)")
                            .monospacedDigit()
                        Text(timeText(for: r)).monospacedDigit().foregroundStyle(.secondary)
                        Text("by \(r.driver)").foregroundStyle(.secondary)
                        Spacer()
                        Text(timestampText(for: r))
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

    private func dayText(for row: LogRow) -> String {
        if let reference = LibraryTimestampFormatter.referenceDate(for: row) {
            return LibraryTimestampFormatter.displayDate(from: reference, timeZone: timeZone.timeZone)
        }
        return row.date
    }

    private func timeText(for row: LogRow) -> String {
        if let reference = LibraryTimestampFormatter.referenceDate(for: row) {
            return LibraryTimestampFormatter.displayTime(from: reference, timeZone: timeZone.timeZone)
        }
        return row.time
    }

    private func timestampText(for row: LogRow) -> String {
        let iso = row.exportedISO.isEmpty ? row.sessionISO : row.exportedISO
        return LibraryTimestampFormatter.displayTimestamp(from: iso, timeZone: timeZone.timeZone)
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

private struct ColumnFilterEditorSheet: View {
    let column: Column
    let initialText: String
    let suggestions: [String]
    let onApply: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    init(column: Column, initialText: String, suggestions: [String], onApply: @escaping (String) -> Void, onClear: @escaping () -> Void) {
        self.column = column
        self.initialText = initialText
        self.suggestions = suggestions
        self.onApply = onApply
        self.onClear = onClear
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle(Text("Filter \(column.rawValue)"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section(header: Text("Contains")) {
                TextField("Keyword", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if !suggestions.isEmpty {
                suggestionsSection
            }
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        Section("Suggestions") {
            ForEach(suggestions, id: \.self) { suggestion in
                suggestionRow(for: suggestion)
            }
        }
    }

    @ViewBuilder
    private func suggestionRow(for suggestion: String) -> some View {
        Button {
            text = suggestion
        } label: {
            HStack {
                Text(suggestion)
                Spacer()
                if text == suggestion {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .destructiveAction) {
            if !initialText.isEmpty || !text.isEmpty {
                Button("Clear") {
                    onClear()
                    dismiss()
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Apply") {
                onApply(text)
                dismiss()
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && initialText.isEmpty)
        }
    }
}
