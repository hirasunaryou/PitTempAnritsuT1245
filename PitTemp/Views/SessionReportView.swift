import SwiftUI

struct SessionReportView: View {
    @EnvironmentObject var vm: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    private let generatedAt = Date()

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd (EEE)"
        return formatter
    }()

    private static let headerTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let rangeFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroHeader

                    if !allTemperatures.isEmpty {
                        highlightMetrics
                    }

                    wheelMatrix

                    if !vm.wheelMemos.isEmpty {
                        memoSection
                    }

                    footerStamp
                }
                .padding(24)
            }
            .background(reportBackground)
            .navigationTitle("Session report / セッションレポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close / 閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var heroHeader: some View {
        let meta = vm.meta
        let track = meta.track.ifEmpty("Track unknown / サーキット未設定")
        let car = meta.car.ifEmpty("Car unknown / 車両未設定")
        let driver = meta.driver.ifEmpty("Driver unknown / ドライバー未設定")
        let tyre = meta.tyre.ifEmpty("Tyre unknown / タイヤ未設定")
        let lap = meta.lap.ifEmpty("Lap unknown / ラップ未設定")

        let captureDate = captureRange?.start ?? Date()
        let dayText = Self.headerDateFormatter.string(from: captureDate)
        let timeText = captureRange
            .map { Self.rangeFormatter.string(from: $0.start, to: $0.end) }
            ?? Self.headerTimeFormatter.string(from: captureDate)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(track)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Session overview / セッション概要")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Divider().background(.white.opacity(0.3))

            Grid(horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    heroLabel("Driver / ドライバー")
                    heroValue(driver)
                }
                GridRow {
                    heroLabel("Car / 車両")
                    heroValue(car)
                }
                GridRow {
                    heroLabel("Tyre / タイヤ")
                    heroValue(tyre)
                }
                GridRow {
                    heroLabel("Lap / ラップ")
                    heroValue(lap)
                }
                GridRow {
                    heroLabel("Captured / 計測日時")
                    heroValue("\(dayText) · \(timeText)")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.09, green: 0.16, blue: 0.32), Color(red: 0.16, green: 0.31, blue: 0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 12)
    }

    private func heroLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.65))
    }

    private func heroValue(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlightMetrics: some View {
        HStack(spacing: 16) {
            metricTile(title: "Max temp / 最高温", value: formattedTemperature(maxTemperature))
            metricTile(title: "Average / 平均温", value: formattedTemperature(averageTemperature))
            metricTile(title: "Samples / 計測数", value: "\(vm.results.count)")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
                .foregroundStyle(Color.primary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var wheelMatrix: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tyre matrix / タイヤ配置")
                .font(.headline)
            Text("Latest readings by zone / ゾーン別の最新値")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(WheelPos.allCases) { wheel in
                    wheelCard(for: wheel)
                }
            }
        }
    }

    private func wheelCard(for wheel: WheelPos) -> some View {
        let name = wheelName(for: wheel)
        let pressure = vm.wheelPressures[wheel].map { String(format: "%.1f kPa", $0) } ?? "--"
        let memo = vm.wheelMemos[wheel]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMemo = !(memo ?? "").isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(name.title)
                    .font(.headline)
                Spacer()
                Text(name.code)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.12))
                    )
            }

            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "gauge.medium")
                    .foregroundStyle(.secondary)
                Text("Pressure / 内圧")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(pressure)
                    .font(.body.monospacedDigit())
            }

            VStack(spacing: 6) {
                ForEach(zoneDisplayOrder, id: \.self) { zone in
                    zoneRow(for: wheel, zone: zone)
                }
            }

            if hasMemo, let memo {
                Divider()
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private func zoneRow(for wheel: WheelPos, zone: Zone) -> some View {
        let reading = latestTemperatures[wheel]?[zone]
        let valueText = reading.map { String(format: "%.1f℃", $0) } ?? "--"
        let subtitle = zoneSubtitle(zone)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(zoneLabel(zone))
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(valueText)
                .font(.body.monospacedDigit())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(zoneBackground(for: reading))
        )
    }

    private func zoneBackground(for reading: Double?) -> Color {
        guard let reading else { return Color(.tertiarySystemFill).opacity(0.35) }
        switch reading {
        case ..<60:
            return Color.blue.opacity(0.12)
        case 60..<80:
            return Color.mint.opacity(0.18)
        case 80..<110:
            return Color.orange.opacity(0.2)
        default:
            return Color.red.opacity(0.22)
        }
    }

    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes / 備考")
                .font(.headline)
            ForEach(WheelPos.allCases) { wheel in
                if let memo = vm.wheelMemos[wheel]?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wheelName(for: wheel).title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(memo)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var footerStamp: some View {
        VStack(spacing: 6) {
            Text("Generated \(DateFormatter.localizedString(from: generatedAt, dateStyle: .medium, timeStyle: .short))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Present this screen for capture / この画面を提示して記録できます")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var captureRange: (start: Date, end: Date)? {
        guard let start = vm.results.map({ $0.startedAt }).min(),
              let end = vm.results.map({ $0.endedAt }).max() else {
            return nil
        }
        return (start, end)
    }

    private var latestTemperatures: [WheelPos: [Zone: Double]] {
        var latest: [WheelPos: [Zone: (Date, Double)]] = [:]
        for result in vm.results {
            guard result.peakC.isFinite else { continue }
            var wheelMap = latest[result.wheel, default: [:]]
            if let existing = wheelMap[result.zone], existing.0 >= result.endedAt {
                continue
            }
            wheelMap[result.zone] = (result.endedAt, result.peakC)
            latest[result.wheel] = wheelMap
        }

        var output: [WheelPos: [Zone: Double]] = [:]
        for (wheel, zoneMap) in latest {
            var simplified: [Zone: Double] = [:]
            for (zone, tuple) in zoneMap {
                simplified[zone] = tuple.1
            }
            output[wheel] = simplified
        }
        return output
    }

    private var allTemperatures: [Double] {
        latestTemperatures.values.flatMap { $0.values }
    }

    private var maxTemperature: Double {
        allTemperatures.max() ?? .nan
    }

    private var averageTemperature: Double {
        guard !allTemperatures.isEmpty else { return .nan }
        let sum = allTemperatures.reduce(0, +)
        return sum / Double(allTemperatures.count)
    }

    private func formattedTemperature(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        return String(format: "%.1f℃", value)
    }

    private func wheelName(for wheel: WheelPos) -> (title: String, code: String) {
        switch wheel {
        case .FL: return ("Front Left", "FL")
        case .FR: return ("Front Right", "FR")
        case .RL: return ("Rear Left", "RL")
        case .RR: return ("Rear Right", "RR")
        }
    }

    private func zoneLabel(_ zone: Zone) -> String {
        switch zone {
        case .IN: return "Inside / イン側"
        case .CL: return "Center / 中央"
        case .OUT: return "Outside / アウト側"
        }
    }

    private func zoneSubtitle(_ zone: Zone) -> String {
        switch zone {
        case .IN: return "Inner edge"
        case .CL: return "Centre"
        case .OUT: return "Outer edge"
        }
    }

    private let zoneDisplayOrder: [Zone] = [.OUT, .CL, .IN]

    private var reportBackground: some View {
        LinearGradient(
            colors: [Color(.systemGroupedBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

#Preview {
    SessionReportView()
        .environmentObject(SessionViewModel())
}
