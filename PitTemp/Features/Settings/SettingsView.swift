//
//  SettingsView.swift
//  PitTemp
//
//  役割: 共有フォルダの指定、測定窓/グラフ幅など各種設定
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var vm: SessionViewModel
    @EnvironmentObject var folderBM: FolderBookmark
    @EnvironmentObject var settings: SettingsStore   // ← 追加：設定は SettingsStore に集約
    @EnvironmentObject var driveService: GoogleDriveService

    @State private var showPicker = false
    @EnvironmentObject var registry: DeviceRegistry
    @EnvironmentObject var uiLog: UILogStore
    @State private var driveAlertMessage: String? = nil
    @State private var showLogViewer = false

    
    var body: some View {
        NavigationStack {
            Form {
                // プロファイル
                Section("Profile") {
                    // 端末のニックネーム。入力済みなら保存フォルダ名にも反映し、
                    // 「どのフォルダが自分の保存分か」を直感的に追跡できるようにする。
                    TextField("Device nickname (saved into folder names)", text: $settings.deviceNickname)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                // 共有フォルダ
                Section("Shared Folder") {
                    Toggle("Upload to iCloud shared folder", isOn: $settings.enableICloudUpload)

                    if settings.enableICloudUpload {
                        HStack {
                            Text("Upload Folder")
                            Spacer()
                            Text(folderBM.folderURL?.lastPathComponent ?? "Not set")
                                .foregroundStyle(.secondary)
                        }
                        Button("Choose iCloud Folder…") { showPicker = true }
                    } else {
                        Label("iCloud upload is disabled. CSV files will remain on this device until you re-enable it.", systemImage: "icloud.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Export") {
                    Toggle("Upload to cloud after Save", isOn: $settings.uploadAfterSave)
                    // 追加説明: 計測を保存した直後にクラウドへ上げるかどうかを
                    // ワンタップで切り替える。オフにすると「Save ＝ローカル保存のみ」
                    // となり、あとで必要な分だけ Library などから手動アップロード
                    // するといった運用ができる。
                    Text("トグルをオフにすると、この端末内にのみ保存します。オンにすると通信状態を見ながらクラウドへキューイングまたは即時アップロードします。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Google Drive") {
                    Toggle("Upload to Google Drive", isOn: $settings.enableGoogleDriveUpload)

                    if settings.enableGoogleDriveUpload {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField(
                                "Parent folder ID",
                                text: Binding(
                                    get: { driveService.parentFolderID },
                                    set: { driveService.setParentFolder(id: $0) }
                                )
                            )
                            .textInputAutocapitalization(.none)
                            .autocorrectionDisabled()

                            TextField(
                                "Manual access token (optional)",
                                text: Binding(
                                    get: { driveService.manualAccessToken },
                                    set: { driveService.setManualAccessToken($0) }
                                )
                            )
                            .textInputAutocapitalization(.none)
                            .autocorrectionDisabled()
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if driveService.supportsInteractiveSignIn {
                                HStack {
                                    Button {
                                        Task {
                                            do {
                                                try await driveService.signIn()
                                            } catch {
                                                driveAlertMessage = error.localizedDescription
                                            }
                                        }
                                    } label: {
                                        Label("Sign in", systemImage: "person.crop.circle.badge.plus")
                                    }

                                    Button(role: .destructive) {
                                        driveService.signOut()
                                    } label: {
                                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                }
                            } else {
                                Label("Interactive Google sign-in is unavailable in this build. Provide an access token manually or add the GoogleSignIn SDK.", systemImage: "info.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button {
                                Task { await driveService.refreshFileList() }
                            } label: {
                                Label("Refresh Drive listing", systemImage: "arrow.clockwise")
                            }
                            .disabled(!settings.enableGoogleDriveUpload || !driveService.isConfigured())

                            if let message = driveService.lastErrorMessage, !message.isEmpty {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    } else {
                        Label("Drive upload is disabled. Enable it if you need automatic uploads to Google Drive.", systemImage: "cloud.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Session identifiers (Session ID / UUID)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Session ID は人が読める短いラベル、UUID は機械向けの絶対識別子です。両方を残すことで、測定担当者はラベルで会話し、管理者や開発者は UUID で衝突なくログを突き合わせられます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("クラウドにアップロードされた CSV にも両者を埋め込みます。アップロード済みファイル単体でも、いつ・どの端末で記録された計測か追跡できるようにしています。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("読み方の目安: ラベルは '20240605-142310_IPHONE-1A2B_X7K9' のように日時+端末+短いランダム値。UUID は '550e8400-e29b-41d4-a716-446655440000' のような固定長文字列で、ログ連携やサポート問い合わせで引用してください。")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Meta Input") {
                    Picker("Mode", selection: Binding(
                        get: { settings.metaInputMode },
                        set: { settings.metaInputMode = $0 }
                    )) {
                        ForEach(SettingsStore.MetaInputMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }

                    NavigationLink("Voice Keywords") {
                        MetaVoiceKeywordSettingsView()
                    }
                }


                // 測定パラメータ
                Section("Measurement") {
                    Stepper(value: $settings.autoStopLimitSec, in: 5...120) {
                        Text("Auto-stop limit: \(settings.autoStopLimitSec) s")
                    }
                    Stepper(value: $settings.chartWindowSec, in: 3...60, step: 1) {
                        Text("Chart Width: \(Int(settings.chartWindowSec)) s")
                    }
                    Toggle("Autofill Date/Time if empty", isOn: $settings.autofillDateTime)

                    Toggle("Enable tyre voice input controls", isOn: $settings.enableWheelVoiceInput)
                        .tint(.orange)
                        .accessibilityHint("When off, pressure and memo voice buttons stay hidden by default")

                    // 👇 追加：Zone順序の切替
                    Picker(
                        "Zone order",
                        selection: Binding(
                            get: { settings.zoneOrderEnum },
                            set: { settings.zoneOrderEnum = $0 }
                        )
                    ) {
                        ForEach(SettingsStore.ZoneOrder.allCases) { o in
                            Text(o.label).tag(o)
                        }
                    }
                }

                Section("Accessibility") {
                    Toggle("Senior layout (large digits for iPad mini)", isOn: $settings.enableSeniorLayout)
                    Label("Increases key numbers and tap areas on iPad to help senior measurers avoid misreading.", systemImage: "textformat.size")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if UIDevice.current.userInterfaceIdiom == .pad {
                        if settings.enableSeniorLayout {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Fine-tune which numbers get larger.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text("Each slider below targets a specific area: measurement buttons, wheel tiles, summary chips, live badge, metadata rows, and the inner-pressure keypad.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                // 個別にフォント倍率を調整。"x1.3" など倍率を明示することで、利用者が安心して操作できるようにする。
                                Slider(
                                    value: Binding(
                                        get: { settings.seniorZoneFontScale },
                                        set: { settings.seniorZoneFontScale = $0 }
                                    ),
                                    in: 0.8...2.0,
                                    step: 0.1
                                ) {
                                    Text("Zone digits (IN/CL/OUT)")
                                } minimumValueLabel: {
                                    Text("x0.8")
                                } maximumValueLabel: {
                                    Text("x2.0")
                                }
                                Text("Affects the big IN/CL/OUT buttons in Measure view.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Current: x\(settings.seniorZoneFontScale, specifier: "%.1f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Slider(
                                    value: Binding(
                                        get: { settings.seniorTileFontScale },
                                        set: { settings.seniorTileFontScale = $0 }
                                    ),
                                    in: 0.8...2.0,
                                    step: 0.1
                                ) {
                                    Text("Tyre tile summaries")
                                } minimumValueLabel: {
                                    Text("x0.8")
                                } maximumValueLabel: {
                                    Text("x2.0")
                                }
                                Text("Enlarges the IN/CL/OUT numbers shown inside each tyre position card.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Current: x\(settings.seniorTileFontScale, specifier: "%.1f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Slider(
                                    value: Binding(
                                        get: { settings.seniorChipFontScale },
                                        set: { settings.seniorChipFontScale = $0 }
                                    ),
                                    in: 0.8...2.0,
                                    step: 0.1
                                ) {
                                    Text("Summary chips (AVG/MAX)")
                                } minimumValueLabel: {
                                    Text("x0.8")
                                } maximumValueLabel: {
                                    Text("x2.0")
                                }
                                Text("Controls the averages / max chips beneath each wheel header.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Current: x\(settings.seniorChipFontScale, specifier: "%.1f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Slider(
                                    value: Binding(
                                        get: { settings.seniorLiveFontScale },
                                        set: { settings.seniorLiveFontScale = $0 }
                                    ),
                                    in: 0.8...2.0,
                                    step: 0.1
                                ) {
                                    Text("Live temperature badge")
                                } minimumValueLabel: {
                                    Text("x0.8")
                                } maximumValueLabel: {
                                    Text("x2.0")
                                }
                                Text("Enlarges the floating badge showing the most recent temperature.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Current: x\(settings.seniorLiveFontScale, specifier: "%.1f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Slider(
                                    value: Binding(
                                        get: { settings.seniorMetaFontScale },
                                        set: { settings.seniorMetaFontScale = $0 }
                                    ),
                                    in: 0.8...2.0,
                                    step: 0.1
                                ) {
                                    Text("Metadata rows (TRACK/DATE etc.)")
                                } minimumValueLabel: {
                                    Text("x0.8")
                                } maximumValueLabel: {
                                    Text("x2.0")
                                }
                                Text("Adjusts the header fields at the top of Measure view.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Current: x\(settings.seniorMetaFontScale, specifier: "%.1f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Slider(
                                    value: Binding(
                                        get: { settings.seniorPressureFontScale },
                                        set: { settings.seniorPressureFontScale = $0 }
                                    ),
                                    in: 0.8...2.0,
                                    step: 0.1
                                ) {
                                    Text("Inner pressure input")
                                } minimumValueLabel: {
                                    Text("x0.8")
                                } maximumValueLabel: {
                                    Text("x2.0")
                                }
                                Text("Grows the pressure label, value, and keypad buttons for easier entry.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Current: x\(settings.seniorPressureFontScale, specifier: "%.1f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Turn on Senior layout to adjust each font size.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Bluetooth") {
                    Toggle("Auto connect first seen device", isOn: $settings.bleAutoConnect)
                        .onChange(of: settings.bleAutoConnect) { _, newValue in
                            // ここは必要なら反映を書く（MeasureView 側で反映しているなら何もしなくてOK）
                            // 例）ble.autoConnectOnDiscover = newValue
                            // 'onChange(of:perform:)' was deprecated in iOS 17.0: Use `onChange` with a two or zero parameter action closure instead.
                        }

                    NavigationLink("Device Registry") {
                        DeviceRegistryView()
                            .environmentObject(registry) // MeasureView や App で注入済みなら OK
                    }

                    Text("If ON, the app connects to the first matching device it discovers. Turn OFF to pick a device manually.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Debug") {
                    Button {
                        showLogViewer = true
                    } label: {
                        Label("View Debug Logs", systemImage: "list.bullet.rectangle")
                    }
                    Text("通信トラブル時はこのログをコピー/共有してもらうと解析が早くなります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                
                // デバイス & ロケーション
                Section("Device & Location") {
                    HStack {
                        let status = LocationLogger.shared.authStatus
                        Text("Location: \(String(describing: status))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Enable") { LocationLogger.shared.request() }
                    }
                }

                Section("Autosave") {
                    Button(role: .destructive) {
                        vm.clearAutosave()
                    } label: {
                        Label("Reset Autosave Snapshot", systemImage: "trash")
                    }

                    if let entry = vm.autosaveStatusEntry {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latest status: \(entry.message)")
                                .font(.footnote)
                                .foregroundStyle(entry.level.tintColor)
                            Text(entry.createdAt, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    if recentAutosaveEntries.isEmpty {
                        Text("No autosave activity logged yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentAutosaveEntries) { entry in
                            HStack(spacing: 12) {
                                Image(systemName: entry.level.iconName)
                                    .foregroundStyle(entry.level.tintColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.message)
                                        .font(.footnote)
                                    Text(entry.createdAt, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false   // フォルダは1つで十分
        ) { result in
            switch result {
            case .success(let urls):
                if let first = urls.first { folderBM.save(url: first) }
            case .failure(let error):
                print("Folder pick failed:", error)
            }
        }
        .sheet(isPresented: $showLogViewer) {
            LogViewerView()
        }
        .alert("Google Drive", isPresented: Binding(
            get: { driveAlertMessage != nil },
            set: { if !$0 { driveAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { driveAlertMessage = nil }
        } message: {
            Text(driveAlertMessage ?? "")
        }
        .onChange(of: settings.enableGoogleDriveUpload) { _, newValue in
            if !newValue {
                driveService.resetUIState()
            }
        }
        .onChange(of: settings.enableICloudUpload) { _, newValue in
            if !newValue {
                folderBM.statusLabel = .idle
            }
        }
    }

    private var recentAutosaveEntries: [UILogEntry] {
        let autosaveEntries = uiLog.entries.filter { $0.category == .autosave }
        return Array(autosaveEntries.suffix(5).reversed())
    }
}

private struct MetaVoiceKeywordSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("How it works") {
                Text("各項目の前に複数のキーワードを設定できます。カンマ（,）または改行で区切ってください。空欄にするとデフォルト値が使われます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Keywords") {
                ForEach(SettingsStore.MetaVoiceField.allCases) { field in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(field.label.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(
                            "Keywords",
                            text: settings.bindingForMetaVoiceKeyword(field: field),
                            prompt: Text(settings.defaultMetaVoiceKeywords(for: field).joined(separator: ", "))
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button("Restore defaults") {
                    settings.resetMetaVoiceKeywords()
                }
                .tint(.orange)
            }
        }
        .navigationTitle("Voice Keywords")
    }
}
