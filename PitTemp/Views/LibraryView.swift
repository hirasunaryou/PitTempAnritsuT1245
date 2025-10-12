// LibraryView.swift

import SwiftUI
import Foundation

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
    case track = "TRACK", date="DATE", car="CAR", driver="DRIVER", tyre="TYRE"
    case lap="LAP", checker="CHECKER", wheel="WHEEL"
    case out="OUT", cl="CL", inT="IN", memo="MEMO", exported="EXPORTED", uploaded="UPLOADED"
    var id: String { rawValue }
}

// URLをそのままIdentifiableに拡張しない（将来衝突回避）ための薄いラッパ
struct FileItem: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - LibraryView
struct LibraryView: View {
    @EnvironmentObject var folderBM: FolderBookmark

    // ファイル一覧
    @State private var files: [FileItem] = []

    // 個別CSV表示用
    @State private var rows: [LogRow] = []
    @State private var sortKey: SortKey = .newest
    @State private var selectedFile: FileItem? = nil
    @State private var rawPreview: String = ""

    // ALL表示用
    @State private var showAllSheet = false
    @State private var searchText = ""
    @State private var selectedColumns: [Column] = [.track,.date,.car,.tyre,.wheel,.out,.cl,.inT,.memo,.exported,.uploaded]
    @State private var sortColumn: Column = .date
    @State private var sortAscending: Bool = true
    @State private var showColumnSheet = false

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
            } else if [.exported, .uploaded].contains(sortColumn) {
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

    var body: some View {
        NavigationStack {
            List {
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
                                let dt = (try? item.url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate)?
                                    .formatted(date:.abbreviated, time:.shortened) ?? ""
                                Text(dt).font(.footnote).foregroundStyle(.secondary)
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
                        applyDynamicSort()
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
                            VStack(alignment: .leading, spacing: 8) {
                                // ヘッダ行（タップでその列ソート、2回目で昇降反転）
                                HStack {
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
                                                Text(col.rawValue).font(.footnote).bold()
                                                if sortColumn == col {
                                                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                                        .font(.caption2)
                                                }
                                            }
                                            .frame(minWidth: 110, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                Divider()

                                // データ行
                                ForEach(visibleSortedRows) { r in
                                    HStack {
                                        ForEach(selectedColumns) { col in
                                            Text(cell(r, col))
                                                .font(.footnote).monospacedDigit()
                                                .frame(minWidth: 110, alignment: .leading)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(.secondarySystemBackground)))
                                }
                            }
                            .padding()
                        }
                    }
                    .navigationTitle("All CSVs")
                    .toolbar { Button("Close") { showAllSheet = false } }
                }
            }

            // 列選択（複数を連続でON/OFF & 並べ替え可能）
            .sheet(isPresented: $showColumnSheet) {
                ColumnPickerSheet(allColumns: Column.allCases, selected: $selectedColumns)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - ファイル一覧
    private func reloadFiles() {
        rows.removeAll(); rawPreview.removeAll()
        folderBM.withAccess { folder in
            let all = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []

            // CSVのみ。*_wflat_* や *_flat_* を優先表示
            let csvs = all.filter{ $0.pathExtension.lowercased() == "csv" }
            let sorted = csvs.sorted { a,b in
                let aFlat = a.lastPathComponent.contains("_wflat_") || a.lastPathComponent.contains("_flat_")
                let bFlat = b.lastPathComponent.contains("_wflat_") || b.lastPathComponent.contains("_flat_")
                if aFlat != bFlat { return aFlat && !bFlat }
                let da = (try? a.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            files = sorted.map { FileItem(url: $0) }
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
            } else if sortColumn == .exported || sortColumn == .uploaded {
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
