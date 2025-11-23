import SwiftUI

struct HistoryDetailView: View {
    let summary: SessionHistorySummary
    @ObservedObject var history: SessionHistoryStore
    var onLoad: (SessionHistorySummary) -> Void

    @State private var snapshot: SessionSnapshot? = nil
    @State private var loadError: String? = nil
    @State private var showReport = false

    private static let metaLabelWidth: CGFloat = 96
    private static let timelineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        Group {
            if let snapshot {
                List {
                    metaSection(snapshot: snapshot)

                    if summary.hasTemperatures {
                        temperatureSection
                    }

                    if !snapshot.results.isEmpty {
                        measurementSection(results: snapshot.results)
                    }

                    if !snapshot.wheelMemos.isEmpty {
                        memoSection(memos: snapshot.wheelMemos)
                    }

                    if summary.hasPressures {
                        pressureSection(snapshot: snapshot)
                    }
                }
                .listStyle(.insetGrouped)
            } else if loadError != nil {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Failed to load / 読み込み失敗")
                        .font(.headline)
                    Text(loadError ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(summary.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSnapshot() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if snapshot != nil {
                    Button {
                        showReport = true
                    } label: {
                        Label("Report", systemImage: "doc.richtext")
                    }
                }
                Button {
                    onLoad(summary)
                } label: {
                    Label("Load", systemImage: "square.and.arrow.down.on.square")
                }
            }
        }
        .reportSheet(item: Binding(
            get: { showReport ? snapshot.map { ReportPayload(summary: summary, snapshot: $0) } : nil },
            set: { newValue in
                // fullScreenCover でも sheet でも閉じるときに nil が渡ってくるので、
                // それをトリガーにフラグを落とす。
                if newValue == nil { showReport = false }
            }
        )) { payload in
            NavigationStack {
                SessionReportView(summary: payload.summary, snapshot: payload.snapshot)
            }
        }
    }

    // sheet と fullScreenCover の両対応に必要な Identifiable コンテナ。
    private struct ReportPayload: Identifiable {
        let id = UUID()
        let summary: SessionHistorySummary
        let snapshot: SessionSnapshot
    }

    private func loadSnapshot() async {
        if snapshot != nil || loadError != nil { return }
        let loaded: SessionSnapshot? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let snapshot = history.snapshot(for: summary)
                continuation.resume(returning: snapshot)
            }
        }
        if let loaded {
            await MainActor.run { self.snapshot = loaded }
        } else {
            await MainActor.run { self.loadError = "履歴データの読み込みに失敗しました" }
        }
    }

    @ViewBuilder
    private func metaSection(snapshot: SessionSnapshot) -> some View {
        Section("Meta / メタ情報") {
            metaRow(title: "Track", value: displayValue(summary.track))
            metaRow(title: "Car", value: displayValue(summary.car))
            metaRow(title: "Driver", value: displayValue(summary.driver))
            metaRow(title: "Tyre", value: displayValue(summary.tyre))
            metaRow(title: "Lap", value: displayValue(summary.lap))
            metaRow(title: "Date", value: displayValue(summary.date))
            if let began = summary.sessionBeganAt {
                metaRow(
                    title: "Session start",
                    value: DateFormatter.localizedString(from: began, dateStyle: .medium, timeStyle: .short)
                )
            }
            metaRow(
                title: "Archived",
                value: DateFormatter.localizedString(from: summary.createdAt, dateStyle: .medium, timeStyle: .short)
            )
            metaRow(
                title: "Session ID",
                value: summary.sessionID.uuidString
            )
            metaRow(
                title: "Device",
                value: summary.originDeviceDisplayName.ifEmpty("Unknown device")
            )
            if !summary.originDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metaRow(
                    title: "Device ID",
                    value: summary.originDeviceID
                )
            }
            metaRow(
                title: "Origin",
                value: summary.isFromCurrentDevice ? "This device" : "Imported / External"
            )
            metaRow(title: "Results", value: "\(snapshot.results.count)")
        }
    }

    private var temperatureSection: some View {
        Section("Temperatures / 温度") {
            HistorySummaryRow(summary: summary)
                .padding(.vertical, 4)
        }
    }

    private func measurementSection(results: [MeasureResult]) -> some View {
        Section("Measurement log / 計測ログ") {
            let sorted = results.sorted { $0.endedAt > $1.endedAt }
            ForEach(sorted) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(result.wheel.rawValue) · \(result.zone.rawValue)")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        Text(String(format: "%.1f℃", result.peakC))
                            .font(.caption.monospacedDigit())
                        Text(Self.timelineDateFormatter.string(from: result.endedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(result.via)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func memoSection(memos: [WheelPos: String]) -> some View {
        Section("Memos / メモ") {
            ForEach(WheelPos.allCases) { wheel in
                if let memo = memos[wheel], !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wheel.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(memo)
                            .font(.body)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func pressureSection(snapshot: SessionSnapshot) -> some View {
        Section("Pressures / 空気圧") {
            Grid(horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("")
                    ForEach(WheelPos.allCases) { wheel in
                        Text(wheel.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GridRow {
                    Text("kPa")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(WheelPos.allCases) { wheel in
                        Text(summary.formattedPressure(for: wheel))
                            .font(.caption2.monospacedDigit())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func metaRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Self.metaLabelWidth, alignment: .leading)
            Text(value)
                .font(.body)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 2)
    }

    private func displayValue(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }
}
