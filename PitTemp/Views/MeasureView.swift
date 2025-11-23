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
    @EnvironmentObject var driveService: GoogleDriveService

    @StateObject private var speech = SpeechMemoManager()
    @StateObject private var pressureSpeech = SpeechMemoManager()
    @StateObject private var history = SessionHistoryStore()
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
    @State private var manualPressureValues: [WheelPos: String] = [:]
    @State private var manualPressureErrors: [WheelPos: String] = [:]
    @State private var manualPressureSuccess: [WheelPos: Date] = [:]
    @State private var showNextSessionDialog = false
    @State private var showWheelDetails = false
    @State private var showHistorySheet = false
    @State private var historyError: String? = nil
    @State private var historyEditingEnabled = false
    @State private var activePressureWheel: WheelPos? = nil
    // レポート表示用のデータを1つのまとまりとして保持する。
    // 最初の表示で空シート（真っ黒な画面）になるのを防ぐため、
    // シートのトリガーとデータの準備を同じ状態にまとめて扱う。"item" のバインディングは
    // 値が非nilの時だけシートを生成するので、データが揃う前にシートが開く競合を避けられる。
    @State private var reportPayload: ReportPayload? = nil

    private let manualTemperatureRange: ClosedRange<Double> = -50...200
    private let manualPressureRange: ClosedRange<Double> = 0...400
    private let manualPressureDefault: Double = 210
    private let zoneButtonHeight: CGFloat = 112

    // シートに受け渡すレポート用のペイロード。
    // Identifiable にしておくことで .sheet(item:) にそのまま渡せる。
    private struct ReportPayload: Identifiable {
        let id = UUID()
        let summary: SessionHistorySummary
        let snapshot: SessionSnapshot
    }

    private var isHistoryMode: Bool { vm.loadedHistorySummary != nil }
    private var isManualInteractionActive: Bool {
        if isHistoryMode { return historyEditingEnabled }
        return isManualMode
    }
    private var canEditPressure: Bool {
        !isHistoryMode || historyEditingEnabled
    }
    private var historyBackgroundColor: Color {
        isHistoryMode ? Color.orange.opacity(0.08) : .clear
    }
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


    @ViewBuilder
    var body: some View {
        // iPad の場合だけ大きなUIに切り替える。どちらのレイアウトでも同じロジック（通信・データ更新）を共有する。
        // withSharedLifecycle を ViewBuilder 化しておくと、条件分岐の各ブランチが異なる View 型でも安全にまとめられる。
        withSharedLifecycle {
            if useSeniorIPadLayout {
                seniorFriendlyNavigation
            } else {
                standardNavigation
            }
        }
    }

    /// iPad + シニア向け設定がONの場合に true になる。デバイス判定で iPhone には影響を与えない。
    private var useSeniorIPadLayout: Bool {
        settings.enableSeniorIPadLayout && UIDevice.current.userInterfaceIdiom == .pad
    }

    /// 既存のタブに出ていた標準レイアウト。見た目はそのまま保持する。
    private var standardNavigation: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    topStatusRow

                    historyStatusCard

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
            .background(historyBackgroundColor)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(appTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showHistorySheet = true
                    } label: {
                        Label("History / 履歴", systemImage: "clock.arrow.circlepath")
                    }
                }

                ToolbarItem(placement: .principal) {
                    appTitleHeader
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        presentSessionReport()
                    } label: {
                        Label("Report", systemImage: "doc.richtext")
                    }
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
            .sheet(isPresented: $showHistorySheet) {
                HistoryListView(
                    history: history,
                    onSelect: { summary in loadHistorySummary(summary) },
                    onClose: { showHistorySheet = false }
                )
                .presentationDetents([.medium, .large])
            }
            // "item" バインディングなら、reportPayload が nil の間はシート自体が生成されない。
            // そのため「開いたが中身が空で真っ黒」という初回だけの不具合を防げる。
            .sheet(item: $reportPayload) { payload in
                NavigationStack {
                    SessionReportView(summary: payload.summary, snapshot: payload.snapshot)
                }
            }
        }
    }

    /// iPad の広い画面を活かし、数字を大きく読めるレイアウト。色や配置で入力箇所を強調する。
    private var seniorFriendlyNavigation: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 接続やスキャンの状態は既存のカードをそのまま流用。
                    sectionCard { connectBar }

                    historyStatusCard

                    sectionCard { seniorWheelSelector }

                    sectionCard { seniorZoneReadout }

                    sectionCard { seniorPressureReadout }

                    sectionCard { seniorMetaSummary }
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
            }
            .background(historyBackgroundColor)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Large Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { appTitleHeader }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        presentSessionReport()
                    } label: {
                        Label("Report", systemImage: "doc.richtext")
                    }
                    Button("Edit") { showMetaEditor = true }
                }
            }
            // 既存のモーダルをそのまま利用し、操作方法を変えない。
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
            .sheet(isPresented: $showHistorySheet) {
                HistoryListView(
                    history: history,
                    onSelect: { summary in loadHistorySummary(summary) },
                    onClose: { showHistorySheet = false }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $reportPayload) { payload in
                NavigationStack {
                    SessionReportView(summary: payload.summary, snapshot: payload.snapshot)
                }
            }
        }
    }

    /// ネットワーク接続や音声入力など、元の MeasureView が持っていた副作用をまとめて適用する。
    private func withSharedLifecycle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // content() を何度も呼ばないようにローカル定数へ格納。ViewBuilder はブランチごとの型を適切にまとめてくれる。
        let base = content()

        return base
            .background(historyBackgroundColor.ignoresSafeArea())
            .onAppear {
                if settings.enableWheelVoiceInput {
                    speech.requestAuth()
                    pressureSpeech.requestAuth()
                }
                ble.startScan()
                ble.autoConnectOnDiscover = settings.bleAutoConnect
                // registry の autoConnect=true だけを優先対象に
                let preferred = Set(registry.known.filter { $0.autoConnect }.map { $0.id })
                ble.setPreferredIDs(preferred)   // ← ここを関数呼び出しに
                if let current = vm.currentWheel {
                    selectedWheel = current
                }
                syncManualPressureDefaults(for: selectedWheel)
                history.refresh()
                print("[UI] MeasureView appear")
            }

            .onDisappear {
                vm.stopAll()
                if pressureSpeech.isRecording { pressureSpeech.stop() }
            }
            .onReceive(ble.temperatureStream) { sample in
                if !isHistoryMode {
                    vm.ingestBLESample(sample)
                }
            }
            .onReceive(vm.$currentWheel) { newWheel in
                if let newWheel { selectedWheel = newWheel }
            }
            .onChange(of: isManualMode) { _, newValue in
                guard !isHistoryMode else { return }
                if newValue {
                    clearManualFeedback(for: selectedWheel)
                    syncManualDefaults(for: selectedWheel)
                    syncManualPressureDefaults(for: selectedWheel)
                    showWheelDetails = true
                } else {
                    clearManualFeedback()
                    if pressureSpeech.isRecording { pressureSpeech.stop() }
                }
                activePressureWheel = nil
            }
            .onChange(of: selectedWheel) { _, newWheel in
                syncManualPressureDefaults(for: newWheel)
                activePressureWheel = nil
                if isManualInteractionActive {
                    clearManualFeedback(for: newWheel)
                    syncManualDefaults(for: newWheel)
                }
                showWheelDetails = false
            }
            .onChange(of: settings.enableWheelVoiceInput) { _, newValue in
                if newValue {
                    speech.requestAuth()
                    pressureSpeech.requestAuth()
                } else {
                    if speech.isRecording { speech.stop() }
                    if pressureSpeech.isRecording { pressureSpeech.stop() }
                }
            }
            .onReceive(vm.$results) { _ in
                if isManualInteractionActive { syncManualDefaults(for: selectedWheel) }
            }
            .onReceive(vm.$wheelMemos) { _ in
                if isManualInteractionActive { syncManualMemo(for: selectedWheel) }
            }
            .onReceive(vm.$wheelPressures) { _ in
                syncManualPressureDefaults(for: selectedWheel)
            }
            .onChange(of: historyEditingEnabled) { _, enabled in
                if enabled {
                    clearManualFeedback(for: selectedWheel)
                    syncManualDefaults(for: selectedWheel)
                    syncManualMemo(for: selectedWheel)
                    syncManualPressureDefaults(for: selectedWheel)
                } else {
                    activePressureWheel = nil
                }
            }
            .onChange(of: vm.loadedHistorySummary) { _, summary in
                deactivateHistoryEditing()
                if summary != nil {
                    isManualMode = false
                }
            }
            .onChange(of: showHistorySheet) { _, presenting in
                if presenting { history.refresh() }
            }
            .onReceive(vm.$sessionResetID) { _ in
                selectedWheel = .FL
                manualValues.removeAll()
                manualMemos.removeAll()
                manualPressureValues.removeAll()
                clearManualFeedback()
                showWheelDetails = false
                if isManualMode {
                    syncManualDefaults(for: .FL)
                    syncManualMemo(for: .FL)
                }
                syncManualPressureDefaults(for: .FL)
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
            .alert(
                "History error / 履歴エラー",
                isPresented: Binding(
                    get: { historyError != nil },
                    set: { if !$0 { historyError = nil } }
                )
            ) {
                Button("OK") { historyError = nil }
            } message: {
                Text(historyError ?? "")
            }
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

    // MARK: - Senior friendly iPad views

    @ViewBuilder
    private var seniorWheelSelector: some View {
        let wheels: [WheelPos] = [.FL, .FR, .RL, .RR]
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

        VStack(alignment: .leading, spacing: 12) {
            Text("Tyre position / タイヤ選択")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(wheels, id: \.self) { wheel in
                    // 既存のボタンをそのまま使い、Dynamic Type を拡大することで見やすさを向上させる。
                    wheelTile(for: wheel)
                        .environment(\.dynamicTypeSize, .accessibility3)
                        .padding(4)
                }
            }

            Text("ボタンは感覚で選びやすいように配置をそのまま残し、文字だけを大きくします。選択中のタイヤは色で強調されます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var seniorZoneReadout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Surface temperature / 路面温度")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                ForEach(zoneOrder(for: selectedWheel), id: \.self) { zone in
                    seniorZoneTile(for: zone)
                }
            }
        }
    }

    private func seniorZoneTile(for zone: Zone) -> some View {
        let value = displayValue(w: selectedWheel, z: zone)
        let stamp = captureTimestamp(for: selectedWheel, zone: zone)

        return VStack(alignment: .leading, spacing: 10) {
            Text(zoneDisplayName(zone))
                .font(.headline)
                .foregroundStyle(.secondary)

            // 数字を特に大きく。monospacedDigit で揃え、瞬時に確認できるようにする。
            Text(value)
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)

            if let stamp {
                Text("\(stamp.date)  \(stamp.time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("まだ値がありません / No reading yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var seniorPressureReadout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pressure / 内圧")
                .font(.title3.bold())

            HStack(alignment: .firstTextBaseline) {
                let display = pressureDetailDisplay(for: selectedWheel) ?? "-- kPa"
                Text(display)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    // 既存の詳細入力をそのまま開く。大画面でも動作は同じ。
                    showWheelDetails = true
                    activePressureWheel = selectedWheel
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
            }

            Text("測定値は数字を太字で表示し、編集ボタンで既存の入力シートを呼び出せます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var seniorMetaSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meta / 入力値の確認")
                .font(.title3.bold())

            seniorMetaRow(title: "TRACK", value: vm.meta.track)
            seniorMetaRow(title: "DATE", value: vm.meta.date)
            seniorMetaRow(title: "CAR", value: vm.meta.car)
            seniorMetaRow(title: "DRIVER", value: vm.meta.driver)
            seniorMetaRow(title: "TYRE", value: vm.meta.tyre)
            seniorMetaRow(title: "TIME", value: vm.meta.time)
            seniorMetaRow(title: "LAP", value: vm.meta.lap)
            seniorMetaRow(title: "CHECKER", value: vm.meta.checker)

            Text("iPhone と同じ入力値を読み込んでいるため、数字のチェックだけをiPadで行う運用でも混乱しません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func seniorMetaRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
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

    @ViewBuilder
    private var historyStatusCard: some View {
        if let summary = vm.loadedHistorySummary {
            historyActiveBanner(for: summary)
        }
    }

    private func historyActiveBanner(for summary: SessionHistorySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Viewing archived session / 履歴データを表示中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary.displayTitle)
                    .font(.headline)
                Text(summary.displayDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    historyNavigationButtons()
                }
                VStack(spacing: 8) {
                    historyNavigationButtons()
                }
            }

            historyEditingControls()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.orange.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.orange.opacity(0.35))
        )
    }

    @ViewBuilder
    private func historyNavigationButtons() -> some View {
        Button {
            showHistorySheet = true
        } label: {
            Label("History list / 履歴一覧", systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(.bordered)

        Button {
            restoreCurrentSession()
        } label: {
            Label("Return to live / 現在の測定に戻る", systemImage: "arrow.uturn.forward")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!vm.canRestoreCurrentSession())
    }

    @ViewBuilder
    private func historyEditingControls() -> some View {
        if historyEditingEnabled {
            VStack(alignment: .leading, spacing: 6) {
                Label("Editing enabled / 編集モード", systemImage: "pencil.circle.fill")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.green)

                Text("手動修正が可能です。計測は行われません。\nManual corrections are enabled; live capture stays paused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    deactivateHistoryEditing()
                } label: {
                    Label("Finish editing / 編集を終了", systemImage: "lock.fill")
                }
                .buttonStyle(.bordered)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("過去データは閲覧のみです。編集する場合は下のボタンを押してください。\nViewing archived data only. Enable editing to make manual adjustments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    activateHistoryEditing()
                } label: {
                    Label("Enable editing / 編集モードに入る", systemImage: "pencil")
                }
                .buttonStyle(.borderedProminent)
            }
        }
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

            if wheel != selectedWheel {
                let currentWheel = selectedWheel
                if hasPendingManualPressure(for: currentWheel) {
                    autoCommitManualPressureIfNeeded(for: currentWheel)
                    if manualPressureError(for: currentWheel) != nil {
                        return
                    }
                }
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

                if let pressureText = pressureTileDisplay(for: wheel) {
                    HStack(spacing: 6) {
                        Text("I.P.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(pressureText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
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

        if let pressureText = pressureDetailDisplay(for: wheel) {
            HStack(spacing: 6) {
                Image(systemName: "gauge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("I.P.: \(pressureText)")
                    .font(.callout.monospacedDigit())
            }
            .padding(.top, 6)
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

            pressureEntrySection(for: selectedWheel)

            zoneSelector(for: selectedWheel)

            wheelExtrasSection(for: selectedWheel)
        }
    }

    @ViewBuilder
    private func pressureEntrySection(for wheel: WheelPos) -> some View {
        // isLockedForHistory を一度だけ評価し、そのブール値に応じて枝分かれしたツリーを返す。
        // Group + .id による強制再構築よりシンプルな分岐にすることで、差分計算時の参照崩れを避ける。
        // 「各ブランチは完全に独立した View ツリー」という点を守れば、SwiftUI が古いノードを触って
        // EXC_BAD_ACCESS を起こすリスクを減らせる。
        let isLockedForHistory = isHistoryMode && !historyEditingEnabled

        if isLockedForHistory {
            lockedPressureSection(for: wheel)
        } else {
            editablePressureSection(for: wheel)
        }
    }

    /// 編集禁止状態の空気圧カード。
    /// 1) ロックされた View ツリーを丸ごと返すことで、差分アルゴリズムが中途半端に更新しないようにする。
    /// 2) overlay / footnote も同じツリーに閉じ込め、参照が取り違えないようにする。
    private func lockedPressureSection(for wheel: WheelPos) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                pressureEntryCard(for: wheel)

                historyLockedOverlay(text: "Enable editing to adjust pressure / 編集モードで空気圧を修正")
            }
            // 編集不可の状態はここだけで閉じ、他の分岐と共有しない。
            .disabled(true)

            historyLockedFootnote()
        }
    }

    /// 編集可能状態の空気圧カード。
    /// ロック解除時には overlay も footnote も描画せず、差分更新のパスを単純化する。
    private func editablePressureSection(for wheel: WheelPos) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            pressureEntryCard(for: wheel)
        }
    }

    private func wheelExtrasSection(for wheel: WheelPos) -> some View {
        DisclosureGroup(isExpanded: $showWheelDetails) {
            VStack(alignment: .leading, spacing: 14) {
                if isHistoryMode {
                    historyManualControls(for: wheel)
                } else {
                    manualModeToggle

                    if isManualMode {
                        manualEntrySection(for: wheel)
                    }

                    if settings.enableWheelVoiceInput {
                        voiceMemoSection(for: wheel)
                    }
                }

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

    private func historyLockedOverlay(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("View only / 閲覧専用", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func historyLockedFootnote() -> some View {
        Text("履歴は編集モードを有効にすると更新できます。\nEnable editing above to modify saved values.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func historyManualControls(for wheel: WheelPos) -> some View {
        if historyEditingEnabled {
            Label("Manual editing enabled / 手動編集中", systemImage: "pencil.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            manualEntrySection(for: wheel)

            if settings.enableWheelVoiceInput {
                voiceMemoSection(for: wheel)
            }
        } else {
            historyLockedMessage()
        }
    }

    private func historyLockedMessage() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("View only / 閲覧専用", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)

            Text("「編集モードに入る」を押すとこのセッションを手動で修正できます。\nActivate editing mode from the banner above to make manual adjustments.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
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

    private func pressureEntryCard(for wheel: WheelPos) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let manualText = manualPressureBinding(for: wheel).wrappedValue.trimmingCharacters(in: .whitespaces)
            let existingPressure = vm.wheelPressures[wheel].map { String(format: "%.1f", $0) }
            let displayText = !manualText.isEmpty ? manualText : (existingPressure ?? "")
            let showPlaceholder = displayText.isEmpty

            HStack(alignment: .center, spacing: 12) {
                Text("I.P.")
                    .font(.title3.weight(.semibold))

                pressureValueButton(for: wheel, displayText: displayText, showPlaceholder: showPlaceholder)

                Button {
                    commitManualPressure(for: wheel)
                    if manualPressureError(for: wheel) == nil {
                        activePressureWheel = nil
                    }
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
            }

            if settings.enableWheelVoiceInput,
               pressureSpeech.isRecording,
               pressureSpeech.currentWheel == wheel {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Recording…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if activePressureWheel == wheel && canEditPressure {
                PressureKeypad(
                    value: manualPressureBinding(for: wheel),
                    range: manualPressureRange,
                    onCommit: {
                        commitManualPressure(for: wheel)
                        if manualPressureError(for: wheel) == nil {
                            activePressureWheel = nil
                        }
                    },
                    onClose: {
                        activePressureWheel = nil
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            pressureAdjustRow(for: wheel)

            if settings.enableWheelVoiceInput {
                HStack {
                    if pressureSpeech.isRecording && pressureSpeech.currentWheel == wheel {
                        Button("Stop") {
                            pressureSpeech.stop()
                            let transcript = pressureSpeech.takeFinalText()
                            applyPressureTranscript(transcript, to: wheel)
                            if manualPressureError(for: wheel) == nil {
                                activePressureWheel = nil
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            let (prevWheel, prevText) = pressureSpeech.stopAndTakeText()
                            if let prevWheel, !prevText.isEmpty {
                                applyPressureTranscript(prevText, to: prevWheel)
                                if manualPressureError(for: prevWheel) == nil {
                                    activePressureWheel = nil
                                }
                            }
                            do {
                                try pressureSpeech.start(for: wheel)
                                Haptics.impactLight()
                            } catch {
                                if let error = error as? SpeechMemoManager.RecordingError {
                                    setManualPressureError(error.localizedDescription, for: wheel)
                                    setManualPressureSuccess(nil, for: wheel)
                                }
                            }
                        } label: {
                            Label("Voice input", systemImage: "mic.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!pressureSpeech.isAuthorized)
                    }
                    Spacer()
                }
            }

            if let error = manualPressureError(for: wheel) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            } else if let savedAt = manualPressureSuccessDate(for: wheel) {
                Text("Saved \(Self.manualTimeFormatter.string(from: savedAt))")
                    .font(.caption)
                    .foregroundStyle(Color.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: activePressureWheel == wheel)
    }

    private func pressureValueButton(for wheel: WheelPos, displayText: String, showPlaceholder: Bool) -> some View {
        Button {
            activePressureWheel = wheel
            Haptics.impactLight()
        } label: {
            HStack {
                if showPlaceholder {
                    Text("ex) \(Int(manualPressureDefault))kPa")
                        .foregroundStyle(Color.secondary.opacity(0.7))
                        .italic()
                } else {
                    Text("\(displayText) kPa")
                        .font(.title3.monospacedDigit())
                }
                Spacer()
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inner pressure value input")
        .accessibilityHint("Opens keypad to edit pressure")
    }

    private func pressureAdjustRow(for wheel: WheelPos) -> some View {
        HStack(spacing: 10) {
            pressureAdjustButton(title: "-5", delta: -5, for: wheel)
            pressureAdjustButton(title: "-1", delta: -1, for: wheel)

            Spacer(minLength: 12)

            pressureAdjustButton(title: "+1", delta: 1, for: wheel)
            pressureAdjustButton(title: "+5", delta: 5, for: wheel)
        }
    }

    private func pressureAdjustButton(title: String, delta: Double, for wheel: WheelPos) -> some View {
        Button(title) {
            adjustManualPressure(for: wheel, delta: delta)
        }
        .buttonStyle(.bordered)
        .font(.callout.weight(.semibold))
        .frame(minWidth: 48)
        .disabled(!canEditPressure)
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

    private struct PressureKeypad: View {
        @Binding var value: String
        let range: ClosedRange<Double>
        var onCommit: () -> Void
        var onClose: () -> Void

        private let digitColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        private let digits: [String] = ["7", "8", "9", "4", "5", "6", "1", "2", "3"]

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: digitColumns, spacing: 8) {
                    ForEach(digits, id: \.self) { symbol in
                        keypadButton(title: symbol) {
                            append(symbol)
                        }
                    }

                    keypadButton(title: ".") { appendDecimal() }
                    keypadButton(title: "0") { append("0") }
                    keypadButton(title: "⌫", systemImage: "delete.left") {
                        backspace()
                    }
                }

                HStack(spacing: 8) {
                    quickAdjustButton(label: "-1", delta: -1)
                    quickAdjustButton(label: "+1", delta: 1)
                }

                HStack {
                    Button("Clear") {
                        value = ""
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Close") {
                        onClose()
                    }
                    .buttonStyle(.bordered)

                    Button("Apply") {
                        onCommit()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }

        private func keypadButton(title: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 8)
                } else {
                    Text(title)
                        .font(.title3.monospacedDigit())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .buttonStyle(.bordered)
        }

        private func quickAdjustButton(label: String, delta: Double) -> some View {
            Button(label) {
                adjust(by: delta)
            }
            .buttonStyle(.bordered)
        }

        private func append(_ symbol: String) {
            if symbol == "0" && value == "0" { return }
            value.append(symbol)
            sanitize()
        }

        private func appendDecimal() {
            if value.contains(".") { return }
            if value.isEmpty { value = "0" }
            value.append(".")
            sanitize()
        }

        private func backspace() {
            if !value.isEmpty {
                value.removeLast()
            }
        }

        private func adjust(by delta: Double) {
            let current = Double(value) ?? 0
            let adjusted = min(max(current + delta, range.lowerBound), range.upperBound)
            value = Self.format(adjusted)
        }

        private func sanitize() {
            let allowed = Set("0123456789.")
            value = value.filter { allowed.contains($0) }

            if let dotIndex = value.firstIndex(of: ".") {
                let afterDot = value.index(after: dotIndex)
                let integerPart = String(value[..<dotIndex])
                let fractionalPart = value[afterDot...].replacingOccurrences(of: ".", with: "")
                value = integerPart + "." + fractionalPart
            } else {
                value = value.replacingOccurrences(of: ".", with: "")
            }

            while value.hasPrefix("0") && value.count > 1 && !value.hasPrefix("0.") {
                value.removeFirst()
            }
        }

        private static func format(_ value: Double) -> String {
            if value.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f", value)
            }
            return String(format: "%.1f", value)
        }
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

    private func manualPressureBinding(for wheel: WheelPos) -> Binding<String> {
        Binding(
            get: { manualPressureValues[wheel] ?? "" },
            set: { newValue in updateManualPressureValue(newValue, for: wheel) }
        )
    }

    private func adjustManualPressure(for wheel: WheelPos, delta: Double) {
        guard canEditPressure else { return }

        let rawText = manualPressureValues[wheel]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentValue: Double

        if let parsed = parseManualValue(rawText) {
            currentValue = parsed
        } else if let existing = vm.wheelPressures[wheel] {
            currentValue = existing
        } else {
            currentValue = manualPressureDefault
        }

        let clamped = min(max(currentValue + delta, manualPressureRange.lowerBound), manualPressureRange.upperBound)
        updateManualPressureValue(String(format: "%.1f", clamped), for: wheel)
    }

    private func updateManualValue(_ value: String, for wheel: WheelPos, zone: Zone) {
        var zoneMap = manualValues[wheel] ?? [:]
        zoneMap[zone] = value
        manualValues[wheel] = zoneMap

        setManualError(nil, for: wheel, zone: zone)
        setManualSuccess(nil, for: wheel, zone: zone)
    }

    private func updateManualPressureValue(_ value: String, for wheel: WheelPos) {
        manualPressureValues[wheel] = value
        setManualPressureError(nil, for: wheel)
        setManualPressureSuccess(nil, for: wheel)
    }

    private func hasPendingManualPressure(for wheel: WheelPos) -> Bool {
        guard canEditPressure else { return false }

        let trimmed = (manualPressureValues[wheel] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return false
        }

        guard let value = parseManualValue(trimmed) else {
            return true
        }

        if let existing = vm.wheelPressures[wheel] {
            if abs(existing - value) < 0.001 {
                return false
            }
        }

        return true
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

    private func manualPressureError(for wheel: WheelPos) -> String? {
        manualPressureErrors[wheel]
    }

    private func manualPressureSuccessDate(for wheel: WheelPos) -> Date? {
        manualPressureSuccess[wheel]
    }

    private func setManualPressureError(_ message: String?, for wheel: WheelPos) {
        if let message {
            manualPressureErrors[wheel] = message
        } else {
            manualPressureErrors.removeValue(forKey: wheel)
        }
    }

    private func setManualPressureSuccess(_ date: Date?, for wheel: WheelPos) {
        if let date {
            manualPressureSuccess[wheel] = date
        } else {
            manualPressureSuccess.removeValue(forKey: wheel)
        }
    }

    private func commitManualEntry(wheel: WheelPos, zone: Zone) {
        guard isManualInteractionActive else { return }
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

    private func commitManualPressure(for wheel: WheelPos) {
        guard canEditPressure else { return }
        let rawText = manualPressureValues[wheel] ?? ""
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setManualPressureError("Enter a pressure value", for: wheel)
            setManualPressureSuccess(nil, for: wheel)
            return
        }

        guard let value = parseManualValue(trimmed) else {
            setManualPressureError("Invalid number", for: wheel)
            setManualPressureSuccess(nil, for: wheel)
            return
        }

        guard manualPressureRange.contains(value) else {
            let minText = String(format: "%.0f", manualPressureRange.lowerBound)
            let maxText = String(format: "%.0f", manualPressureRange.upperBound)
            setManualPressureError("Value must be between \(minText) and \(maxText) kPa", for: wheel)
            setManualPressureSuccess(nil, for: wheel)
            return
        }

        vm.setPressure(value, for: wheel)
        updateManualPressureValue(String(format: "%.1f", value), for: wheel)
        setManualPressureError(nil, for: wheel)
        setManualPressureSuccess(Date(), for: wheel)
        Haptics.success()
    }

    private func autoCommitManualPressureIfNeeded(for wheel: WheelPos) {
        guard hasPendingManualPressure(for: wheel) else { return }
        commitManualPressure(for: wheel)
    }

    private func parseManualValue(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func persistManualMemo(for wheel: WheelPos) {
        guard isManualInteractionActive else { return }
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

    private func syncManualPressureDefaults(for wheel: WheelPos) {
        if let existing = vm.wheelPressures[wheel] {
            manualPressureValues[wheel] = String(format: "%.1f", existing)
        } else {
            manualPressureValues[wheel] = manualPressureValues[wheel] ?? ""
        }
    }

    private func clearManualFeedback(for wheel: WheelPos? = nil) {
        if let wheel {
            manualErrors[wheel] = nil
            manualSuccess[wheel] = nil
            manualMemoSuccess[wheel] = nil
            manualPressureErrors[wheel] = nil
            manualPressureSuccess[wheel] = nil
        } else {
            manualErrors.removeAll()
            manualSuccess.removeAll()
            manualMemoSuccess.removeAll()
            manualPressureErrors.removeAll()
            manualPressureSuccess.removeAll()
        }
    }

    private func applyPressureTranscript(_ text: String, to wheel: WheelPos) {
        guard canEditPressure else { return }
        let sanitized = text.replacingOccurrences(of: "[^0-9,\\.]", with: "", options: .regularExpression)
        let normalized = sanitized.replacingOccurrences(of: ",", with: ".")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            setManualPressureError("Voice input did not contain numbers", for: wheel)
            setManualPressureSuccess(nil, for: wheel)
            return
        }

        updateManualPressureValue(trimmed, for: wheel)
        commitManualPressure(for: wheel)
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
            if wheel != selectedWheel {
                let currentWheel = selectedWheel
                if hasPendingManualPressure(for: currentWheel) {
                    autoCommitManualPressureIfNeeded(for: currentWheel)
                    if manualPressureError(for: currentWheel) != nil {
                        return
                    }
                }
            }

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
        .disabled(isHistoryMode)
        .opacity(isHistoryMode ? 0.55 : 1)
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

    private func pressureTileDisplay(for wheel: WheelPos) -> String? {
        guard let pressure = vm.wheelPressures[wheel] else { return nil }
        return String(format: "%.1f kPa", pressure)
    }

    private func pressureDetailDisplay(for wheel: WheelPos) -> String? {
        guard let pressure = vm.wheelPressures[wheel] else { return nil }
        return String(format: "%.1f kPa", pressure)
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

    private func presentSessionReport() {
        // スナップショットとサマリを同時に作り、一つの構造体にまとめてから
        // シートに渡す。これにより「シートが開いた瞬間にデータがまだ nil」という
        // タイミングずれを根本的に排除する。
        let snapshot = vm.makeLiveSnapshotForReport()
        let summary = vm.makeLiveSummary(for: snapshot)
        reportPayload = ReportPayload(summary: summary, snapshot: snapshot)
    }

    private func loadHistorySummary(_ summary: SessionHistorySummary) {
        guard let snapshot = history.snapshot(for: summary) else {
            historyError = "履歴の読み込みに失敗しました / Failed to load archived session"
            return
        }
        deactivateHistoryEditing()
        isManualMode = false
        vm.loadHistorySnapshot(snapshot, summary: summary)
        showHistorySheet = false
    }

    private func restoreCurrentSession() {
        vm.exitHistoryMode()
        deactivateHistoryEditing()
    }

    private func activateHistoryEditing() {
        guard isHistoryMode else { return }
        if !historyEditingEnabled {
            historyEditingEnabled = true
            clearManualFeedback(for: selectedWheel)
            syncManualDefaults(for: selectedWheel)
            syncManualMemo(for: selectedWheel)
            syncManualPressureDefaults(for: selectedWheel)
            showWheelDetails = true
        }
    }

    private func deactivateHistoryEditing() {
        if historyEditingEnabled {
            historyEditingEnabled = false
        }
        manualValues.removeAll()
        manualMemos.removeAll()
        manualPressureValues.removeAll()
        clearManualFeedback()
        if speech.isRecording { speech.stop() }
        if pressureSpeech.isRecording { pressureSpeech.stop() }
        showWheelDetails = false
        syncManualDefaults(for: selectedWheel)
        syncManualMemo(for: selectedWheel)
        syncManualPressureDefaults(for: selectedWheel)
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

                if settings.enableGoogleDriveUpload, let metadata = vm.lastCSVMetadata, let url = vm.lastCSV {
                    Task { await driveService.upload(csvURL: url, metadata: metadata) }
                }

                if settings.enableICloudUpload, let fallbackURL = vm.lastLegacyCSV ?? vm.lastCSV {
                    folderBM.upload(file: fallbackURL, metadata: vm.lastCSVMetadata)
                }
            }
            .buttonStyle(.borderedProminent)

            uploadStatusView
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }



    // BLEの状態、操作、診断をまとめたカード
    private var connectBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    bleHeader
                    captureStatusRow
                }

                Spacer(minLength: 0)

                liveTemperatureBadge
            }

            if let entry = vm.autosaveStatusEntry {
                noticeRow(for: entry)
            }

            connectButtons
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func noticeRow(for entry: UILogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: entry.level.iconName)
                .foregroundStyle(entry.level.tintColor)
                .font(.body)

            Text(compactNoticeMessage(for: entry))
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.level.tintColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Text(entry.createdAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(entry.level.tintColor.opacity(0.12))
        )
    }

    private func compactNoticeMessage(for entry: UILogEntry) -> String {
        if entry.category == .autosave {
            return "Autosave restored"
        }
        return entry.message
    }

    private var liveTemperatureBadge: some View {
        let valueText: String
        if let live = vm.liveTemperatureC, live.isFinite {
            valueText = String(format: "%.1f", live)
        } else {
            valueText = "--"
        }

        return HStack(alignment: .lastTextBaseline, spacing: 6) {
            Image(systemName: "thermometer")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(valueText)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text("℃")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var uploadStatusView: some View {
        let driveState = driveService.uploadState
        let iCloudState = folderBM.statusLabel
        let showDrive = settings.enableGoogleDriveUpload && driveState != .idle
        let showICloud = settings.enableICloudUpload && iCloudState != .idle

        if showDrive || showICloud {
            HStack(spacing: 12) {
                if showICloud { iCloudStatusChip(for: iCloudState) }
                if showDrive { driveStatusChip(for: driveState) }
            }
        } else if !settings.enableGoogleDriveUpload && !settings.enableICloudUpload {
            Label("Cloud uploads disabled", systemImage: "icloud.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func iCloudStatusChip(for state: UploadUIState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .uploading:
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                Text("Saving to iCloud…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done:
            Label("iCloud upload complete", systemImage: "checkmark.icloud.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message.isEmpty ? "iCloud upload failed" : message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func driveStatusChip(for state: UploadUIState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .uploading:
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                Text("Uploading to Drive…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .done:
            Label("Drive upload complete", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message.isEmpty ? "Drive upload failed" : message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
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
            HStack(spacing: 10) {
                Button(scanButtonTitle()) { scanOrDisconnect() }
                    .buttonStyle(.borderedProminent)
                HStack(spacing: 8) {
                    Button("Devices…") { showConnectSheet = true }
                        .buttonStyle(.bordered)

                    notifyMetrics
                }
            }

            VStack(spacing: 8) {
                Button(scanButtonTitle()) { scanOrDisconnect() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                HStack(alignment: .top, spacing: 8) {
                    Button("Devices…") { showConnectSheet = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                    notifyMetrics
                }
            }
        }
    }

    private var notifyMetrics: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "Hz: %.1f", ble.notifyHz))
            Text("N: \(ble.notifyCountUI)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
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
        .environmentObject(fixtures.driveService)
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
        .environmentObject(fixtures.driveService)
        .environmentObject(fixtures.bluetooth)
        .environmentObject(fixtures.registry)
        .environmentObject(fixtures.logStore)
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}
