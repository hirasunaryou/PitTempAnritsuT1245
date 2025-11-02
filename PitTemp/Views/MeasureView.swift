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

    private let manualTemperatureRange: ClosedRange<Double> = -50...200
    private static let manualTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let entry = vm.autosaveStatusEntry {
                        autosaveBanner(entry)
                    }
                    connectBar
                    HStack(spacing: 12) {
                        Text(String(format: "Hz: %.1f", ble.notifyHz))
                        Text("W: \(ble.writeCount)")
                        Text("N: \(ble.notifyCountUI)")
                        if let v = ble.latestTemperature {
                            Text(String(format: "Now: %.1f℃", v)).monospacedDigit()
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

//                    if let v = ble.latestTemperature {
//                        Text(String(format: "BLE Now: %.1f℃", v))
//                            .font(.title3).monospacedDigit()
//                    }

                    headerReadOnly
                    wheelSelector
                    manualModeToggle
                    selectedWheelSection(selectedWheel)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live Temp (last \(Int(settings.chartWindowSec))s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ZStack {
                            // 元のチャート
                            MiniTempChart(data: vm.live)

                            // 半透明の現在温度をオーバーレイ
                            if let v = ble.latestTemperature {
                                OverlayNow(value: v)   // ← 下の補助Viewを追加します
                                    .allowsHitTesting(false) // 操作はチャートに通す
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(appTitle)
            .toolbar { Button("Edit") { showMetaEditor = true } }
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
            } else {
                clearManualFeedback()
            }
        }
        .onChange(of: selectedWheel) { _, newWheel in
            if isManualMode {
                clearManualFeedback(for: newWheel)
                syncManualDefaults(for: newWheel)
            }
        }
        .onReceive(vm.$results) { _ in
            if isManualMode { syncManualDefaults(for: selectedWheel) }
        }
        .onReceive(vm.$wheelMemos) { _ in
            if isManualMode { syncManualMemo(for: selectedWheel) }
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
    }

    private var headerReadOnly: some View {
        VStack(alignment: .leading, spacing: 6) {
            MetaRow(label: "TRACK", value: vm.meta.track)
            MetaRow(label: "DATE",  value: vm.meta.date)
            MetaRow(label: "CAR",   value: vm.meta.car)
            MetaRow(label: "DRIVER",value: vm.meta.driver)
            MetaRow(label: "TYRE",  value: vm.meta.tyre)
            HStack {
                MetaRow(label: "TIME", value: vm.meta.time)
                Spacer(minLength: 12)
                MetaRow(label: "LAP",  value: vm.meta.lap)
            }
            MetaRow(label: "CHECKER", value: vm.meta.checker)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func MetaRow(label: String, value: String) -> some View {
        HStack { Text(label).font(.caption).foregroundStyle(.secondary); Spacer(); Text(value.isEmpty ? "-" : value).font(.headline) }
    }

    private var wheelSelector: some View {
        let wheels: [WheelPos] = [.FL, .FR, .RL, .RR]
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Tyre position").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(wheels, id: \.self) { wheelButton($0) }
            }
        }
    }

    private func wheelButton(_ wheel: WheelPos) -> some View {
        let isSelected = selectedWheel == wheel
        return Button {
            let (prevWheel, prevText) = speech.stopAndTakeText()
            if let pw = prevWheel, !prevText.isEmpty {
                let vmRef = vm
                Task { @MainActor in vmRef.appendMemo(prevText, to: pw) }
            }
            selectedWheel = wheel
            Haptics.impactLight()
        } label: {
            wheelCard(for: wheel, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(wheel))
    }

    @ViewBuilder
    private func wheelCard(for wheel: WheelPos, isSelected: Bool) -> some View {
        let zones = zoneOrder(for: wheel)

        VStack(alignment: .leading, spacing: 10) {
            wheelCardHeader(for: wheel)
            wheelCardSummary(for: wheel, zones: zones)
            wheelCardMemo(for: wheel)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.accentColor.opacity(0.20) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1)
        )
    }

    @ViewBuilder
    private func wheelCardHeader(for wheel: WheelPos) -> some View {
        HStack {
            Text(title(wheel)).font(.headline)
            Spacer()
            if vm.currentWheel == wheel {
                Label("active", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private func wheelCardSummary(for wheel: WheelPos, zones: [Zone]) -> some View {
        HStack(spacing: 8) {
            ForEach(zones, id: \.self) { zone in
                summaryChip(for: zone, wheel: wheel)
            }
        }
    }

    @ViewBuilder
    private func wheelCardMemo(for wheel: WheelPos) -> some View {
        if let memo = vm.wheelMemos[wheel], !memo.isEmpty {
            Text(memo)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func selectedWheelSection(_ wheel: WheelPos) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            zoneSelector(for: wheel)
            if isManualMode {
                manualEntrySection(for: wheel)
            }
            voiceMemoSection(for: wheel)
        }
        .animation(.easeInOut(duration: 0.2), value: wheel)
    }

    private func zoneSelector(for wheel: WheelPos) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title(wheel)) zones").font(.caption).foregroundStyle(.secondary)
            ForEach(zoneOrder(for: wheel), id: \.self) { zone in
                zoneButton(wheel, zone)
            }
        }
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
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(.systemBackground).opacity(0.7))
        )
    }

    private func zoneButton(_ wheel: WheelPos, _ zone: Zone) -> some View {
        let isRunning = vm.currentWheel == wheel && vm.currentZone == zone
        let valueText = displayValue(w: wheel, z: zone)
        let progress = min(vm.elapsed / Double(settings.durationSec), 1.0)

        return Button {
            selectedWheel = wheel
            vm.tapCell(wheel: wheel, zone: zone)
            focusTick &+= 1
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(zoneDisplayName(zone))
                        .font(.headline)
                    Spacer()
                    Text(valueText)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                }
                if isRunning {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text(String(format: "Remaining %.1fs", max(0, Double(settings.durationSec) - vm.elapsed)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(valueText == "--" ? "Tap to capture" : "Last captured")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isRunning ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isRunning ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isRunning ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(wheel)) \(zoneDisplayName(zone)) button")
    }

    private func zoneDisplayName(_ zone: Zone) -> String {
        switch zone {
        case .IN: return "IN"
        case .CL: return "CENTER"
        case .OUT: return "OUT"
        }
    }

    private func title(_ w: WheelPos) -> String {
        switch w { case .FL: return "Front Left"; case .FR: return "Front Right"
        case .RL: return "Rear Left"; case .RR: return "Rear Right" }
    }

    private func displayValue(w: WheelPos, z: Zone) -> String {
        if let r = vm.results.first(where: { $0.wheel == w && $0.zone == z }) {
            return r.peakC.isFinite ? String(format: "%.1f", r.peakC) : "--"
        }
        if vm.currentWheel == w && vm.currentZone == z { return vm.latestValueText }
        return "--"
    }

    // 置き換え: 下部バーは「Stop」「Next」「Export CSV」のみ
    // MeasureView.swift の bottomBar 内
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Stop") { vm.stopAll() }
                .buttonStyle(.bordered)

            Spacer()

            Button("Next") { vm.receiveSpecial("<RET>") }
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



    // 上部バーは「Scan/Disconnect」と「Devices…」だけに
    private var connectBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("BLE: " + stateText()).font(.subheadline)
                Spacer()
                if let name = ble.deviceName {
                    Text(name).font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button(scanButtonTitle()) { scanOrDisconnect() }
                    .buttonStyle(.borderedProminent)
                Button("Devices…") { showConnectSheet = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(Color(.secondarySystemBackground)))
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
