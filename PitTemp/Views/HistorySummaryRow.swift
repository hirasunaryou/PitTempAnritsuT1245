import SwiftUI

struct HistorySummaryRow: View {
    let summary: SessionHistorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.displayTitle)
                    .font(.headline)
                Spacer()
                Text(summary.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(summary.displayDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label {
                    Text(summary.originDeviceDisplayName.ifEmpty("Unknown device"))
                } icon: {
                    Image(systemName: summary.isFromCurrentDevice ? "iphone" : "arrow.down.circle")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if !summary.originDeviceShortID.isEmpty {
                    Text("ID: \(summary.originDeviceShortID)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(String(summary.sessionID.uuidString.prefix(8)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if !summary.date.isEmpty {
                Text("記録日: \(summary.date)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if summary.hasTemperatures {
                temperatureGrid
                    .padding(.top, 4)
            }

            if summary.hasPressures {
                pressureGrid
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
    }

    private var temperatureGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(Zone.allCases) { zone in
                    Text(zone.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ForEach(WheelPos.allCases) { wheel in
                GridRow {
                    Text(wheel.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)

                    ForEach(Zone.allCases) { zone in
                        Text(summary.formattedTemperature(for: wheel, zone: zone))
                            .font(.caption2.monospacedDigit())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var pressureGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                Text("IP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(WheelPos.allCases) { wheel in
                    Text(wheel.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GridRow {
                Text("")
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

struct HistorySummaryRow_Previews: PreviewProvider {
    static var previews: some View {
        let snapshot = SessionSnapshot(
            meta: MeasureMeta(track: "Fuji", date: "2024/05/20", car: "GT3", driver: "A. Driver", tyre: "Soft", time: "", lap: "5", checker: ""),
            results: [
                MeasureResult(wheel: .FL, zone: .OUT, peakC: 85.4, startedAt: .now, endedAt: .now, via: "manual"),
                MeasureResult(wheel: .FL, zone: .CL, peakC: 86.4, startedAt: .now, endedAt: .now, via: "manual"),
                MeasureResult(wheel: .FL, zone: .IN, peakC: 87.4, startedAt: .now, endedAt: .now, via: "manual"),
            ],
            wheelMemos: [:],
            wheelPressures: [.FL: 195.0],
            sessionBeganAt: Date().addingTimeInterval(-600),
            sessionID: UUID(),
            originDeviceID: "SAMPLE-DEVICE-ID",
            originDeviceName: "PitTemp iPhone",
            createdAt: Date()
        )

        let zonePeaks: [WheelPos: [Zone: Double]] = [
            .FL: [.OUT: 85.4, .CL: 86.4, .IN: 87.4],
            .FR: [.OUT: 84.2, .CL: 85.5, .IN: 86.1]
        ]

        let summary = SessionHistorySummary(
            fileURL: URL(fileURLWithPath: "/tmp/sample.json"),
            createdAt: snapshot.createdAt,
            sessionBeganAt: snapshot.sessionBeganAt,
            sessionID: snapshot.sessionID,
            track: snapshot.meta.track,
            date: snapshot.meta.date,
            car: snapshot.meta.car,
            driver: snapshot.meta.driver,
            tyre: snapshot.meta.tyre,
            lap: snapshot.meta.lap,
            resultCount: snapshot.results.count,
            zonePeaks: zonePeaks,
            wheelPressures: snapshot.wheelPressures,
            originDeviceID: snapshot.originDeviceID,
            originDeviceName: snapshot.originDeviceName,
            isFromCurrentDevice: true
        )

        HistorySummaryRow(summary: summary)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
