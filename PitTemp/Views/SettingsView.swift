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

    
    var body: some View {
        NavigationStack {
            Form {
                // プロファイル
                Section("Profile") {
                    // checker は SettingsStore 側に寄せていないため、必要なら移設可。
                    // ここでは既存キーを流用する形で統一するため SettingsStore に追加して使うのが綺麗です。
                    // ひとまずキーをそのまま使いたい場合は、下行のように @AppStorage を残すか、
                    // SettingsStore に @AppStorage("profile.checker") を追加して $settings.checker にしてください。
                    TextField("Checker", text: .init(
                        get: { UserDefaults.standard.string(forKey: "profile.checker") ?? "" },
                        set: { UserDefaults.standard.set($0, forKey: "profile.checker") }
                    ))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                    HStack {
                        TextField("Thermometer (HR-...)", text: $settings.hr2500ID) // ← SettingsStore を参照
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    Button("Show Welcome on next launch") {
                        UserDefaults.standard.set(false, forKey: "onboarded")
                    }
                    .tint(.orange)
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

                
                // デバイス & ロケーション
                Section("Device & Location") {
                    TextField("HR2500 ID (label / asset tag)", text: $settings.hr2500ID)

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
