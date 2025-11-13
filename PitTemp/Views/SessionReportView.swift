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

    private var memoAvailable: Bool {
        snapshot.wheelMemos.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.16), Color(red: 0.05, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    tyreGrid
                    if summary.hasPressures {
                        pressureSection
                    }
                    if memoAvailable {
                        memoSection
                    }
                    footer
                }
                .padding(24)
            }
        }
        .navigationTitle("Session report / セッションレポート")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.displayTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("Session ID / セッション ID: \(snapshot.sessionID.uuidString)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(headlineDate)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Time / 時刻: \(recordedAtDescription)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }

            infoTagGrid
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var infoTagGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                infoTag(icon: "flag.checkered", title: "Track / サーキット", value: summary.track.ifEmpty("-"))
                infoTag(icon: "car.fill", title: "Car / 車両", value: summary.car.ifEmpty("-"))
            }
            HStack(spacing: 12) {
                infoTag(icon: "person.fill", title: "Driver / ドライバー", value: summary.driver.ifEmpty("-"))
                infoTag(icon: "timer", title: "Lap / ラップ", value: summary.lap.ifEmpty("-"))
            }
            infoTag(icon: "speedometer", title: "Tyre / タイヤ", value: summary.tyre.ifEmpty("-"))
        }
    }

    private func infoTag(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.white.opacity(0.7))
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var tyreGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tyre snapshot / タイヤ状況")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    wheelCard(for: .FL)
                    axleIndicator(title: "Front", subtitle: "フロント", systemImage: "car.fill")
                    wheelCard(for: .FR)
                }
                HStack(alignment: .top, spacing: 20) {
                    wheelCard(for: .RL)
                    axleIndicator(title: "Rear", subtitle: "リア", systemImage: "car.2.fill")
                    wheelCard(for: .RR)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func wheelCard(for wheel: WheelPos) -> some View {
        SessionReportWheelCard(
            wheel: wheel,
            summary: summary,
            snapshot: snapshot
        )
    }

    private func axleIndicator(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(Color.white.opacity(0.4))
            VStack(spacing: 2) {
                Text(title)
                Text(subtitle)
            }
            .font(.caption2)
            .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(width: 78)
    }

    private var pressureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tyre pressures / タイヤ内圧")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    Text("Front left\nフロント左")
                    Text("Front right\nフロント右")
                    Text("Rear left\nリア左")
                    Text("Rear right\nリア右")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))

                GridRow {
                    Text("kPa")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    ForEach(WheelPos.allCases) { wheel in
                        Text(summary.formattedPressure(for: wheel))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes / メモ")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            ForEach(WheelPos.allCases) { wheel in
                if let memo = snapshot.wheelMemos[wheel]?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedWheelTitle(for: wheel))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(memo)
                            .font(.body)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recorded by / 計測デバイス")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 12) {
                infoTag(icon: "iphone.homebutton", title: "Device / デバイス", value: snapshot.originDeviceName.ifEmpty(summary.originDeviceDisplayName.ifEmpty("Unknown")))
                infoTag(icon: "number", title: "Device ID / デバイスID", value: snapshot.originDeviceID.ifEmpty(summary.originDeviceShortID.ifEmpty("-")))
            }
            Text("Measurements / 計測数: \(summary.resultCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func localizedWheelTitle(for wheel: WheelPos) -> String {
        switch wheel {
        case .FL: return "Front left / フロント左"
        case .FR: return "Front right / フロント右"
        case .RL: return "Rear left / リア左"
        case .RR: return "Rear right / リア右"
        }
    }

    private struct SessionReportWheelCard: View {
        let wheel: WheelPos
        let summary: SessionHistorySummary
        let snapshot: SessionSnapshot

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let pressureText {
                        Text("Pressure / 内圧: \(pressureText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                VStack(spacing: 8) {
                    ForEach(Zone.allCases) { zone in
                        HStack {
                            Text(localizedZoneTitle(for: zone))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                            Spacer(minLength: 12)
                            Text(summary.formattedTemperature(for: wheel, zone: zone))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }

                if let memo {
                    Divider().background(Color.white.opacity(0.2))
                    Text(memo)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: 220)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
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

        private var title: String {
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
