import XCTest
@testable import PitTemp

/// CSVExporter の出力仕様を固定するテスト。
/// ファイル名のサニタイズと基本的なヘッダー生成を確認する。
final class CSVExporterTests: XCTestCase {

    func testExportUsesSanitizedFileNameAndCreatesCSV() throws {
        // HOME を一時ディレクトリに切り替えて Documents パスを隔離する。
        let tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        let originalHome = getenv("HOME").flatMap { String(cString: $0) }
        setenv("HOME", tempHome.path, 1)
        defer {
            if let originalHome { setenv("HOME", originalHome, 1) }
            try? FileManager.default.removeItem(at: tempHome)
        }

        // 許容外文字を含むメタ情報でファイル名サニタイズを検証。
        let meta = MeasureMeta(
            track: "鈴鹿/本コース",
            date: "2025-01-01",
            car: "GR-8<>",
            driver: "山田 太郎",
            tyre: "R3",
            time: "",
            lap: "",
            checker: ""
        )
        let exporter = CSVExporter()
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let url = try exporter.exportWFlat(
            meta: meta,
            results: [],
            wheelMemos: [:],
            wheelPressures: [.FL: 195.5],
            sessionStart: Date(timeIntervalSince1970: 0),
            deviceName: "AnritsuM-試作#1",
            sessionID: sessionID,
            deviceIdentity: DeviceIdentity(id: "dev", name: "デバイス")
        )

        // ファイルが作成され、Documents 配下（tempHome/Library/...）に置かれていることを確認。
        XCTAssertTrue(url.path.contains(tempHome.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // サニタイズ済みのファイル名: 日本語・記号が `_` に置換され、空白は除外される。
        XCTAssertTrue(url.lastPathComponent.hasPrefix("session-\(sessionID.uuidString)-"))
        XCTAssertFalse(url.lastPathComponent.contains(" "))
        XCTAssertFalse(url.lastPathComponent.contains("<"))
        XCTAssertFalse(url.lastPathComponent.contains("/"))

        // 旧 wflat ヘッダーが書き込まれていることを軽く確認。
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("TRACK,DATE,CAR"))
    }
}
