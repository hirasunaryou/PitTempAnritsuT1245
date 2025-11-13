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
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let rangeFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let orientation: ReportOrientation = proxy.size.width >= proxy.size.height ? .landscape : .portrait
                let metrics = layoutMetrics(for: orientation)
                let scale = min(proxy.size.width / metrics.canvasSize.width,
                                proxy.size.height / metrics.canvasSize.height)

                ZStack {
                    reportBackground

                    reportPage(for: orientation, metrics: metrics)
                        .frame(width: metrics.canvasSize.width, height: metrics.canvasSize.height)
                        .scaleEffect(scale, anchor: .center)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
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

    private func reportPage(for orientation: ReportOrientation, metrics: ReportLayoutMetrics) -> some View {
        VStack(spacing: metrics.sectionSpacing) {
            topRow(isLandscape: orientation.isLandscape)
            middleRow(isLandscape: orientation.isLandscape)
            identityStrip(isLandscape: orientation.isLandscape)

            if !condensedMemos.isEmpty {
                memoStrip
            }

            footerStamp
        }
        .padding(metrics.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func topRow(isLandscape: Bool) -> some View {
        if isLandscape {
            HStack(alignment: .top, spacing: 24) {
                timeBanner
                keyMetricStack
                    .frame(maxWidth: 320)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                timeBanner
                keyMetricStack
            }
        }
    }

    private var timeBanner: some View {
        let meta = vm.meta
        let track = meta.track.ifEmpty("Track unknown / サーキット未設定")
        let capture = captureRange
        let captureDate = capture?.start ?? Date()
        let dayText = Self.headerDateFormatter.string(from: captureDate)
        let windowText = capture.map { Self.rangeFormatter.string(from: $0.start, to: $0.end) }
            ?? Self.headerTimeFormatter.string(from: captureDate)
        let durationText = capture.flatMap { range -> String? in
            let seconds = max(0, range.end.timeIntervalSince(range.start))
            guard let formatted = Self.durationFormatter.string(from: seconds), !formatted.isEmpty else { return nil }
            return "Duration / 所要: \(formatted)"
        }

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(track)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(dayText)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Time window / 計測時間帯")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                Text(windowText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let durationText {
                    Text(durationText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.07, green: 0.18, blue: 0.36),
                                    Color(red: 0.18, green: 0.39, blue: 0.72)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 12)
    }

    private var keyMetricStack: some View {
        VStack(spacing: 16) {
            temperatureSummaryCard
            pressureSummaryCard
        }
        .frame(maxWidth: .infinity)
    }

    private var temperatureSummaryCard: some View {
        let hottest = hottestReading

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Temperature / 温度", systemImage: "flame.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.52, blue: 0.17))
                Spacer()
            }

            Text(formattedTemperature(maxTemperature))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 12) {
                StatCaption(title: "Average / 平均", value: formattedTemperature(averageTemperature))
                if let hottest {
                    StatCaption(title: "Peak zone / 最高ゾーン", value: "\(wheelName(for: hottest.wheel).code) · \(zoneLabel(hottest.zone))")
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var pressureSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Inner pressure / 内圧", systemImage: "gauge")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.24, green: 0.49, blue: 0.92))
                Spacer()
            }

            Text(formattedPressure(pressureAverage))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 12) {
                if let range = pressureRange {
                    StatCaption(title: "Range / 幅", value: "\(formattedPressure(range.min)) – \(formattedPressure(range.max))")
                }
                if let leader = highestPressureWheel {
                    StatCaption(title: "Highest wheel / 最高ホイール", value: wheelName(for: leader.wheel).code)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func middleRow(isLandscape: Bool) -> some View {
        if isLandscape {
            HStack(alignment: .top, spacing: 24) {
                wheelQuadrantMap
                    .frame(maxWidth: 360)
                temperatureDetailPanel
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                wheelQuadrantMap
                temperatureDetailPanel
            }
        }
    }

    private var wheelQuadrantMap: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let itemSize = side / 2 - 10

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.95))
                    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        quadrantTile(for: .FL)
                            .frame(width: itemSize, height: itemSize)
                        quadrantTile(for: .FR)
                            .frame(width: itemSize, height: itemSize)
                    }
                    HStack(spacing: 10) {
                        quadrantTile(for: .RL)
                            .frame(width: itemSize, height: itemSize)
                        quadrantTile(for: .RR)
                            .frame(width: itemSize, height: itemSize)
                    }
                }
                .padding(20)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func quadrantTile(for wheel: WheelPos) -> some View {
        let temperature = wheelTemperatureSummary[wheel]
        let pressure = vm.wheelPressures[wheel]
        let isActive = wheel == featuredWheel

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(wheelName(for: wheel).code)
                    .font(.headline.weight(.bold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(formattedTemperature(temperature ?? .nan))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.primary)
                Text("Pressure \(formattedPressure(pressure))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isActive ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isActive ? 2 : 1)
        )
    }

    private var temperatureDetailPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zone temperatures / ゾーン温度")
                .font(.headline)
            Text("Latest per tyre / 最新値一覧")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(WheelPos.allCases.enumerated()), id: \.element) { index, wheel in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wheelName(for: wheel).title)
                            .font(.subheadline.weight(.semibold))
                        Text(wheelName(for: wheel).code)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ForEach(zoneDisplayOrder, id: \.self) { zone in
                        zoneChip(for: wheel, zone: zone)
                    }
                }
                .padding(.vertical, 6)
                if index < WheelPos.allCases.count - 1 {
                    Divider()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func zoneChip(for wheel: WheelPos, zone: Zone) -> some View {
        let reading = latestTemperatures[wheel]?[zone]
        let value = formattedTemperature(reading ?? .nan)

        return VStack(spacing: 4) {
            Text(zoneLabel(zone))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(zoneBackground(for: reading))
                )
        }
    }

    private func identityStrip(isLandscape: Bool) -> some View {
        let meta = vm.meta
        let infoItems: [(title: String, value: String)] = [
            ("Driver / ドライバー", meta.driver.ifEmpty("--")),
            ("Car / 車両", meta.car.ifEmpty("--")),
            ("Tyre / タイヤ", meta.tyre.ifEmpty("--")),
            ("Lap / ラップ", meta.lap.ifEmpty("--")),
        ]

        let content = Group {
            ForEach(infoItems.indices, id: \.self) { idx in
                VStack(alignment: .leading, spacing: 4) {
                    Text(infoItems[idx].title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(infoItems[idx].value)
                        .font(.callout)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        return Group {
            if isLandscape {
                HStack(alignment: .top, spacing: 16) { content }
            } else {
                VStack(alignment: .leading, spacing: 8) { content }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.tertiarySystemBackground).opacity(0.9))
        )
    }

    private var memoStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes / 備考")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(condensedMemos, id: \.wheel) { memo in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(wheelName(for: memo.wheel).title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(memo.text)
                            .font(.footnote)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct StatCaption: View {
        let title: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var captureRange: (start: Date, end: Date)? {
        guard let start = vm.results.map({ $0.startedAt }).min(),
              let end = vm.results.map({ $0.endedAt }).max() else {
            return nil
        }
        return (start, end)
    }

    private var hottestReading: (wheel: WheelPos, zone: Zone, value: Double)? {
        var candidate: (WheelPos, Zone, Double, Date)? = nil
        for result in vm.results {
            guard result.peakC.isFinite else { continue }
            let record = (result.wheel, result.zone, result.peakC, result.endedAt)
            if let current = candidate {
                if record.2 > current.2 || (record.2 == current.2 && record.3 > current.3) {
                    candidate = record
                }
            } else {
                candidate = record
            }
        }
        guard let candidate else { return nil }
        return (candidate.0, candidate.1, candidate.2)
    }

    private var featuredWheel: WheelPos? {
        if let current = vm.currentWheel { return current }
        if let hottest = hottestReading { return hottest.wheel }
        if let latestResult = vm.results.sorted(by: { $0.endedAt < $1.endedAt }).last {
            return latestResult.wheel
        }
        if let firstPressure = vm.wheelPressures.keys.sorted(by: { $0.rawValue < $1.rawValue }).first {
            return firstPressure
        }
        return nil
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

    private var wheelTemperatureSummary: [WheelPos: Double] {
        var summary: [WheelPos: Double] = [:]
        for (wheel, map) in latestTemperatures {
            summary[wheel] = map.values.max()
        }
        return summary
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

    private var pressureValues: [Double] {
        vm.wheelPressures.values.filter { $0.isFinite }
    }

    private var pressureAverage: Double? {
        guard !pressureValues.isEmpty else { return nil }
        let sum = pressureValues.reduce(0, +)
        return sum / Double(pressureValues.count)
    }

    private var pressureRange: (min: Double, max: Double)? {
        guard let min = pressureValues.min(), let max = pressureValues.max() else { return nil }
        return (min, max)
    }

    private var highestPressureWheel: (wheel: WheelPos, value: Double)? {
        vm.wheelPressures.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    private func formattedTemperature(_ value: Double) -> String {
        guard value.isFinite else { return "--" }
        return String(format: "%.1f℃", value)
    }

    private func formattedPressure(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(format: "%.0f kPa", value)
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

    private let zoneDisplayOrder: [Zone] = [.OUT, .CL, .IN]

    private func zoneBackground(for reading: Double?) -> Color {
        guard let reading else { return Color(.tertiarySystemFill).opacity(0.35) }
        switch reading {
        case ..<60:
            return Color.blue.opacity(0.18)
        case 60..<80:
            return Color.mint.opacity(0.2)
        case 80..<110:
            return Color.orange.opacity(0.24)
        default:
            return Color.red.opacity(0.26)
        }
    }

    private var condensedMemos: [(wheel: WheelPos, text: String)] {
        WheelPos.allCases.compactMap { wheel in
            guard let memo = vm.wheelMemos[wheel]?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty else {
                return nil
            }
            return (wheel, memo)
        }
    }

    private var reportBackground: some View {
        LinearGradient(
            colors: [Color(.systemGroupedBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var footerStamp: some View {
        VStack(spacing: 4) {
            Text("Generated \(DateFormatter.localizedString(from: generatedAt, dateStyle: .medium, timeStyle: .short))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Present this screen for capture / この画面を提示して記録できます")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private enum ReportOrientation {
        case landscape
        case portrait

        var isLandscape: Bool { self == .landscape }
    }

    private struct ReportLayoutMetrics {
        let canvasSize: CGSize
        let sectionSpacing: CGFloat
        let pagePadding: EdgeInsets
    }

    private func layoutMetrics(for orientation: ReportOrientation) -> ReportLayoutMetrics {
        switch orientation {
        case .landscape:
            return ReportLayoutMetrics(
                canvasSize: CGSize(width: 1060, height: 640),
                sectionSpacing: 26,
                pagePadding: EdgeInsets(top: 38, leading: 44, bottom: 34, trailing: 44)
            )
        case .portrait:
            return ReportLayoutMetrics(
                canvasSize: CGSize(width: 820, height: 1180),
                sectionSpacing: 22,
                pagePadding: EdgeInsets(top: 32, leading: 28, bottom: 32, trailing: 28)
            )
        }
    }
}

#Preview {
    SessionReportView()
        .environmentObject(SessionViewModel())
}
