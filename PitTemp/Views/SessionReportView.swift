import SwiftUI

struct SessionReportView: View {
    let summary: SessionHistorySummary
    let snapshot: SessionSnapshot

    @AppStorage("sessionReportLanguage")
    private var languageRaw: String = ReportLanguage.english.rawValue

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

    private var language: ReportLanguage {
        ReportLanguage(rawValue: languageRaw) ?? .english
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height
            let layout = Self.layoutProfile(for: proxy.size)
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.03, green: 0.03, blue: 0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                content(isWide: isWide, layout: layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(isWide ? layout.widePagePadding : layout.pagePadding)
            }
        }
        .navigationTitle(localized("Session report", "セッションレポート"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(isWide: Bool, layout: LayoutProfile) -> some View {
        let headerStack = VStack(spacing: layout.headerSpacing) {
            languagePicker(layout: layout)
            headerCard(layout: layout)
        }

        if isWide {
            VStack(spacing: layout.sectionSpacing) {
                HStack(alignment: .top, spacing: layout.sectionSpacing) {
                    VStack(spacing: layout.sectionSpacing) {
                        headerStack
                            .frame(maxWidth: .infinity, alignment: .leading)
                        tyreMatrix(layout: layout)
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    metricsStack(layout: layout)
                        .frame(maxWidth: layout.metricsColumnMaxWidth, alignment: .top)
                }

                if layout.showMemo, memoAvailable {
                    memoStrip(layout: layout)
                }
            }
        } else {
            VStack(spacing: layout.sectionSpacing) {
                headerStack
                    .frame(maxWidth: .infinity, alignment: .leading)
                tyreMatrix(layout: layout)
                    .layoutPriority(1)
                metricsStack(layout: layout)
                if layout.showMemo, memoAvailable {
                    memoStrip(layout: layout)
                }
            }
        }
    }

    private func metricsStack(layout: LayoutProfile) -> some View {
        ViewThatFits {
            HStack(alignment: .top, spacing: layout.metricsSpacing) {
                if summary.hasPressures {
                    pressureCard(layout: layout)
                }
                sessionInfoCard(layout: layout)
            }
            .frame(maxWidth: .infinity, alignment: .top)

            VStack(spacing: layout.metricsSpacing) {
                if summary.hasPressures {
                    pressureCard(layout: layout)
                }
                sessionInfoCard(layout: layout)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func headerCard(layout: LayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: layout.headerContentSpacing) {
            HStack(alignment: .top, spacing: layout.headerContentSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.displayTitle)
                        .font(.system(size: layout.headerTitleSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(snapshot.sessionID.uuidString)
                        .font(.system(size: layout.headerIDSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(headlineDate)
                        .font(.system(size: layout.headerDateSize, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(recordedAtDescription)
                        .font(.system(size: layout.headerTimeSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.trailing)
                }
            }

            Grid(horizontalSpacing: layout.metadataGridSpacing, verticalSpacing: layout.metadataGridSpacing) {
                GridRow {
                    infoChip(title: localized("Track", "サーキット"), value: summary.track, layout: layout)
                    infoChip(title: localized("Car", "車両"), value: summary.car, layout: layout)
                }
                GridRow {
                    infoChip(title: localized("Driver", "ドライバー"), value: summary.driver, layout: layout)
                    infoChip(title: localized("Tyre", "タイヤ"), value: summary.tyre, layout: layout)
                }
                GridRow {
                    infoChip(title: localized("Lap", "ラップ"), value: summary.lap.ifEmpty("-"), layout: layout)
                    infoChip(title: localized("Date memo", "計測日メモ"), value: summary.date.ifEmpty("-"), layout: layout)
                }
            }

            if !layout.showMemo, memoAvailable {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.top, 6)

                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: layout.infoIconSize, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text(localized("Notes saved", "メモ登録あり"))
                        .font(.system(size: layout.infoDetailSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .padding(layout.headerCardPadding)
        .background(cardBackground(cornerRadius: layout.headerCardCornerRadius))
    }

    private func infoChip(title: String, value: String, layout: LayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: layout.metadataTitleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(value.ifEmpty("-"))
                .font(.system(size: layout.metadataValueSize, weight: .medium, design: .default))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, layout.metadataChipVerticalPadding)
        .padding(.horizontal, layout.metadataChipHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func tyreMatrix(layout: LayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: layout.tyreMatrixHeaderSpacing) {
            Text(localized("Tyre focus", "タイヤフォーカス"))
                .font(.system(size: layout.tyreMatrixTitleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))

            Grid(alignment: .center, horizontalSpacing: layout.tyreMatrixSpacing, verticalSpacing: layout.tyreMatrixSpacing) {
                GridRow {
                    wheelCard(for: .FL, layout: layout)
                    wheelCard(for: .FR, layout: layout)
                }
                GridRow {
                    wheelCard(for: .RL, layout: layout)
                    wheelCard(for: .RR, layout: layout)
                }
            }
        }
        .padding(layout.tyreMatrixPadding)
        .background(cardBackground(cornerRadius: layout.tyreMatrixCornerRadius))
    }

    private func wheelCard(for wheel: WheelPos, layout: LayoutProfile) -> some View {
        SessionReportWheelCard(
            wheel: wheel,
            summary: summary,
            snapshot: snapshot,
            language: language,
            layout: layout
        )
    }

    private func pressureCard(layout: LayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: layout.infoCardHeaderSpacing) {
            Text(localized("Tyre pressures", "タイヤ内圧"))
                .font(.system(size: layout.infoHeaderSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Grid(horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow {
                    ForEach(WheelPos.allCases) { wheel in
                        VStack(spacing: 4) {
                            Text(localizedWheelShort(for: wheel))
                                .font(.system(size: layout.infoLabelSize, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                            Text(summary.formattedPressure(for: wheel))
                                .font(.system(size: layout.pressureFontSize, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(layout.infoCardPadding)
        .background(cardBackground(cornerRadius: layout.infoCardCornerRadius))
    }

    private func sessionInfoCard(layout: LayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: layout.infoCardHeaderSpacing) {
            Text(localized("Timing & device", "計測タイミングと端末"))
                .font(.system(size: layout.infoHeaderSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            infoLine(icon: "calendar", title: localized("Captured", "記録"), detail: "\(headlineDate) · \(recordedAtDescription)", layout: layout)

            if let began = snapshot.sessionBeganAt {
                let beginText = Self.timeFormatter.string(from: began)
                infoLine(icon: "timer", title: localized("Session start", "計測開始"), detail: beginText, layout: layout)
            }

            infoLine(icon: "square.grid.3x3.fill", title: localized("Measurements", "計測数"), detail: "\(summary.resultCount)", layout: layout)

            infoLine(
                icon: "iphone.gen3",
                title: localized("Device", "デバイス"),
                detail: snapshot.originDeviceName.ifEmpty(summary.originDeviceDisplayName.ifEmpty("-")),
                layout: layout
            )

            let deviceID = snapshot.originDeviceID.ifEmpty(summary.originDeviceID)
            if !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                infoLine(icon: "barcode", title: localized("Device ID", "デバイスID"), detail: deviceID, layout: layout)
            }
        }
        .padding(layout.infoCardPadding)
        .background(cardBackground(cornerRadius: layout.infoCardCornerRadius))
    }

    private func infoLine(icon: String, title: String, detail: String, layout: LayoutProfile) -> some View {
        HStack(alignment: .top, spacing: layout.infoLineSpacing) {
            Image(systemName: icon)
                .font(.system(size: layout.infoIconSize, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: layout.infoIconSize + 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: layout.infoTitleSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(detail)
                    .font(.system(size: layout.infoDetailSize))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func memoStrip(layout: LayoutProfile) -> some View {
        VStack(alignment: .leading, spacing: layout.memoHeaderSpacing) {
            Text(localized("Notes", "メモ"))
                .font(.system(size: layout.memoTitleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            let columns = [GridItem(.flexible(), spacing: layout.memoGridSpacing), GridItem(.flexible(), spacing: layout.memoGridSpacing)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: layout.memoGridSpacing) {
                ForEach(memoItems, id: \.0) { wheel, memo in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedWheelTitle(for: wheel))
                            .font(.system(size: layout.infoLabelSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(memo)
                            .font(.system(size: layout.memoFontSize))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(layout.memoLineLimit)
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
        .padding(layout.memoCardPadding)
        .background(cardBackground(cornerRadius: layout.memoCardCornerRadius))
    }

    private func localizedWheelTitle(for wheel: WheelPos) -> String {
        switch wheel {
        case .FL: return localized("Front left", "フロント左")
        case .FR: return localized("Front right", "フロント右")
        case .RL: return localized("Rear left", "リア左")
        case .RR: return localized("Rear right", "リア右")
        }
    }

    private func localizedWheelShort(for wheel: WheelPos) -> String {
        switch wheel {
        case .FL: return localized("Front L", "フロント左")
        case .FR: return localized("Front R", "フロント右")
        case .RL: return localized("Rear L", "リア左")
        case .RR: return localized("Rear R", "リア右")
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

    private func localized(_ english: String, _ japanese: String) -> String {
        language == .english ? english : japanese
    }

    private func languagePicker(layout: LayoutProfile) -> some View {
        Picker(localized("Language", "言語"), selection: Binding(get: { languageRaw }, set: { languageRaw = $0 })) {
            Text("EN").tag(ReportLanguage.english.rawValue)
            Text("日本語").tag(ReportLanguage.japanese.rawValue)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: layout.languagePickerWidth)
    }

    private enum ReportLanguage: String, CaseIterable, Identifiable {
        case english
        case japanese

        var id: String { rawValue }
    }

    private struct LayoutProfile {
        let pagePadding: CGFloat
        let widePagePadding: CGFloat
        let sectionSpacing: CGFloat
        let headerSpacing: CGFloat
        let headerContentSpacing: CGFloat
        let headerTitleSize: CGFloat
        let headerIDSize: CGFloat
        let headerDateSize: CGFloat
        let headerTimeSize: CGFloat
        let headerCardPadding: CGFloat
        let headerCardCornerRadius: CGFloat
        let metadataGridSpacing: CGFloat
        let metadataChipVerticalPadding: CGFloat
        let metadataChipHorizontalPadding: CGFloat
        let metadataTitleSize: CGFloat
        let metadataValueSize: CGFloat
        let tyreMatrixHeaderSpacing: CGFloat
        let tyreMatrixTitleSize: CGFloat
        let tyreMatrixSpacing: CGFloat
        let tyreMatrixPadding: CGFloat
        let tyreMatrixCornerRadius: CGFloat
        let wheelCardPadding: CGFloat
        let wheelCardCornerRadius: CGFloat
        let wheelContentSpacing: CGFloat
        let wheelZoneSpacing: CGFloat
        let wheelTitleSize: CGFloat
        let zoneTitleSize: CGFloat
        let temperatureFontSize: CGFloat
        let pressureFontSize: CGFloat
        let wheelMemoFontSize: CGFloat
        let wheelMemoLineLimit: Int
        let wheelBadgeSpacing: CGFloat
        let infoCardHeaderSpacing: CGFloat
        let infoHeaderSize: CGFloat
        let infoLabelSize: CGFloat
        let infoCardPadding: CGFloat
        let infoCardCornerRadius: CGFloat
        let infoLineSpacing: CGFloat
        let infoIconSize: CGFloat
        let infoTitleSize: CGFloat
        let infoDetailSize: CGFloat
        let metricsSpacing: CGFloat
        let metricsColumnMaxWidth: CGFloat
        let languagePickerWidth: CGFloat
        let memoHeaderSpacing: CGFloat
        let memoTitleSize: CGFloat
        let memoFontSize: CGFloat
        let memoLineLimit: Int
        let memoCardPadding: CGFloat
        let memoCardCornerRadius: CGFloat
        let memoGridSpacing: CGFloat
        let showMemo: Bool
    }

    private static func layoutProfile(for size: CGSize) -> LayoutProfile {
        let height = size.height
        if height < 620 {
            return compactLayout
        } else if height < 740 {
            return tightLayout
        } else {
            return regularLayout
        }
    }

    private static let regularLayout = LayoutProfile(
        pagePadding: 20,
        widePagePadding: 30,
        sectionSpacing: 18,
        headerSpacing: 12,
        headerContentSpacing: 8,
        headerTitleSize: 21,
        headerIDSize: 11,
        headerDateSize: 16,
        headerTimeSize: 14,
        headerCardPadding: 16,
        headerCardCornerRadius: 22,
        metadataGridSpacing: 8,
        metadataChipVerticalPadding: 5,
        metadataChipHorizontalPadding: 8,
        metadataTitleSize: 11,
        metadataValueSize: 13,
        tyreMatrixHeaderSpacing: 12,
        tyreMatrixTitleSize: 20,
        tyreMatrixSpacing: 16,
        tyreMatrixPadding: 18,
        tyreMatrixCornerRadius: 26,
        wheelCardPadding: 16,
        wheelCardCornerRadius: 24,
        wheelContentSpacing: 10,
        wheelZoneSpacing: 10,
        wheelTitleSize: 20,
        zoneTitleSize: 12,
        temperatureFontSize: 38,
        pressureFontSize: 24,
        wheelMemoFontSize: 12,
        wheelMemoLineLimit: 2,
        wheelBadgeSpacing: 6,
        infoCardHeaderSpacing: 12,
        infoHeaderSize: 16,
        infoLabelSize: 11,
        infoCardPadding: 14,
        infoCardCornerRadius: 20,
        infoLineSpacing: 8,
        infoIconSize: 13,
        infoTitleSize: 11,
        infoDetailSize: 13,
        metricsSpacing: 14,
        metricsColumnMaxWidth: 300,
        languagePickerWidth: 220,
        memoHeaderSpacing: 10,
        memoTitleSize: 16,
        memoFontSize: 13,
        memoLineLimit: 3,
        memoCardPadding: 16,
        memoCardCornerRadius: 22,
        memoGridSpacing: 10,
        showMemo: true
    )

    private static let tightLayout = LayoutProfile(
        pagePadding: 18,
        widePagePadding: 26,
        sectionSpacing: 16,
        headerSpacing: 10,
        headerContentSpacing: 7,
        headerTitleSize: 20,
        headerIDSize: 10,
        headerDateSize: 15,
        headerTimeSize: 13,
        headerCardPadding: 14,
        headerCardCornerRadius: 20,
        metadataGridSpacing: 7,
        metadataChipVerticalPadding: 4,
        metadataChipHorizontalPadding: 7,
        metadataTitleSize: 10,
        metadataValueSize: 12,
        tyreMatrixHeaderSpacing: 11,
        tyreMatrixTitleSize: 19,
        tyreMatrixSpacing: 14,
        tyreMatrixPadding: 16,
        tyreMatrixCornerRadius: 24,
        wheelCardPadding: 14,
        wheelCardCornerRadius: 22,
        wheelContentSpacing: 9,
        wheelZoneSpacing: 8,
        wheelTitleSize: 18,
        zoneTitleSize: 11,
        temperatureFontSize: 34,
        pressureFontSize: 22,
        wheelMemoFontSize: 11.5,
        wheelMemoLineLimit: 2,
        wheelBadgeSpacing: 6,
        infoCardHeaderSpacing: 11,
        infoHeaderSize: 15,
        infoLabelSize: 10,
        infoCardPadding: 12,
        infoCardCornerRadius: 18,
        infoLineSpacing: 7,
        infoIconSize: 12,
        infoTitleSize: 10,
        infoDetailSize: 12,
        metricsSpacing: 12,
        metricsColumnMaxWidth: 280,
        languagePickerWidth: 200,
        memoHeaderSpacing: 9,
        memoTitleSize: 15,
        memoFontSize: 12,
        memoLineLimit: 2,
        memoCardPadding: 14,
        memoCardCornerRadius: 20,
        memoGridSpacing: 10,
        showMemo: true
    )

    private static let compactLayout = LayoutProfile(
        pagePadding: 16,
        widePagePadding: 22,
        sectionSpacing: 12,
        headerSpacing: 8,
        headerContentSpacing: 6,
        headerTitleSize: 18,
        headerIDSize: 9,
        headerDateSize: 14,
        headerTimeSize: 12,
        headerCardPadding: 12,
        headerCardCornerRadius: 18,
        metadataGridSpacing: 6,
        metadataChipVerticalPadding: 3,
        metadataChipHorizontalPadding: 6,
        metadataTitleSize: 9,
        metadataValueSize: 11,
        tyreMatrixHeaderSpacing: 10,
        tyreMatrixTitleSize: 18,
        tyreMatrixSpacing: 12,
        tyreMatrixPadding: 12,
        tyreMatrixCornerRadius: 20,
        wheelCardPadding: 12,
        wheelCardCornerRadius: 20,
        wheelContentSpacing: 8,
        wheelZoneSpacing: 7,
        wheelTitleSize: 17,
        zoneTitleSize: 10,
        temperatureFontSize: 31,
        pressureFontSize: 19,
        wheelMemoFontSize: 11,
        wheelMemoLineLimit: 1,
        wheelBadgeSpacing: 5,
        infoCardHeaderSpacing: 9,
        infoHeaderSize: 14,
        infoLabelSize: 9,
        infoCardPadding: 10,
        infoCardCornerRadius: 16,
        infoLineSpacing: 6,
        infoIconSize: 11,
        infoTitleSize: 9,
        infoDetailSize: 11,
        metricsSpacing: 10,
        metricsColumnMaxWidth: 250,
        languagePickerWidth: 180,
        memoHeaderSpacing: 8,
        memoTitleSize: 14,
        memoFontSize: 11,
        memoLineLimit: 2,
        memoCardPadding: 12,
        memoCardCornerRadius: 18,
        memoGridSpacing: 8,
        showMemo: false
    )

    private struct SessionReportWheelCard: View {
        let wheel: WheelPos
        let summary: SessionHistorySummary
        let snapshot: SessionSnapshot
        let language: ReportLanguage
        let layout: LayoutProfile

        var body: some View {
            VStack(alignment: .leading, spacing: layout.wheelContentSpacing) {
                Text(localizedWheelTitle(for: wheel))
                    .font(.system(size: layout.wheelTitleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(alignment: .bottom, spacing: layout.wheelZoneSpacing) {
                    ForEach(Zone.allCases) { zone in
                        VStack(spacing: 4) {
                            Text(localizedZoneTitle(for: zone))
                                .font(.system(size: layout.zoneTitleSize, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(summary.formattedTemperature(for: wheel, zone: zone))
                                .font(.system(size: layout.temperatureFontSize, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.75)
                                .lineLimit(1)
                                .fixedSize()
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
                    HStack(spacing: layout.wheelBadgeSpacing) {
                        Image(systemName: "gauge")
                            .font(.system(size: layout.infoLabelSize, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.65))
                        Text(pressureText)
                            .font(.system(size: layout.pressureFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                if let memo {
                    Text(memo)
                        .font(.system(size: layout.wheelMemoFontSize))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(layout.wheelMemoLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(layout.wheelCardPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: layout.wheelCardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.wheelCardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
            )
            .layoutPriority(1)
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
            case .FL: return localized("Front left", "フロント左")
            case .FR: return localized("Front right", "フロント右")
            case .RL: return localized("Rear left", "リア左")
            case .RR: return localized("Rear right", "リア右")
            }
        }

        private func localizedZoneTitle(for zone: Zone) -> String {
            switch zone {
            case .IN: return localized("Inner", "インナー")
            case .CL: return localized("Center", "センター")
            case .OUT: return localized("Outer", "アウター")
            }
        }

        private func localized(_ english: String, _ japanese: String) -> String {
            language == .english ? english : japanese
        }
    }
}
