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
                    .padding(isWide ? 28 : 18)
            }
        }
        .navigationTitle("Session report / セッションレポート")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(isWide: Bool) -> some View {
        if isWide {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 16) {
                        headerCard
                        tyreMatrix
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    metricsStack
                        .frame(maxWidth: 320, alignment: .top)
                }

                if memoAvailable {
                    memoStrip
                }
            }
        } else {
            VStack(spacing: 16) {
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
        ViewThatFits {
            HStack(alignment: .top, spacing: 14) {
                if summary.hasPressures {
                    pressureCard
                }
                sessionInfoCard
            }
            .frame(maxWidth: .infinity, alignment: .top)

            VStack(spacing: 14) {
                if summary.hasPressures {
                    pressureCard
                }
                sessionInfoCard
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("Session ID / セッションID")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(snapshot.sessionID.uuidString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(headlineDate)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Time / 時刻")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(recordedAtDescription)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.trailing)
                }
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 8) {
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
        .padding(16)
        .background(cardBackground(cornerRadius: 22))
    }

    private func infoChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value.ifEmpty("-"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var tyreMatrix: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tyre focus / タイヤフォーカス")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            Grid(alignment: .center, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    wheelCard(for: .FL)
                    wheelCard(for: .FR)
                }
                GridRow {
                    wheelCard(for: .RL)
                    wheelCard(for: .RR)
                }
            }
        }
        .padding(18)
        .background(cardBackground(cornerRadius: 26))
    }

    private func wheelCard(for wheel: WheelPos) -> some View {
        SessionReportWheelCard(
            wheel: wheel,
            summary: summary,
            snapshot: snapshot
        )
    }

    private var pressureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tyre pressures / タイヤ内圧")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            Grid(horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow {
                    ForEach(WheelPos.allCases) { wheel in
                        VStack(spacing: 4) {
                            Text(localizedWheelShort(for: wheel))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                            Text(summary.formattedPressure(for: wheel))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground(cornerRadius: 22))
    }

    private var sessionInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timing & device / 計測タイミングと端末")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

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
        .padding(16)
        .background(cardBackground(cornerRadius: 22))
    }

    private func infoLine(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var memoStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes / メモ")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(memoItems, id: \.0) { wheel, memo in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedWheelTitle(for: wheel))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(memo)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(3)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                }
            }
        }
        .padding(16)
        .background(cardBackground(cornerRadius: 22))
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
            VStack(alignment: .leading, spacing: 8) {
                Text(localizedWheelTitle(for: wheel))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Zone.allCases) { zone in
                        VStack(spacing: 4) {
                            Text(localizedZoneTitle(for: zone))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                            Text(summary.formattedTemperature(for: wheel, zone: zone))
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                }

                if let pressureText {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.65))
                        Text(pressureText)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }

                if let memo {
                    Text(memo)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
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
