// PitTemp/Data/SessionFileCoordinator.swift
import Foundation

protocol SessionFileUploading {
    func uploadSessionFile(_ file: URL, metadata: DriveCSVMetadata)
}

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
    private let exporter: CSVExporting
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
        let exportedAt = Date()
        let url = try exporter.exportWFlat(
            meta: context.meta,
            results: results,
            wheelMemos: wheelMemos,
            wheelPressures: wheelPressures,
            sessionStart: context.sessionBeganAt,
            deviceName: context.deviceName,
            sessionID: context.sessionID,
            deviceIdentity: context.deviceIdentity
        )
        let metadata = context.driveMetadata(exportedAt: exportedAt)
        return SessionFileExport(url: url, metadata: metadata)
    }

    func uploadIfPossible(_ export: SessionFileExport) {
        uploader?.uploadSessionFile(export.url, metadata: export.metadata)
    }
}

extension FolderBookmark: SessionFileUploading {
    func uploadSessionFile(_ file: URL, metadata: DriveCSVMetadata) {
        upload(file: file, metadata: metadata)
    }
}
