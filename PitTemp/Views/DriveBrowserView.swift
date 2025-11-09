import SwiftUI

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

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
