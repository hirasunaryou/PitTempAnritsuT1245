//
//  FolderBookmark.swift
//  PitTemp
//
//  役割: iCloud Drive など外部フォルダの URL を「ブックマーク化」して永続保存
//  初心者向けメモ:
//   - iOSでは bookmarkData(options: []) を保存して、使うときに
//     startAccessingSecurityScopedResource() / stopAccessing... で一時的に権限を開く
//

import Foundation
import SwiftUI

enum UploadUIState { case idle, uploading, done, failed(String) }

final class FolderBookmark: ObservableObject {
    // UserDefaults に生の bookmarkData を保存（小サイズなので AppStorage でOK）
    @AppStorage("sharedFolder.bookmark") private var bookmarkData: Data?

    // 復元済みのURL（UI表示用）
    @Published private(set) var folderURL: URL?

    // UploadボタンのUI状態（連打抑止のため）
    @Published var statusLabel: UploadUIState = .idle

    // MARK: Save / Restore

    /// 保存済みの bookmarkData から URL を復元（必要なら stale 更新）
    @discardableResult
    func restore() -> URL? {
        guard let data = bookmarkData else { return nil }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            folderURL = url
            return url
        } catch {
            print("Bookmark restore failed:", error)
            return nil
        }
    }

    // MARK: Scoped Access Helper

    /// 実アクセス時だけスコープを開く。戻り値は body の戻り値。
    @discardableResult
    func withAccess<R>(_ body: (URL) throws -> R) rethrows -> R? {
        guard let url = folderURL ?? restore() else { return nil }
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    // MARK: Save chosen folder

    /// iCloud Drive などから選ばれたフォルダを bookmarkData 化して保存
    func save(url: URL) {
        // 一時的にアクセスを開く（存在確認と権限付与のため）
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }

        // フォルダ実在チェック
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            print("Bookmark save failed: not a directory")
            return
        }
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmarkData = data
            folderURL = url
            statusLabel = .idle
        } catch {
            print("Bookmark save failed:", error)
        }
    }

    // MARK: Upload (CSV → 共有フォルダにコピー)
    /// Export済みCSVをアップロード時刻を刻印してから共有フォルダへコピー。
    /// - 連打吸収（statusLabel で制御）
    /// - 同名があれば _1, _2 ... を付けて重複回避
    func upload(file originalCSV: URL) {
        // 連打ガード
        guard case .idle = statusLabel else { return }
        statusLabel = .uploading

        // 保存先フォルダを復元（未設定なら failed）
        guard let folder = folderURL ?? restore() else {
            statusLabel = .failed("No folder")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.statusLabel = .idle }
            return
        }

        // 刻印するアップロード時刻（ISO）
        let uploadedISO: String = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: Date())
        }()

        DispatchQueue.global().async {
            // フォルダのセキュリティスコープを開く
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }

            // 1) 一時ファイルに UPLOADED_AT_ISO を刻印
            guard let stamped = self.makeUploadedStampedCopy(from: originalCSV, uploadedISO: uploadedISO) else {
                DispatchQueue.main.async {
                    self.statusLabel = .failed("Stamp failed")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.statusLabel = .idle }
                }
                return
            }

            // 2) 共有フォルダへコピー（同名回避）
            let fm = FileManager.default
            var dest = folder.appendingPathComponent(stamped.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                let base = dest.deletingPathExtension().lastPathComponent
                let ext  = dest.pathExtension
                var i = 1
                while fm.fileExists(atPath: dest.path) {
                    let candidate = folder.appendingPathComponent("\(base)_\(i)" + (ext.isEmpty ? "" : ".\(ext)"))
                    dest = candidate
                    i += 1
                }
            }

            do {
                try fm.copyItem(at: stamped, to: dest)
                DispatchQueue.main.async {
                    self.statusLabel = .done
                    // 少し表示してから idle に戻す（UI固着回避）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.statusLabel = .idle
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel = .failed(error.localizedDescription)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.statusLabel = .idle
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// 既存 CSV（wheel-flat 形式想定）に UPLOADED_AT_ISO を埋めたコピーを /Documents に作る
    private func makeUploadedStampedCopy(from original: URL, uploadedISO: String) -> URL? {
        guard let text = try? String(contentsOf: original, encoding: .utf8) else { return nil }
        guard let firstNL = text.firstIndex(of: "\n") else { return nil }
        let header = String(text[..<firstNL])

        // 期待ヘッダ: “…,UPLOADED_AT_ISO” まで含む
        guard header.hasPrefix("TRACK,DATE,CAR,DRIVER,TYRE,TIME,LAP,CHECKER,WHEEL,OUT,CL,IN,MEMO,SESSION_START_ISO,EXPORTED_AT_ISO,UPLOADED_AT_ISO")
        else { return nil }

        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let body = lines.dropFirst().map { line -> String in
            var cols = splitCSV(line)
            if cols.count >= 16 { cols[15] = uploadedISO } // 0..15 の16列目
            return cols.joined(separator: ",")
        }.joined(separator: "\n")

        let stamped = ([header, body].joined(separator: "\n") + "\n")
        let tmp = original.deletingLastPathComponent()
            .appendingPathComponent(original.lastPathComponent.replacingOccurrences(of: ".csv", with: "_uploaded.csv"))
        try? Data(stamped.utf8).write(to: tmp)
        return tmp
    }

    /// CSV1行をカンマ+ダブルクオート対応で分割
    private func splitCSV(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQ = false
        for ch in line {
            if ch == "\"" { inQ.toggle() }
            else if ch == "," && !inQ { out.append(cur); cur.removeAll() }
            else { cur.append(ch) }
        }
        out.append(cur)
        return out.map { $0.replacingOccurrences(of: "\"\"", with: "\"") }
    }
}
