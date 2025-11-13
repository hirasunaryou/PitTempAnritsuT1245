import SwiftUI

struct SessionReportView: View {
    let summary: SessionHistorySummary
    let snapshot: SessionSnapshot

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var headlineDate: String {
        if let began = snapshot.sessionBeganAt {
            return Self.dateFormatter.string(from: began)
        }
        return Self.dateFormatter.string(from: summary.createdAt)
    }

    private var recordedAtDescription: String {
        if let began = snapshot.sessionBeganAt {
            let end = Self.timeFormatter.string(from: summary.createdAt)
            return "\(Self.timeFormatter.string(from: began)) → \(end)"
        }
        return Self.timeFormatter.string(from: summary.createdAt)
    }

    private var memoItems: [(WheelPos, String)] {
        WheelPos.allCases.compactMap { wheel in
            guard let memo = snapshot.wheelMemos[wheel]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !memo.isEmpty else { return nil }
            return (wheel, memo)
        }
    }

    private var memoAvailable: Bool { !memoItems.isEmpty }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.03, green: 0.03, blue: 0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                content(isWide: isWide)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(isWide ? 32 : 20)
            }
        }
        .navigationTitle("Session report / セッションレポート")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(isWide: Bool) -> some View {
        if isWide {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 20) {
                        headerCard
                        tyreMatrix
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 20) {
                        metricsStack
                    }
                    .frame(maxWidth: 320, alignment: .top)
                }

                if memoAvailable {
                    memoStrip
                }
            }
        } else {
            VStack(spacing: 18) {
                headerCard
                tyreMatrix
                    .layoutPriority(1)
                metricsStack
                if memoAvailable {
                    memoStrip
                }
            }
        }
    }

    private var metricsStack: some View {
        VStack(spacing: 18) {
            if summary.hasPressures {
                pressureCard
            }
            sessionInfoCard
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.displayTitle)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text("Session ID / セッションID: \(snapshot.sessionID.uuidString)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(headlineDate)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Time / 時刻: \(recordedAtDescription)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.trailing)
                }
            }

            Divider()
                .background(Color.white.opacity(0.2))

            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    infoChip(title: "Track / サーキット", value: summary.track)
                    infoChip(title: "Car / 車両", value: summary.car)
                }
                GridRow {
                    infoChip(title: "Driver / ドライバー", value: summary.driver)
                    infoChip(title: "Tyre / タイヤ", value: summary.tyre)
                }
                GridRow {
                    infoChip(title: "Lap / ラップ", value: summary.lap.ifEmpty("-"))
                    infoChip(title: "Date meta / 計測日メモ", value: summary.date.ifEmpty("-"))
                }
            }
        }
        .padding(20)
        .background(cardBackground(cornerRadius: 26))
    }

    private func infoChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(value.ifEmpty("-"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var tyreMatrix: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tyre metrics / タイヤ主要値")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))

            Grid(alignment: .top, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    wheelCard(for: .FL)
                    axleIndicator(title: "Front", subtitle: "フロント", systemImage: "car.front.waves.up.fill")
                    wheelCard(for: .FR)
                }
                GridRow {
                    wheelCard(for: .RL)
                    axleIndicator(title: "Rear", subtitle: "リア", systemImage: "car.rear.waves.up.fill")
                    wheelCard(for: .RR)
                }
            }
        }
        .padding(22)
        .background(cardBackground(cornerRadius: 30))
    }

    private func wheelCard(for wheel: WheelPos) -> some View {
        SessionReportWheelCard(
            wheel: wheel,
            summary: summary,
            snapshot: snapshot
        )
    }

    private func axleIndicator(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(Color.white.opacity(0.45))
            VStack(spacing: 2) {
                Text(title)
                Text(subtitle)
            }
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(width: 82)
    }

    private var pressureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tyre pressures / タイヤ内圧")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))

            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("")
                    ForEach(WheelPos.allCases) { wheel in
                        Text(localizedWheelShort(for: wheel))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                GridRow {
                    Text("kPa")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    ForEach(WheelPos.allCases) { wheel in
                        Text(summary.formattedPressure(for: wheel))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground(cornerRadius: 24))
    }

    private var sessionInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Timing & device / 計測タイミングと端末")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))

            infoLine(icon: "calendar", title: "Captured / 記録", detail: "\(headlineDate) · \(recordedAtDescription)")

            if let began = snapshot.sessionBeganAt {
                let beginText = Self.timeFormatter.string(from: began)
                infoLine(icon: "timer", title: "Session start / 計測開始", detail: beginText)
            }

            infoLine(icon: "square.grid.3x3.fill", title: "Measurements / 計測数", detail: "\(summary.resultCount)")

            infoLine(
                icon: "iphone.gen3",
                title: "Device / デバイス",
                detail: snapshot.originDeviceName.ifEmpty(summary.originDeviceDisplayName.ifEmpty("-"))
            )

            let deviceID = snapshot.originDeviceID.ifEmpty(summary.originDeviceID)
            if !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                infoLine(icon: "barcode", title: "Device ID / デバイスID", detail: deviceID)
            }
        }
        .padding(20)
        .background(cardBackground(cornerRadius: 24))
    }

    private func infoLine(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var memoStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes / メモ")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))

            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(memoItems, id: \.0) { wheel, memo in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizedWheelTitle(for: wheel))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.65))
                        Text(memo)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .lineLimit(4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
            }
        }
        .padding(20)
        .background(cardBackground(cornerRadius: 26))
    }

    private func localizedWheelTitle(for wheel: WheelPos) -> String {
        switch wheel {
        case .FL: return "Front left / フロント左"
        case .FR: return "Front right / フロント右"
        case .RL: return "Rear left / リア左"
        case .RR: return "Rear right / リア右"
        }
    }

    private func localizedWheelShort(for wheel: WheelPos) -> String {
        switch wheel {
        case .FL: return "Front L\nフロント左"
        case .FR: return "Front R\nフロント右"
        case .RL: return "Rear L\nリア左"
        case .RR: return "Rear R\nリア右"
        }
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }

    private struct SessionReportWheelCard: View {
        let wheel: WheelPos
        let summary: SessionHistorySummary
        let snapshot: SessionSnapshot

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(localizedWheelTitle(for: wheel))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    if let pressureText {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Pressure / 内圧")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(pressureText)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    ForEach(Zone.allCases) { zone in
                        VStack(spacing: 4) {
                            Text(localizedZoneTitle(for: zone))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(summary.formattedTemperature(for: wheel, zone: zone))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                }

                if let memo {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: 220)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
        }

        private var pressureText: String? {
            let text = summary.formattedPressure(for: wheel)
            return text == "-" ? nil : text
        }

        private var memo: String? {
            guard let raw = snapshot.wheelMemos[wheel]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            return raw
        }

        private func localizedWheelTitle(for wheel: WheelPos) -> String {
            switch wheel {
            case .FL: return "Front left / フロント左"
            case .FR: return "Front right / フロント右"
            case .RL: return "Rear left / リア左"
            case .RR: return "Rear right / リア右"
            }
        }

        private func localizedZoneTitle(for zone: Zone) -> String {
            switch zone {
            case .IN: return "Inner / インナー"
            case .CL: return "Center / センター"
            case .OUT: return "Outer / アウター"
            }
        }
    }
}
