import SwiftUI

struct SessionReportView: View {
    let summary: SessionHistorySummary
    let snapshot: SessionSnapshot

    @AppStorage("sessionReportLanguage")
    private var languageRaw: String = ReportLanguage.english.rawValue

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "a h:mm"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }()

    private static let manualDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    private static let temperatureFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let pressureFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private var language: ReportLanguage { ReportLanguage(rawValue: languageRaw) ?? .english }

    private var displayedDate: String {
        if let start = measurementStart {
            return Self.dateFormatter.string(from: start)
        }

        if let manual = sanitizedManualDate(from: summary.date) {
            return manual
        }

        return Self.dateFormatter.string(from: summary.createdAt)
    }

    private var displayedTrack: String {
        summary.track.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("-")
    }

    private var displayedCar: String {
        summary.car.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("-")
    }

    private var displayedDriver: String {
        summary.driver.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("-")
    }

    private var displayedTyre: String {
        summary.tyre.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("-")
    }

    private var displayedChecker: String {
        summary.checker.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("-")
    }

    private var measurementStart: Date? {
        if let earliest = snapshot.results.map(\.startedAt).min() {
            return earliest
        }
        if let began = snapshot.sessionBeganAt { return began }
        if let began = summary.sessionBeganAt { return began }
        return nil
    }

    private var displayedTime: String {
        let date = measurementStart ?? summary.createdAt
        let time = Self.timeFormatter.string(from: date)
        let zone = timeZoneAbbreviation(for: date)
        return zone.isEmpty ? time : "\(time) \(zone)"
    }

    private func timeZoneAbbreviation(for date: Date) -> String {
        TimeZone.current.abbreviation(for: date) ?? TimeZone.current.identifier
    }

    private var memoItems: [(WheelPos, String)] {
        WheelPos.allCases.compactMap { wheel in
            guard let memo = snapshot.wheelMemos[wheel]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !memo.isEmpty else { return nil }
            return (wheel, memo)
        }
    }

    private func sanitizedManualDate(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let parsed = Self.manualDateParser.date(from: trimmed) {
            return Self.dateFormatter.string(from: parsed)
        }

        var components = trimmed
        if let range = components.range(of: "T") {
            components = String(components[..<range.lowerBound])
        }
        if let range = components.range(of: " ") {
            components = String(components[..<range.lowerBound])
        }
        if let range = components.range(of: ",") {
            components = String(components[..<range.lowerBound])
        }
        if let range = components.range(of: "\n") {
            components = String(components[..<range.lowerBound])
        }
        if let range = components.range(of: "\r") {
            components = String(components[..<range.lowerBound])
        }

        let sanitized = components.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutMetrics(size: proxy.size)
            ZStack {
                Color(red: 0.92, green: 0.9, blue: 0.86)
                    .ignoresSafeArea()

                VStack(spacing: metrics.canvasSpacing) {
                    languagePicker(metrics: metrics)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    paperSheet(metrics: metrics)
                        .padding(.horizontal, metrics.paperHorizontalPadding)
                        .padding(.bottom, metrics.paperBottomPadding)
                }
                .padding(.top, metrics.paperTopPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(localized("Session report", "セッションレポート"))
    }

    private func paperSheet(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            sheetHeader(metrics: metrics)
            Divider().overlay(Color.black.opacity(0.25))
            formSection(metrics: metrics)
            Divider().overlay(Color.black.opacity(0.2))
            wheelSection(metrics: metrics)
            if !memoItems.isEmpty {
                Divider().overlay(Color.black.opacity(0.2))
                memoSection(metrics: metrics)
            }
        }
        .padding(metrics.sheetPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: metrics.sheetCornerRadius, style: .continuous)
                .fill(Color(red: 0.99, green: 0.98, blue: 0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.sheetCornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }

    private func languagePicker(metrics: LayoutMetrics) -> some View {
        Picker("", selection: $languageRaw) {
            ForEach(ReportLanguage.allCases) { language in
                Text(language.displayName)
                    .tag(language.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .font(.system(size: metrics.languagePickerFont, weight: .medium))
    }

    private func sheetHeader(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.headerSpacing) {
            Text(localized("PIT TEMP SESSION REPORT", "PitTemp 計測レポート"))
                .font(.system(size: metrics.headerTitleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.bottom, 2)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(localized("Track", "サーキット").uppercased())
                    .font(.system(size: metrics.fieldLabelSize, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                Rectangle()
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Color.black.opacity(0.25))
                Text(displayedTrack)
                    .font(.system(size: metrics.fieldValueSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private func formSection(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.formRowSpacing) {
            fieldRow(metrics: metrics, fields: [
                .init(label: localized("Date", "日付"), value: displayedDate),
                .init(label: localized("Time", "時間"), value: displayedTime)
            ])
            fieldRow(metrics: metrics, fields: [
                .init(label: localized("Car", "車両"), value: displayedCar),
                .init(label: localized("Driver", "ドライバー"), value: displayedDriver)
            ])
            fieldRow(metrics: metrics, fields: [
                .init(label: localized("Tyre", "タイヤ"), value: displayedTyre),
                .init(label: localized("Measured by", "計測者"), value: displayedChecker)
            ])
            fieldRow(metrics: metrics, fields: [
                .init(label: localized("Session ID", "セッション ID"),
                      value: snapshot.sessionID.uuidString,
                      style: .monospaced,
                      maxLines: 1,
                      weight: .regular)
            ])
        }
    }

    private func fieldRow(metrics: LayoutMetrics, fields: [Field]) -> some View {
        HStack(spacing: fields.count == 1 ? 0 : metrics.formColumnSpacing) {
            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: metrics.fieldSpacing) {
                    Text(field.label.uppercased())
                        .font(.system(size: metrics.fieldLabelSize, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                    Rectangle()
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color.black.opacity(0.15))
                    Group {
                        if field.style == .monospaced {
                            Text(field.value.ifEmpty("-"))
                                .monospacedDigit()
                        } else {
                            Text(field.value.ifEmpty("-"))
                        }
                    }
                    .font(.system(size: metrics.fieldValueSize, weight: field.weight, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .lineLimit(field.maxLines)
                    .minimumScaleFactor(field.maxLines == 1 ? 0.55 : 0.85)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func wheelSection(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.wheelSectionSpacing) {
            Text(localized("Tyre temps & pressure", "タイヤ温度・内圧"))
                .font(.system(size: metrics.sectionLabelSize, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.65))

            HStack(alignment: .top, spacing: metrics.wheelColumnSpacing) {
                VStack(spacing: metrics.wheelColumnSpacing) {
                    wheelCard(.FL, metrics: metrics)
                    wheelCard(.RL, metrics: metrics)
                }
                VStack(spacing: metrics.wheelColumnSpacing) {
                    wheelCard(.FR, metrics: metrics)
                    wheelCard(.RR, metrics: metrics)
                }
            }
        }
    }

    private func wheelCard(_ wheel: WheelPos, metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.wheelInnerSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: metrics.wheelHeaderSpacing) {
                Text(localizedWheelTitle(for: wheel))
                    .font(.system(size: metrics.wheelLabelSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))

                Spacer(minLength: metrics.wheelHeaderSpacing)

                if let pressure = pressureValue(for: wheel) {
                    pressureDisplay(for: pressure, metrics: metrics)
                }
            }

            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.black.opacity(0.1))

            temperatureGrid(for: wheel, metrics: metrics)

            if let memo = memoText(for: wheel) {
                Text(memo)
                    .font(.system(size: metrics.memoFontSize, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(metrics.wheelPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: metrics.wheelCornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: metrics.wheelCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.9))
                )
        )
    }

    private func memoSection(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.memoSpacing) {
            Text(localized("Notes", "メモ"))
                .font(.system(size: metrics.sectionLabelSize, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.65))
            ForEach(memoItems, id: \.0) { wheel, memo in
                HStack(alignment: .top, spacing: 8) {
                    Text(localizedWheelShort(for: wheel))
                        .font(.system(size: metrics.memoLabelSize, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(width: metrics.memoLabelWidth, alignment: .leading)
                    Text(memo)
                        .font(.system(size: metrics.memoFontSize))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func temperatureText(for wheel: WheelPos, zone: Zone) -> String {
        guard let value = summary.temperature(for: wheel, zone: zone), value.isFinite else { return "-" }
        return Self.temperatureFormatter.string(from: NSNumber(value: value)) ?? "-"
    }

    private func pressureValue(for wheel: WheelPos) -> Double? {
        guard let value = summary.wheelPressures[wheel], value.isFinite else { return nil }
        return value
    }

    private func pressureDisplay(for value: Double, metrics: LayoutMetrics) -> some View {
        // 温度と同じ大きさの数値にそろえ、ラベルとの距離を詰めて「内圧だけ目立つ」印象を防ぐ
        let number = Self.pressureFormatter.string(from: NSNumber(value: value))?.ifEmpty("") ?? ""
        return HStack(alignment: .firstTextBaseline, spacing: metrics.pressureRowSpacing) {
            Text(localized("Pressure", "内圧"))
                .font(.system(size: metrics.pressureLabelSize, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(number.ifEmpty("-"))
                    .font(.system(size: metrics.pressureValueFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.88))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(metrics.pressureValueMinimumScale)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Text("kPa")
                    .font(.system(size: metrics.pressureUnitFontSize, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(metrics.pressureUnitMinimumScale)
            }
        }
    }

    private func temperatureGrid(for wheel: WheelPos, metrics: LayoutMetrics) -> some View {
        HStack(alignment: .top, spacing: metrics.zoneSpacing) {
            // 左右のタイヤで温度表示の向きを変えるため、ホイールごとにゾーンの並び順を決定する
            ForEach(zoneOrder(for: wheel), id: \.self) { zone in
                temperatureTile(for: wheel, zone: zone, metrics: metrics)
            }
        }
    }

    private func temperatureTile(for wheel: WheelPos, zone: Zone, metrics: LayoutMetrics) -> some View {
        VStack(spacing: metrics.zoneInnerSpacing) {
            Text(localizedZoneTitle(for: zone))
                .font(.system(size: metrics.zoneLabelSize, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.52))

            // 数字が潰れて「1」だけ残るような視認性低下を防ぐため、十分な余白と最小縮小率を確保する
            Text(temperatureText(for: wheel, zone: zone))
                .font(.system(size: metrics.temperatureFontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.92))
                .monospacedDigit()
                .minimumScaleFactor(metrics.temperatureMinimumScale)
                .lineLimit(1)
                .allowsTightening(true)
                .layoutPriority(1)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, metrics.temperatureTileVerticalPadding)
        .padding(.horizontal, metrics.temperatureTileHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.temperatureTileMinHeight)
        .background(
            RoundedRectangle(cornerRadius: metrics.temperatureTileCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
    }

    private func memoText(for wheel: WheelPos) -> String? {
        guard let memo = snapshot.wheelMemos[wheel]?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty else {
            return nil
        }
        return memo
    }

    private func localizedWheelTitle(for wheel: WheelPos) -> String {
        // 左右表記をアルファベット2文字に統一することで、英日ともに記号化された表現で伝える
        switch wheel {
        case .FL: return language == .english ? "FL" : "FL"
        case .FR: return language == .english ? "FR" : "FR"
        case .RL: return language == .english ? "RL" : "RL"
        case .RR: return language == .english ? "RR" : "RR"
        }
    }

    private func localizedWheelShort(for wheel: WheelPos) -> String {
        // メモ欄など短い表示でも同じ略称を使用して認識のずれを防ぐ
        switch wheel {
        case .FL: return language == .english ? "FL" : "FL"
        case .FR: return language == .english ? "FR" : "FR"
        case .RL: return language == .english ? "RL" : "RL"
        case .RR: return language == .english ? "RR" : "RR"
        }
    }

    private func localizedZoneTitle(for zone: Zone) -> String {
        switch zone {
        case .OUT: return localized("Out", "Out")
        case .CL: return localized("CL", "CL")
        case .IN: return localized("In", "In")
        }
    }

    private func localized(_ english: String, _ japanese: String) -> String {
        language == .english ? english : japanese
    }

    private func zoneOrder(for wheel: WheelPos) -> [Zone] {
        // 右側のタイヤは外側(Out)が画面右に来るよう並び順を反転する
        switch wheel {
        case .FR, .RR:
            return [.IN, .CL, .OUT]
        case .FL, .RL:
            return [.OUT, .CL, .IN]
        }
    }

    private struct Field: Identifiable {
        enum Style {
            case standard
            case monospaced
        }

        let id = UUID()
        let label: String
        let value: String
        let style: Style
        let maxLines: Int
        let weight: Font.Weight

        init(label: String, value: String, style: Style = .standard, maxLines: Int = 1, weight: Font.Weight = .semibold) {
            self.label = label
            self.value = value
            self.style = style
            self.maxLines = maxLines
            self.weight = weight
        }
    }

    private struct LayoutMetrics {
        let sheetPadding: CGFloat
        let sheetCornerRadius: CGFloat
        let sectionSpacing: CGFloat
        let headerSpacing: CGFloat
        let fieldLabelSize: CGFloat
        let fieldValueSize: CGFloat
        let fieldSpacing: CGFloat
        let formRowSpacing: CGFloat
        let formColumnSpacing: CGFloat
        let sectionLabelSize: CGFloat
        let wheelSectionSpacing: CGFloat
        let wheelColumnSpacing: CGFloat
        let wheelInnerSpacing: CGFloat
        let wheelHeaderSpacing: CGFloat
        let zoneSpacing: CGFloat
        let zoneInnerSpacing: CGFloat
        let wheelLabelSize: CGFloat
        let temperatureFontSize: CGFloat
        let temperatureMinimumScale: CGFloat
        let temperatureTileVerticalPadding: CGFloat
        let temperatureTileHorizontalPadding: CGFloat
        let temperatureTileMinHeight: CGFloat
        let temperatureTileCornerRadius: CGFloat
        let pressureValueFontSize: CGFloat
        let pressureUnitFontSize: CGFloat
        let pressureLabelSize: CGFloat
        let pressureRowSpacing: CGFloat
        let pressureValueMinimumScale: CGFloat
        let pressureUnitMinimumScale: CGFloat
        let zoneLabelSize: CGFloat
        let memoFontSize: CGFloat
        let memoSpacing: CGFloat
        let memoLabelSize: CGFloat
        let memoLabelWidth: CGFloat
        let wheelCornerRadius: CGFloat
        let wheelPadding: CGFloat
        let canvasSpacing: CGFloat
        let languagePickerFont: CGFloat
        let headerTitleSize: CGFloat
        let paperHorizontalPadding: CGFloat
        let paperTopPadding: CGFloat
        let paperBottomPadding: CGFloat

        init(size: CGSize) {
            let shorter = min(size.width, size.height)

            if shorter < 360 {
                sheetPadding = 14
                sheetCornerRadius = 18
                sectionSpacing = 14
                headerSpacing = 8
                fieldLabelSize = 10
                fieldValueSize = 15
                fieldSpacing = 4
                formRowSpacing = 10
                formColumnSpacing = 12
                sectionLabelSize = 12
                wheelSectionSpacing = 12
                wheelColumnSpacing = 12
                wheelInnerSpacing = 10
                wheelHeaderSpacing = 6
                zoneSpacing = 10
                zoneInnerSpacing = 4
                wheelLabelSize = 14
                temperatureFontSize = 26
                temperatureMinimumScale = 0.65
                temperatureTileVerticalPadding = 9
                temperatureTileHorizontalPadding = 6
                temperatureTileMinHeight = 74
                temperatureTileCornerRadius = 12
                pressureValueFontSize = temperatureFontSize
                pressureUnitFontSize = 11
                pressureLabelSize = 10
                pressureRowSpacing = 6
                pressureValueMinimumScale = 0.6
                pressureUnitMinimumScale = 0.75
                zoneLabelSize = 11
                memoFontSize = 11
                memoSpacing = 6
                memoLabelSize = 11
                memoLabelWidth = 26
                wheelCornerRadius = 14
                wheelPadding = 10
                canvasSpacing = 16
                languagePickerFont = 12
                headerTitleSize = 18
                paperHorizontalPadding = 12
                paperTopPadding = 12
                paperBottomPadding = 12
            } else if shorter < 420 {
                sheetPadding = 18
                sheetCornerRadius = 20
                sectionSpacing = 18
                headerSpacing = 10
                fieldLabelSize = 11
                fieldValueSize = 17
                fieldSpacing = 4
                formRowSpacing = 12
                formColumnSpacing = 16
                sectionLabelSize = 13
                wheelSectionSpacing = 16
                wheelColumnSpacing = 14
                wheelInnerSpacing = 12
                wheelHeaderSpacing = 8
                zoneSpacing = 12
                zoneInnerSpacing = 6
                wheelLabelSize = 16
                temperatureFontSize = 32
                temperatureMinimumScale = 0.7
                temperatureTileVerticalPadding = 11
                temperatureTileHorizontalPadding = 8
                temperatureTileMinHeight = 86
                temperatureTileCornerRadius = 14
                pressureValueFontSize = temperatureFontSize
                pressureUnitFontSize = 12
                pressureLabelSize = 11
                pressureRowSpacing = 8
                pressureValueMinimumScale = 0.65
                pressureUnitMinimumScale = 0.8
                zoneLabelSize = 12
                memoFontSize = 12
                memoSpacing = 8
                memoLabelSize = 12
                memoLabelWidth = 30
                wheelCornerRadius = 16
                wheelPadding = 12
                canvasSpacing = 18
                languagePickerFont = 13
                headerTitleSize = 20
                paperHorizontalPadding = 16
                paperTopPadding = 16
                paperBottomPadding = 16
            } else {
                sheetPadding = 22
                sheetCornerRadius = 22
                sectionSpacing = 22
                headerSpacing = 12
                fieldLabelSize = 12
                fieldValueSize = 19
                fieldSpacing = 4
                formRowSpacing = 14
                formColumnSpacing = 20
                sectionLabelSize = 14
                wheelSectionSpacing = 18
                wheelColumnSpacing = 16
                wheelInnerSpacing = 14
                wheelHeaderSpacing = 10
                zoneSpacing = 14
                zoneInnerSpacing = 6
                wheelLabelSize = 18
                temperatureFontSize = 36
                temperatureMinimumScale = 0.75
                temperatureTileVerticalPadding = 13
                temperatureTileHorizontalPadding = 10
                temperatureTileMinHeight = 96
                temperatureTileCornerRadius = 16
                pressureValueFontSize = temperatureFontSize
                pressureUnitFontSize = 13
                pressureLabelSize = 12
                pressureRowSpacing = 10
                pressureValueMinimumScale = 0.7
                pressureUnitMinimumScale = 0.82
                zoneLabelSize = 13
                memoFontSize = 13
                memoSpacing = 10
                memoLabelSize = 13
                memoLabelWidth = 32
                wheelCornerRadius = 18
                wheelPadding = 14
                canvasSpacing = 20
                languagePickerFont = 14
                headerTitleSize = 22
                paperHorizontalPadding = 20
                paperTopPadding = 20
                paperBottomPadding = 20
            }
        }
    }

    private enum ReportLanguage: String, CaseIterable, Identifiable {
        case english
        case japanese

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .english: return "English"
            case .japanese: return "日本語"
            }
        }
    }
}
