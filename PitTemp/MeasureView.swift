import SwiftUI

struct MeasureView: View {
    @EnvironmentObject var vm: SessionViewModel
    @EnvironmentObject var folderBM: FolderBookmark
    @EnvironmentObject var settings: SettingsStore

    @StateObject private var speech = SpeechMemoManager()

    @State private var showRaw = false
    @State private var focusTick = 0
    @State private var showMetaEditor = false

    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerReadOnly
                    grid
                    if vm.isCaptureActive {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Live Temp (last \(Int(settings.chartWindowSec))s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            MiniTempChart(data: vm.live)
                        }
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            // この画面だけで HID を稼働
            .overlay(alignment: .bottomTrailing) {
                HIDTextFieldCaptureView(
                    onLine: { vm.ingestLine($0) },
                    onSpecial: { vm.receiveSpecial($0) },
                    onBuffer: { vm.ingestBufferSnapshot($0) },
                    isActive: vm.isCaptureActive || showRaw,
                    showField: $showRaw,
                    focusTick: $focusTick
                )
                .frame(width: showRaw ? 280 : 1, height: showRaw ? 36 : 1)
                .padding(.trailing, 12)
                .padding(.bottom, showRaw ? 64 : 12)
            }
            .navigationTitle("TrackTemp")
            .toolbar {
                Button("Edit") { showMetaEditor = true }
            }
            .sheet(isPresented: $showMetaEditor) {
                if settings.metaInputMode == .voice {
                    MetaVoiceEditorView()
                        .environmentObject(vm)
                        .presentationDetents([.medium, .large])
                } else {
                    MetaEditorView()
                        .environmentObject(vm)
                        .presentationDetents([.medium, .large])
                }
            }
        }
        .onAppear { speech.requestAuth() }
        .onDisappear { vm.stopAll() }
    }

    // MARK: - メタ情報（ラベル表示のみ）
    private var headerReadOnly: some View {
        VStack(alignment: .leading, spacing: 6) {
            MetaRow(label: "TRACK",   value: vm.meta.track)
            MetaRow(label: "DATE",    value: vm.meta.date)
            MetaRow(label: "CAR",     value: vm.meta.car)
            MetaRow(label: "DRIVER",  value: vm.meta.driver)
            MetaRow(label: "TYRE",    value: vm.meta.tyre)
            HStack {
                MetaRow(label: "TIME", value: vm.meta.time)
                Spacer(minLength: 12)
                MetaRow(label: "LAP",  value: vm.meta.lap)
            }
            MetaRow(label: "CHECKER", value: vm.meta.checker)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func MetaRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "-" : value).font(.headline)
        }
    }

    // MARK: - 4輪×3ゾーンのグリッド
    private var grid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            wheelCard(.FL); wheelCard(.FR); wheelCard(.RL); wheelCard(.RR)
        }
    }

    private func wheelCard(_ w: WheelPos) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(w)).font(.headline)

            // 音声メモ
            HStack {
                Text("I.P.").font(.caption2)
                Spacer()
                if speech.isRecording && speech.currentWheel == w {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Button("Stop") {
                        speech.stop()
                        let t = speech.takeFinalText()
                        if !t.isEmpty {
                            let vmRef = vm   // ← EnvironmentObjectをローカルに退避
                            Task { @MainActor in
                                vmRef.appendMemo(t, to: w)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        let (prevWheel, prevText) = speech.stopAndTakeText()
                        if let pw = prevWheel, !prevText.isEmpty {
                            let vmRef = vm   // ← 退避
                            Task { @MainActor in
                                vmRef.appendMemo(prevText, to: pw)
                            }
                        }
                        try? speech.start(for: w)
                        Haptics.impactLight()
                    } label: {
                        Label("MEMO", systemImage: "mic.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!speech.isAuthorized)
                }
            }

            if let memo = vm.wheelMemos[w], !memo.isEmpty {
                Text(memo)
                    .font(.footnote)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            // 温度セル
            Text("TEMP.").font(.caption2)
            HStack(spacing: 8) {
                // 実車の位置関係：左輪= OUT-CL-IN / 右輪= IN-CL-OUT
                let zones: [Zone] = (w == .FL || w == .RL) ? [.OUT, .CL, .IN] : [.IN, .CL, .OUT]
                ForEach(zones, id: \.self) { z in
                    zoneButton(w, z)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
    }

    private func zoneButton(_ w: WheelPos, _ z: Zone) -> some View {
        Button {
            vm.tapCell(wheel: w, zone: z)
            focusTick &+= 1
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.18))
                HStack {
                    Text(z.rawValue).font(.caption2).opacity(0.85)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .overlay(alignment: .bottomLeading) {
                if vm.currentWheel == w && vm.currentZone == z {
                    let p = min(vm.elapsed / Double(settings.durationSec), 1.0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                        Capsule().fill(Color.blue.opacity(0.6)).frame(width: CGFloat(p) * 80, height: 4)
                    }
                    .padding(.bottom, 6)
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text(String(format: "%.1fs", max(0, Double(settings.durationSec) - vm.elapsed)))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .padding(.top, 6)
                }
            }
            .overlay {
                // 数字は大きく、ゾーンで少し縦位置をずらす
                let y: CGFloat = (z == .OUT ? -18 : (z == .CL ? 0 : 18))
                Text(displayValue(w: w, z: z))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .offset(y: y)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
    }

    private func title(_ w: WheelPos) -> String {
        switch w {
        case .FL: return "Front Left"
        case .FR: return "Front Right"
        case .RL: return "Rear Left"
        case .RR: return "Rear Right"
        }
    }

    private func displayValue(w: WheelPos, z: Zone) -> String {
        if let r = vm.results.first(where: { $0.wheel == w && $0.zone == z }) {
            return r.peakC.isFinite ? String(format: "%.1f", r.peakC) : "--"
        }
        if vm.currentWheel == w && vm.currentZone == z {
            return vm.latestValueText
        }
        return "--"
    }

    // MARK: - 下部バー
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(showRaw ? "Hide Raw" : "Show Raw") {
                showRaw.toggle()
                focusTick &+= 1
            }
            .buttonStyle(.bordered)

            Button("Stop") { vm.stopAll() }
                .buttonStyle(.bordered)

            Spacer()

            Button("Next") { vm.receiveSpecial("<RET>") }
                .buttonStyle(.bordered)

            // Export → iCloud Upload
            Button {
                if let url = vm.ensureCSV() {
                    folderBM.upload(file: url)
                }
            } label: {
                switch folderBM.statusLabel {
                case .idle: Text("Upload")
                case .uploading: Label("Uploading…", systemImage: "icloud.and.arrow.up")
                case .done: Label("Uploaded", systemImage: "checkmark.icloud")
                case .failed: Label("Retry", systemImage: "exclamationmark.icloud")
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Export CSV") { vm.exportCSV() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
