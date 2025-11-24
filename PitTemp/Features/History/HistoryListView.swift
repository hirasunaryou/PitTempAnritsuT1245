import SwiftUI
import UniformTypeIdentifiers

struct HistoryListView: View {
    @ObservedObject var history: SessionHistoryStore
    var onSelect: (SessionHistorySummary) -> Void
    var onClose: () -> Void

    @State private var searchText: String = ""
    @State private var sortOption: HistorySortOption = .newest
    @State private var showImporter = false
    @State private var importReport: SessionHistoryImportReport? = nil
    @State private var importError: String? = nil

    private var filteredSummaries: [SessionHistorySummary] {
        let filtered = history.summaries.filter { summary in
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? true : summary.matches(search: searchText)
        }

        return filtered.sorted { lhs, rhs in
            switch sortOption {
            case .newest:
                return lhs.createdAt > rhs.createdAt
            case .oldest:
                return lhs.createdAt < rhs.createdAt
            case .car:
                return lhs.car.localizedCaseInsensitiveCompare(rhs.car) == .orderedAscending
            case .track:
                return lhs.track.localizedCaseInsensitiveCompare(rhs.track) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("一致する履歴がありません / No matching history entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if history.summaries.isEmpty {
                            Text("まだ履歴が保存されていません / No archives saved yet")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else {
                    ForEach(filteredSummaries) { summary in
                        NavigationLink {
                            HistoryDetailView(summary: summary, history: history, onLoad: onSelect)
                        } label: {
                            HistorySummaryRow(summary: summary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                onSelect(summary)
                            } label: {
                                Label("Load", systemImage: "square.and.arrow.down.on.square")
                            }
                            .tint(.accentColor)
                        }
                        .contextMenu {
                            Button {
                                onSelect(summary)
                            } label: {
                                Label("Load into editor / 編集用に読み込む", systemImage: "square.and.arrow.down.on.square")
                            }
                        }
                    }
                }
            }
            .navigationTitle("History / 履歴")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(HistorySortOption.allCases) { option in
                                Label(option.label, systemImage: option.icon)
                                    .tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }

                    Button("Close") { onClose() }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                handleImport(urls: urls)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("Import result / インポート結果", isPresented: Binding(
            get: { importReport != nil },
            set: { if !$0 { importReport = nil } }
        )) {
            Button("OK", role: .cancel) { importReport = nil }
        } message: {
            if let report = importReport {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Imported: \(report.importedCount)")
                    if report.hasFailures {
                        ForEach(report.failures) { failure in
                            Text("× \(failure.url.lastPathComponent): \(failure.reason)")
                                .font(.caption)
                        }
                    }
                }
            } else {
                EmptyView()
            }
        }
        .alert("Import error / インポートエラー", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func handleImport(urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                await history.importSnapshots(from: urls)
            }.value
            await MainActor.run {
                importReport = report
            }
        }
    }
}

private enum HistorySortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case car
    case track

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest first / 新しい順"
        case .oldest: return "Oldest first / 古い順"
        case .car: return "Car name / 車両名"
        case .track: return "Track / サーキット"
        }
    }

    var icon: String {
        switch self {
        case .newest: return "clock.arrow.circlepath"
        case .oldest: return "clock"
        case .car: return "car"
        case .track: return "flag.checkered"
        }
    }
}

