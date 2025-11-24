// PitTemp/Data/SessionFileCoordinator.swift
import Foundation

/// アップロード手段（例: iCloud の共有フォルダ経由）を抽象化するための最小プロトコル。
/// FolderBookmark から切り出すことで、ViewModel 側が具体型を知らずに済む。
protocol SessionFileUploading {
    func uploadSessionFile(_ file: URL, metadata: DriveCSVMetadata)
}

/// CSV 出力とアップロードをまとめて扱うファサード層。
/// ViewModel からはこのプロトコルだけを見ればよく、CSVExporter / FolderBookmark
/// との結合点を一か所に集約する。
protocol SessionFileCoordinating {
    func exportWFlat(
        context: SessionFileContext,
        results: [MeasureResult],
        wheelMemos: [WheelPos: String],
        wheelPressures: [WheelPos: Double]
    ) throws -> SessionFileExport

    func uploadIfPossible(_ export: SessionFileExport)
}

struct SessionFileExport {
    let url: URL
    let metadata: DriveCSVMetadata
}

final class SessionFileCoordinator: SessionFileCoordinating {
    /// CSV をファイルに書き出す役。デフォルトは既存の CSVExporter を流用。
    private let exporter: CSVExporting
    /// iCloud などへ渡す「出口」。nil ならアップロードせずエクスポートのみ。
    private let uploader: SessionFileUploading?

    init(exporter: CSVExporting = CSVExporter(), uploader: SessionFileUploading? = nil) {
        self.exporter = exporter
        self.uploader = uploader
    }

    func exportWFlat(
        context: SessionFileContext,
        results: [MeasureResult],
        wheelMemos: [WheelPos: String],
        wheelPressures: [WheelPos: Double]
    ) throws -> SessionFileExport {
        // 出力メタとセッション開始時刻をまとめて CSVExporter に橋渡しする。
        let exportedAt = Date()
        let url = try exporter.exportWFlat(
            meta: context.meta,
            results: results,
            wheelMemos: wheelMemos,
            wheelPressures: wheelPressures,
            sessionStart: context.sessionBeganAt,
            deviceName: context.deviceName,
            deviceModelLabel: context.deviceModelLabel,
            sessionID: context.sessionID,
            sessionReadableID: context.sessionReadableID,
            deviceIdentity: context.deviceIdentity
        )
        let metadata = context.driveMetadata(exportedAt: exportedAt)
        return SessionFileExport(url: url, metadata: metadata)
    }

    func uploadIfPossible(_ export: SessionFileExport) {
        // uploader が nil なら何もしない。「可能ならアップロード」という挙動を
        // 明示することで、ViewModel 側は設定値だけを気にすれば良い。
        uploader?.uploadSessionFile(export.url, metadata: export.metadata)
    }
}

extension FolderBookmark: SessionFileUploading {
    func uploadSessionFile(_ file: URL, metadata: DriveCSVMetadata) {
        upload(file: file, metadata: metadata)
    }
}
