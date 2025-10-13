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
    @State private var showRaw = false
    @State private var focusTick = 0
    @State private var showMetaEditor = false
    @State private var showConnectSheet = false
    @State private var shareURL: URL?
    @State private var showUploadAlert = false
    @State private var uploadedPathText = ""
    @State private var uploadMessage = ""
    
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
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
                    grid
                    

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
            print("[UI] MeasureView appear")
        }

        .onDisappear {
            vm.stopAll()
        }
        .onReceive(ble.temperatureStream) { sample in
            vm.ingestBLESample(sample)
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

    private var grid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            wheelCard(.FL); wheelCard(.FR); wheelCard(.RL); wheelCard(.RR)
        }
    }

    private func wheelCard(_ w: WheelPos) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(w)).font(.headline)
            // 音声メモ（元の挙動）
            HStack {
                Text("I.P.").font(.caption2); Spacer()
                if speech.isRecording && speech.currentWheel == w {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Button("Stop") {
                        speech.stop()
                        let t = speech.takeFinalText()
                        if !t.isEmpty { let vmRef = vm; Task { @MainActor in vmRef.appendMemo(t, to: w) } }
                    }.buttonStyle(.bordered)
                } else {
                    Button {
                        let (pw, prevText) = speech.stopAndTakeText()
                        if let pw, !prevText.isEmpty {
                            let vmRef = vm; Task { @MainActor in vmRef.appendMemo(prevText, to: pw) }
                        }
                        try? speech.start(for: w); Haptics.impactLight()
                    } label: { Label("MEMO", systemImage: "mic.fill") }
                    .buttonStyle(.bordered)
                    .disabled(!speech.isAuthorized)
                }
            }
            if let memo = vm.wheelMemos[w], !memo.isEmpty {
                Text(memo).font(.footnote).lineLimit(3).textSelection(.enabled)
            }

            Text("TEMP.").font(.caption2)
            HStack(spacing: 8) {
                let zones: [Zone] = (w == .FL || w == .RL) ? [.OUT, .CL, .IN] : [.IN, .CL, .OUT]
                ForEach(zones, id: \.self) { z in zoneButton(w, z) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
    }

    private func zoneButton(_ w: WheelPos, _ z: Zone) -> some View {
        Button {
            vm.tapCell(wheel: w, zone: z); focusTick &+= 1
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.18))
                HStack { Text(z.rawValue).font(.caption2).opacity(0.85); Spacer(minLength: 0) }
                    .padding(.horizontal, 10).padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .overlay(alignment: .bottomLeading) {
                if vm.currentWheel == w && vm.currentZone == z {
                    let p = min(vm.elapsed / Double(settings.durationSec), 1.0)
                    ZStack(alignment: .leading) {
                        Capsule().foregroundStyle(.white.opacity(0.08)).frame(height: 4)
                        Capsule().foregroundStyle(.blue.opacity(0.6)).frame(width: CGFloat(p) * 80, height: 4)
                    }
                    .padding(.bottom, 6)
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text(String(format: "%.1fs", max(0, Double(settings.durationSec) - vm.elapsed)))
                            .font(.caption2).monospacedDigit()
                    }
                    .padding(.top, 6)
                }
            }
            .overlay {
                let y: CGFloat = (z == .OUT ? -18 : (z == .CL ? 0 : 18))
                Text(displayValue(w: w, z: z))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.3).offset(y: y)
                    .allowsHitTesting(false)
            }
        }.buttonStyle(.plain)
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
