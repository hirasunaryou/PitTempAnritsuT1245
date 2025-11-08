// MeasureView.swift
// BLEの Now/Hz/W/N の小さなヘッダ、
// ライブグラフ、接続ボタン群、BLESampleの購読(onReceive) を含む。
import SwiftUI
import UIKit

struct MeasureView: View {
    @EnvironmentObject var vm: SessionViewModel
    @EnvironmentObject var folderBM: FolderBookmark
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var ble: BluetoothService
    @EnvironmentObject var registry: DeviceRegistry

    @StateObject private var speech = SpeechMemoManager()
    @State private var selectedWheel: WheelPos = .FL
    @State private var showRaw = false
    @State private var focusTick = 0
    @State private var showMetaEditor = false
    @State private var showConnectSheet = false
    @State private var shareURL: URL?
    @State private var showUploadAlert = false
    @State private var uploadedPathText = ""
    @State private var uploadMessage = ""
    @State private var isManualMode = false
    @State private var manualValues: [WheelPos: [Zone: String]] = [:]
    @State private var manualErrors: [WheelPos: [Zone: String]] = [:]
    @State private var manualSuccess: [WheelPos: [Zone: Date]] = [:]
    @State private var manualMemos: [WheelPos: String] = [:]
    @State private var manualMemoSuccess: [WheelPos: Date] = [:]
    @State private var showNextSessionDialog = false
    @State private var showWheelDetails = false

    private let manualTemperatureRange: ClosedRange<Double> = -50...200
    private let zoneButtonHeight: CGFloat = 112
    private static let manualTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    private static let captureDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let captureTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    topStatusRow

                    if let entry = vm.autosaveStatusEntry {
                        autosaveBanner(entry)
                    }

                    sectionCard {
                        tyreControlsSection
                    }

                    sectionCard {
                        headerReadOnly
                    }

                    sectionCard {
                        liveChartSection
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(appTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    appTitleHeader
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showMetaEditor = true }
                }
            }
            .sheet(isPresented: $showMetaEditor) {
                MetaEditorView()
                    .environmentObject(vm)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showConnectSheet) {
                ConnectView()
                    .environmentObject(ble)
                    .environmentObject(registry)
            }
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let url = shareURL {
                    ActivityView(items: [url])
                }
            }
        }
        .onAppear {
            speech.requestAuth()
            ble.startScan()
            ble.autoConnectOnDiscover = settings.bleAutoConnect
            // registry の autoConnect=true だけを優先対象に
            let preferred = Set(registry.known.filter { $0.autoConnect }.map { $0.id })
            ble.setPreferredIDs(preferred)   // ← ここを関数呼び出しに
            if let current = vm.currentWheel {
                selectedWheel = current
            }
            print("[UI] MeasureView appear")
        }

        .onDisappear {
            vm.stopAll()
        }
        .onReceive(ble.temperatureStream) { sample in
            vm.ingestBLESample(sample)
        }
        .onReceive(vm.$currentWheel) { newWheel in
            if let newWheel { selectedWheel = newWheel }
        }
        .onChange(of: isManualMode) { _, newValue in
            if newValue {
                clearManualFeedback(for: selectedWheel)
                syncManualDefaults(for: selectedWheel)
                showWheelDetails = true
            } else {
                clearManualFeedback()
            }
        }
        .onChange(of: selectedWheel) { _, newWheel in
            if isManualMode {
                clearManualFeedback(for: newWheel)
                syncManualDefaults(for: newWheel)
            }
            showWheelDetails = false
        }
        .onReceive(vm.$results) { _ in
            if isManualMode { syncManualDefaults(for: selectedWheel) }
        }
        .onReceive(vm.$wheelMemos) { _ in
            if isManualMode { syncManualMemo(for: selectedWheel) }
        }
        .onReceive(vm.$sessionResetID) { _ in
            selectedWheel = .FL
            manualValues.removeAll()
            manualMemos.removeAll()
            clearManualFeedback()
            showWheelDetails = false
            if isManualMode {
                syncManualDefaults(for: .FL)
                syncManualMemo(for: .FL)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pitUploadFinished)) { note in
            if let url = note.userInfo?["url"] as? URL {
                let comps = url.pathComponents.suffix(2).joined(separator: "/")
                uploadMessage = "Saved to: \(comps)"
                showUploadAlert = true
            }
        }
        .onChange(of: folderBM.statusLabel) { _, newVal in
            if case .done = newVal, let p = folderBM.lastUploadedDestination {
                let hint = p.deletingLastPathComponent().lastPathComponent
                uploadMessage = "Uploaded to: \(hint)"
                showUploadAlert = true
            }
        }
        // アラートはこれ1つに
        .alert("Upload complete", isPresented: $showUploadAlert) {
            Button("OK", role: .cancel) { }
        } message: { Text(uploadMessage) }
        .onChange(of: folderBM.statusLabel) { _, newVal in
            if case .done = newVal {
                let p = folderBM.lastUploadedDestination
                // 例: "iCloud/YourFolder/2025-10-13"
                let parent = p?.deletingLastPathComponent()
                let hint = parent?.lastPathComponent ?? ""
                uploadMessage = "Uploaded to: \(hint)"
                showUploadAlert = true
            }
        }
        .confirmationDialog(
            "次の測定の準備 / Prepare next measurement",
            isPresented: $showNextSessionDialog,
            titleVisibility: .visible
        ) {
            Button("結果のみクリア / Clear results") {
                handleNextSessionChoice(.keepAllMeta)
            }
            Button("車両Noのみ保持 / Keep car number") {
                handleNextSessionChoice(.keepCarIdentity)
            }
            Button("すべて初期化 / Reset everything", role: .destructive) {
                handleNextSessionChoice(.resetEverything)
            }
            Button("キャンセル / Cancel", role: .cancel) { }
        } message: {
            Text("次の車両に移る際のリセット方法を選択してください。\nChoose how to reset before the next vehicle arrives.")
        }
    }

    private var topStatusRow: some View { connectBar }

    private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.secondary.opacity(0.08))
            )
    }

    private var liveChartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Temp (last \(Int(settings.chartWindowSec))s)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {
                MiniTempChart(data: vm.live)

                if let v = ble.latestTemperature {
                    OverlayNow(value: v)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // --- 以降はUI部品（元のまま） ---
    private func autosaveBanner(_ entry: UILogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.level.iconName)
                .foregroundStyle(entry.level.tintColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message)
                    .font(.footnote)
                    .foregroundStyle(entry.level.tintColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(entry.level.tintColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(entry.level.tintColor.opacity(0.25))
        )
    }
    private var manualModeToggle: some View {
        Toggle(isOn: $isManualMode) {
            Label("Manual Mode", systemImage: "hand.tap.fill")
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 4)
    }

    private var headerReadOnly: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetaRow(label: "TRACK", value: vm.meta.track)
            MetaRow(label: "DATE",  value: vm.meta.date)
            MetaRow(label: "CAR",   value: vm.meta.car)
            MetaRow(label: "DRIVER",value: vm.meta.driver)
            MetaRow(label: "TYRE",  value: vm.meta.tyre)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                MetaRow(label: "TIME", value: vm.meta.time)
                MetaRow(label: "LAP",  value: vm.meta.lap)
            }
            MetaRow(label: "CHECKER", value: vm.meta.checker)
        }
    }

    private func MetaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "-" : value)
                .font(.headline)
        }
        .padding(.vertical, 2)
    }

    private var wheelSelector: some View {
        let wheels: [WheelPos] = [.FL, .FR, .RL, .RR]
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

        return VStack(alignment: .leading, spacing: 8) {
            Text("Tyre position")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(wheels, id: \.self) { wheel in
                    wheelTile(for: wheel)
                }
            }
        }
    }

    private func wheelTile(for wheel: WheelPos) -> some View {
        let isSelected = selectedWheel == wheel
        let headlineFont = Font.system(.headline, design: .rounded)
        let isActive = vm.currentWheel == wheel
        let zoneValues = zoneOrder(for: wheel).map { ($0, displayValue(w: wheel, z: $0)) }
        let hasZoneSummary = zoneValues.contains { $0.1 != "--" }

        return Button {
            let (prevWheel, prevText) = speech.stopAndTakeText()
            if let pw = prevWheel, !prevText.isEmpty {
                let vmRef = vm
                Task { @MainActor in vmRef.appendMemo(prevText, to: pw) }
            }
            selectedWheel = wheel
            Haptics.impactLight()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(shortTitle(wheel))
                        .font(headlineFont.weight(.semibold))
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel(title(wheel))

                    if isActive {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }

                if hasZoneSummary {
                    HStack(spacing: 8) {
                        ForEach(zoneValues, id: \.0) { zone, value in
                            VStack(spacing: 2) {
                                Text(zoneShortName(zone))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(value)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Double tap to select \(title(wheel))")
    }

    @ViewBuilder
    private func wheelDetailCard(for wheel: WheelPos) -> some View {
        let zones = zoneOrder(for: wheel)

        VStack(alignment: .leading, spacing: 12) {
            wheelCardHeader(for: wheel)
            wheelCardSummary(for: wheel, zones: zones)
            wheelCardMemo(for: wheel)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }

    @ViewBuilder
    private func wheelCardHeader(for wheel: WheelPos) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title(wheel))
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if vm.currentWheel == wheel {
                Label("Capturing", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private func wheelCardSummary(for wheel: WheelPos, zones: [Zone]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(zones, id: \.self) { zone in
                    summaryChip(for: zone, wheel: wheel)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(zones, id: \.self) { zone in
                    summaryChip(for: zone, wheel: wheel)
                }
            }
        }
    }

    @ViewBuilder
    private func wheelCardMemo(for wheel: WheelPos) -> some View {
        if let memo = vm.wheelMemos[wheel], !memo.isEmpty {
            Text(memo)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private func shortTitle(_ wheel: WheelPos) -> String {
        switch wheel {
        case .FL: return "Front Left"
        case .FR: return "Front Right"
        case .RL: return "Rear Left"
        case .RR: return "Rear Right"
        }
    }

    private var tyreControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            wheelSelector

            zoneSelector(for: selectedWheel)

            selectedWheelSection(selectedWheel)
        }
    }

    private func selectedWheelSection(_ wheel: WheelPos) -> some View {
        DisclosureGroup(isExpanded: $showWheelDetails) {
            VStack(alignment: .leading, spacing: 14) {
                manualModeToggle

                if isManualMode {
                    manualEntrySection(for: wheel)
                }

                voiceMemoSection(for: wheel)

                Divider()

                wheelDetailCard(for: wheel)
            }
        } label: {
            Label(
                showWheelDetails ? "Hide extra controls / 詳細を閉じる" : "More controls / 詳細設定",
                systemImage: showWheelDetails ? "chevron.up.circle.fill" : "chevron.down.circle"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .animation(.easeInOut(duration: 0.2), value: showWheelDetails)
        .animation(.easeInOut(duration: 0.2), value: wheel)
    }

    private func zoneSelector(for wheel: WheelPos) -> some View {
        let zones = zoneOrder(for: wheel)

        return VStack(alignment: .leading, spacing: 8) {
            Text("\(title(wheel)) zones")
                .font(.caption)
                .foregroundStyle(.secondary)

            tyreZoneContainer {
                HStack(spacing: 10) {
                    ForEach(zones, id: \.self) { zone in
                        zoneButton(wheel, zone)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func tyreZoneContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
    }

    private func manualEntrySection(for wheel: WheelPos) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual entry for \(title(wheel))")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(zoneOrder(for: wheel), id: \.self) { zone in
                manualZoneRow(for: wheel, zone: zone)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Wheel memo")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Memo (optional)", text: manualMemoBinding(for: wheel))
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)

                Button {
                    persistManualMemo(for: wheel)
                } label: {
                    Label("Save memo", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                if let savedAt = manualMemoSuccessDate(for: wheel) {
                    Text("Memo saved \(Self.manualTimeFormatter.string(from: savedAt))")
                        .font(.caption)
                        .foregroundStyle(Color.green)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemBackground)))
    }

    private func manualZoneRow(for wheel: WheelPos, zone: Zone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(zoneDisplayName(zone))
                    .font(.headline)
                Spacer()
                Button {
                    commitManualEntry(wheel: wheel, zone: zone)
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
            }

            TextField("85.0", text: manualValueBinding(for: wheel, zone: zone))
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .disableAutocorrection(true)
                .onSubmit { commitManualEntry(wheel: wheel, zone: zone) }

            Stepper(value: manualStepperBinding(for: wheel, zone: zone), in: manualTemperatureRange, step: 0.5) {
                Text("Adjust: \(manualValueDisplay(for: wheel, zone: zone))℃")
                    .monospacedDigit()
            }

            if let error = manualError(for: wheel, zone: zone) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            } else if let savedAt = manualSuccessDate(for: wheel, zone: zone) {
                Text("Saved \(Self.manualTimeFormatter.string(from: savedAt))")
                    .font(.caption)
                    .foregroundStyle(Color.green)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground).opacity(0.6)))
    }

    private func manualValueBinding(for wheel: WheelPos, zone: Zone) -> Binding<String> {
        Binding(
            get: { manualValues[wheel]?[zone] ?? "" },
            set: { newValue in updateManualValue(newValue, for: wheel, zone: zone) }
        )
    }

    private func manualStepperBinding(for wheel: WheelPos, zone: Zone) -> Binding<Double> {
        Binding(
            get: {
                if let text = manualValues[wheel]?[zone], let parsed = parseManualValue(text) {
                    return parsed
                }
                return defaultManualValue(for: wheel, zone: zone)
            },
            set: { newValue in
                updateManualValue(String(format: "%.1f", newValue), for: wheel, zone: zone)
            }
        )
    }

    private func manualValueDisplay(for wheel: WheelPos, zone: Zone) -> String {
        if let text = manualValues[wheel]?[zone], !text.isEmpty {
            return text
        }
        if let existing = vm.results.first(where: { $0.wheel == wheel && $0.zone == zone }), existing.peakC.isFinite {
            return String(format: "%.1f", existing.peakC)
        }
        return "--"
    }

    private func manualError(for wheel: WheelPos, zone: Zone) -> String? {
        manualErrors[wheel]?[zone]
    }

    private func manualSuccessDate(for wheel: WheelPos, zone: Zone) -> Date? {
        manualSuccess[wheel]?[zone]
    }

    private func manualMemoBinding(for wheel: WheelPos) -> Binding<String> {
        Binding(
            get: { manualMemos[wheel] ?? vm.wheelMemos[wheel] ?? "" },
            set: { newValue in
                manualMemos[wheel] = newValue
                manualMemoSuccess.removeValue(forKey: wheel)
            }
        )
    }

    private func manualMemoSuccessDate(for wheel: WheelPos) -> Date? {
        manualMemoSuccess[wheel]
    }

    private func updateManualValue(_ value: String, for wheel: WheelPos, zone: Zone) {
        var zoneMap = manualValues[wheel] ?? [:]
        zoneMap[zone] = value
        manualValues[wheel] = zoneMap

        setManualError(nil, for: wheel, zone: zone)
        setManualSuccess(nil, for: wheel, zone: zone)
    }

    private func defaultManualValue(for wheel: WheelPos, zone: Zone) -> Double {
        if let existing = vm.results.first(where: { $0.wheel == wheel && $0.zone == zone }), existing.peakC.isFinite {
            return existing.peakC
        }
        return 60.0
    }

    private func setManualError(_ message: String?, for wheel: WheelPos, zone: Zone) {
        var zoneMap = manualErrors[wheel] ?? [:]
        if let message {
            zoneMap[zone] = message
        } else {
            zoneMap.removeValue(forKey: zone)
        }
        manualErrors[wheel] = zoneMap.isEmpty ? nil : zoneMap
    }

    private func setManualSuccess(_ date: Date?, for wheel: WheelPos, zone: Zone) {
        var zoneMap = manualSuccess[wheel] ?? [:]
        if let date {
            zoneMap[zone] = date
        } else {
            zoneMap.removeValue(forKey: zone)
        }
        manualSuccess[wheel] = zoneMap.isEmpty ? nil : zoneMap
    }

    private func commitManualEntry(wheel: WheelPos, zone: Zone) {
        let rawText = manualValues[wheel]?[zone] ?? ""
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setManualError("Enter a temperature", for: wheel, zone: zone)
            setManualSuccess(nil, for: wheel, zone: zone)
            return
        }

        guard let value = parseManualValue(trimmed) else {
            setManualError("Invalid number", for: wheel, zone: zone)
            setManualSuccess(nil, for: wheel, zone: zone)
            return
        }

        guard manualTemperatureRange.contains(value) else {
            let minText = String(format: "%.0f", manualTemperatureRange.lowerBound)
            let maxText = String(format: "%.0f", manualTemperatureRange.upperBound)
            setManualError("Value must be between \(minText)℃ and \(maxText)℃", for: wheel, zone: zone)
            setManualSuccess(nil, for: wheel, zone: zone)
            return
        }

        let formatted = String(format: "%.1f", value)
        var memo = manualMemos[wheel] ?? vm.wheelMemos[wheel] ?? ""
        memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        manualMemos[wheel] = memo

        vm.commitManualValue(
            wheel: wheel,
            zone: zone,
            value: value,
            memo: memo,
            timestamp: Date()
        )

        updateManualValue(formatted, for: wheel, zone: zone)
        setManualError(nil, for: wheel, zone: zone)
        setManualSuccess(Date(), for: wheel, zone: zone)
        manualMemoSuccess[wheel] = Date()
    }

    private func parseManualValue(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func persistManualMemo(for wheel: WheelPos) {
        let trimmed = (manualMemos[wheel] ?? vm.wheelMemos[wheel] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        manualMemos[wheel] = trimmed
        if trimmed.isEmpty {
            vm.wheelMemos.removeValue(forKey: wheel)
        } else {
            vm.wheelMemos[wheel] = trimmed
        }
        manualMemoSuccess[wheel] = Date()
    }

    private func syncManualDefaults(for wheel: WheelPos) {
        var zoneMap = manualValues[wheel] ?? [:]
        for zone in Zone.allCases {
            if let existing = vm.results.first(where: { $0.wheel == wheel && $0.zone == zone }), existing.peakC.isFinite {
                zoneMap[zone] = String(format: "%.1f", existing.peakC)
            } else {
                zoneMap[zone] = zoneMap[zone] ?? ""
            }
        }
        manualValues[wheel] = zoneMap
        manualMemos[wheel] = vm.wheelMemos[wheel] ?? manualMemos[wheel] ?? ""
    }

    private func syncManualMemo(for wheel: WheelPos) {
        manualMemos[wheel] = vm.wheelMemos[wheel] ?? manualMemos[wheel] ?? ""
    }

    private func clearManualFeedback(for wheel: WheelPos? = nil) {
        if let wheel {
            manualErrors[wheel] = nil
            manualSuccess[wheel] = nil
            manualMemoSuccess[wheel] = nil
        } else {
            manualErrors.removeAll()
            manualSuccess.removeAll()
            manualMemoSuccess.removeAll()
        }
    }

    private func zoneOrder(for wheel: WheelPos) -> [Zone] {
        if wheel == .FL || wheel == .RL {
            return [.OUT, .CL, .IN]
        } else {
            return [.IN, .CL, .OUT]
        }
    }

    private func voiceMemoSection(for wheel: WheelPos) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Voice memo").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if speech.isRecording && speech.currentWheel == wheel {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Recording…").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                if speech.isRecording && speech.currentWheel == wheel {
                    Button("Stop") {
                        speech.stop()
                        let text = speech.takeFinalText()
                        if !text.isEmpty {
                            let vmRef = vm
                            Task { @MainActor in vmRef.appendMemo(text, to: wheel) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        let (pw, prevText) = speech.stopAndTakeText()
                        if let pw, !prevText.isEmpty {
                            let vmRef = vm
                            Task { @MainActor in vmRef.appendMemo(prevText, to: pw) }
                        }
                        try? speech.start(for: wheel)
                        Haptics.impactLight()
                    } label: {
                        Label("Record memo", systemImage: "mic.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!speech.isAuthorized)
                }
                Spacer()
            }
            if let memo = vm.wheelMemos[wheel], !memo.isEmpty {
                Text(memo)
                    .font(.footnote)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemBackground))
        )
    }

    private func summaryChip(for zone: Zone, wheel: WheelPos) -> some View {
        let value = displayValue(w: wheel, z: zone)
        return HStack(spacing: 6) {
            Text(zoneDisplayName(zone))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.12))
        )
    }

    private func zoneButton(_ wheel: WheelPos, _ zone: Zone) -> some View {
        let isRunning = vm.currentWheel == wheel && vm.currentZone == zone
        let valueText = displayValue(w: wheel, z: zone)
        let autoStopLimit = Double(settings.autoStopLimitSec)
        let progress = autoStopLimit > 0 ? min(vm.elapsed / autoStopLimit, 1.0) : 0

        return Button {
            selectedWheel = wheel
            vm.tapCell(wheel: wheel, zone: zone)
            focusTick &+= 1
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        zoneBadge(for: zone)

                        Spacer(minLength: 8)

                        zoneValueLabel(for: zone, valueText: valueText, isLive: isRunning)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        zoneBadge(for: zone)

                        zoneValueLabel(for: zone, valueText: valueText, isLive: isRunning)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    if isRunning {
                        if settings.autoStopLimitSec > 0 {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(Color.accentColor)
                            Text(String(format: "Auto stop in %.1fs", max(0, autoStopLimit - vm.elapsed)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text("Tap again to stop")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let stamp = captureTimestamp(for: wheel, zone: zone) {
                        timestampLabel(date: stamp.date, time: stamp.time)
                    } else {
                        Text("Tap to capture")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: zoneButtonHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isRunning ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isRunning ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isRunning ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(wheel)) \(zoneDisplayName(zone)) button")
        .accessibilityHint(isRunning ? "Capturing" : "Double tap to start capture")
    }

    @ViewBuilder
    private func zoneBadge(for zone: Zone) -> some View {
        Text(zoneShortName(zone))
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
    }

    @ViewBuilder
    private func zoneValueLabel(for zone: Zone, valueText: String, isLive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valueText)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueText == "--" ? .tertiary : .primary)
                .lineLimit(1)
                .allowsTightening(true)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, -6)
                .offset(y: zoneValueOffset(for: zone))
                .accessibilityLabel("\(zoneDisplayName(zone)) value \(valueText)")

            if isLive && valueText != "--" {
                Text("Live")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                    )
                    .accessibilityLabel("Live reading")
            }
        }
    }

    @ViewBuilder
    private func timestampLabel(date: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(date)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)

            Text(time)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func zoneValueOffset(for zone: Zone) -> CGFloat {
        switch zone {
        case .OUT: return -6
        case .CL: return 0
        case .IN: return 6
        }
    }

    private func zoneDisplayName(_ zone: Zone) -> String {
        switch zone {
        case .IN: return "IN"
        case .CL: return "CENTER"
        case .OUT: return "OUT"
        }
    }

    private func zoneShortName(_ zone: Zone) -> String {
        switch zone {
        case .IN: return "IN"
        case .CL: return "CL"
        case .OUT: return "OUT"
        }
    }

    private func title(_ w: WheelPos) -> String {
        switch w { case .FL: return "Front Left"; case .FR: return "Front Right"
        case .RL: return "Rear Left"; case .RR: return "Rear Right" }
    }

    private func displayValue(w: WheelPos, z: Zone) -> String {
        if vm.currentWheel == w && vm.currentZone == z {
            return vm.latestValueText
        }

        if let r = vm.results.first(where: { $0.wheel == w && $0.zone == z }) {
            return r.peakC.isFinite ? String(format: "%.1f", r.peakC) : "--"
        }
        return "--"
    }

    private func captureTimestamp(for wheel: WheelPos, zone: Zone) -> (date: String, time: String)? {
        if let manualDate = manualSuccessDate(for: wheel, zone: zone) {
            return (
                date: Self.captureDateFormatter.string(from: manualDate),
                time: captureTimeText(for: manualDate)
            )
        }

        guard let result = vm.results.first(where: { $0.wheel == wheel && $0.zone == zone }),
              result.peakC.isFinite else { return nil }

        let endedAt = result.endedAt
        return (
            date: Self.captureDateFormatter.string(from: endedAt),
            time: captureTimeText(for: endedAt)
        )
    }

    private func captureTimeText(for date: Date) -> String {
        let core = Self.captureTimeFormatter.string(from: date)
        let abbreviation = TimeZone.current.abbreviation() ?? ""
        return abbreviation.isEmpty ? core : core + " " + abbreviation
    }

    private func handleNextSessionChoice(_ option: SessionViewModel.NextSessionCarryOver) {
        let (prevWheel, prevText) = speech.stopAndTakeText()
        if let pw = prevWheel, !prevText.isEmpty {
            let vmRef = vm
            Task { @MainActor in vmRef.appendMemo(prevText, to: pw) }
        }

        vm.prepareForNextSession(carryOver: option)
        isManualMode = false
        manualValues.removeAll()
        manualMemos.removeAll()
        clearManualFeedback()
        Haptics.impactMedium()
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button {
                showNextSessionDialog = true
            } label: {
                Label("Next", systemImage: "arrowshape.turn.up.right.circle")
            }
            .buttonStyle(.bordered)

            Button("Export CSV") {
                // 1) CSVを両フォーマットで生成（デバイス名を付与）
                vm.exportCSV(deviceName: ble.deviceName)

                // 2) アップロード先は「旧フォーマット優先」（ライブラリ互換）
                if let url = vm.lastLegacyCSV ?? vm.lastCSV {
                    folderBM.upload(file: url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }



    // BLEの状態、操作、診断をまとめたカード
    private var connectBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    bleHeader
                    captureStatusRow
                }

                Spacer(minLength: 0)

                liveTemperatureBadge
            }

            connectButtons
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Text(String(format: "Hz: %.1f", ble.notifyHz))
                Text("N: \(ble.notifyCountUI)")
                if let v = ble.latestTemperature {
                    Text(String(format: "Now: %.1f℃", v))
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var liveTemperatureBadge: some View {
        let valueText: String
        if let live = vm.liveTemperatureC, live.isFinite {
            valueText = String(format: "%.1f", live)
        } else {
            valueText = "--"
        }

        return HStack(alignment: .lastTextBaseline, spacing: 4) {
            Image(systemName: "thermometer")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(valueText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text("℃")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var captureStatusRow: some View {
        HStack(spacing: 6) {
            if vm.isCaptureActive {
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 7)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
            }

            Text(captureStatusText())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
    }

    private func captureStatusText() -> String {
        if vm.isCaptureActive, let wheel = vm.currentWheel, let zone = vm.currentZone {
            return "Capturing / 計測中: \(title(wheel)) \(zoneDisplayName(zone))"
        }
        return "Standby / 待機中"
    }

    private var bleHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BLE: " + stateText())
                .font(.subheadline)

            if let name = ble.deviceName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var connectButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Button(scanButtonTitle()) { scanOrDisconnect() }
                    .buttonStyle(.borderedProminent)
                Button("Devices…") { showConnectSheet = true }
                    .buttonStyle(.bordered)
            }

            VStack(spacing: 8) {
                Button(scanButtonTitle()) { scanOrDisconnect() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Devices…") { showConnectSheet = true }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
    }


    private func stateText() -> String {
        switch ble.connectionState {
        case .idle: "idle"; case .scanning: "scanning"; case .connecting: "connecting"
        case .ready: "ready"; case .failed(let m): "failed: \(m)"
        }
    }
    private func scanButtonTitle() -> String {
        switch ble.connectionState { case .idle, .failed: "Scan"; default: "Disconnect" }
    }
    private func scanOrDisconnect() {
        switch ble.connectionState { case .idle, .failed: ble.startScan(); default: ble.disconnect() }
    }
    
    // MARK: - Overlay big "Now" on chart
    private struct OverlayNow: View {
        @Environment(\.colorScheme) private var scheme
        let value: Double

        var body: some View {
            // ダークは白、ライトは黒ベースの半透明
            let color = (scheme == .dark ? Color.white : Color.black).opacity(0.35)

            Text(String(format: "%.1f℃", value))
                .font(.system(size: 78, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.3)
                .foregroundStyle(color)
                .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.05), radius: 8, x: 0, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.2), value: value)
        }
    }
    private var appTitleHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "thermometer.medium")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(appTitle.uppercased())
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .tracking(1.5)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.1)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
        .foregroundStyle(Color.primary.opacity(0.85))
        .accessibilityLabel(appTitle)
    }

    // MeasureView.swift
    private var appTitle: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? "PitTemp" // フォールバック
    }

    struct ActivityView: UIViewControllerRepresentable {
        let items: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }
        func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
    }


//    // MARK: - Big Now Reading
//    @ViewBuilder
//    private var bigNow: some View {
//        if let v = ble.latestTemperature {
//            Text(String(format: "%.1f℃", v))
//                .font(.system(size: 72, weight: .bold, design: .rounded))
//                .monospacedDigit()
//                .lineLimit(1)
//                .minimumScaleFactor(0.5)
//                .kerning(0.5)
//                .frame(maxWidth: .infinity, alignment: .center)
//                .padding(.vertical, 4)
//                .transition(.opacity.combined(with: .scale))
//        }
//    }



}

#Preview("MeasureView – Light") {
    let fixtures = MeasureViewPreviewFixtures()
    return MeasureView()
        .environmentObject(fixtures.viewModel)
        .environmentObject(fixtures.folderBookmark)
        .environmentObject(fixtures.settings)
        .environmentObject(fixtures.bluetooth)
        .environmentObject(fixtures.registry)
        .environmentObject(fixtures.logStore)
}

#Preview("MeasureView – Accessibility", traits: .sizeThatFitsLayout) {
    let fixtures = MeasureViewPreviewFixtures()
    return MeasureView()
        .environmentObject(fixtures.viewModel)
        .environmentObject(fixtures.folderBookmark)
        .environmentObject(fixtures.settings)
        .environmentObject(fixtures.bluetooth)
        .environmentObject(fixtures.registry)
        .environmentObject(fixtures.logStore)
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}
